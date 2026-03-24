/*
 * indicators/cvd.cpp
 * CVD — Cumulative Volume Delta, panel séparé.
 *
 * Algorithme (fidèle à CVD.cpp original) :
 *
 *   Pour chaque barre i du TF courant :
 *     1. AnchorPeriod reset : si le jour (Unix/86400) change entre i et i+1
 *        → prevClose = 0
 *     2. Trouver dans QChart1 (sub-TF 1 min) les barres appartenant à la barre i :
 *        fenêtre [curTimestamps[i] .. curTimestamps[i-1][  (ou +tfSec pour la dernière)
 *     3. Pour chaque barre sub-TF :
 *        if close > open  → runningDelta += volume
 *        if close < open  → runningDelta -= volume
 *        tracker High/Low du delta cumulé
 *     4. CloseBuffer[i] = prevClose + runningDelta
 *        OpenBuffer[i]  = prevClose
 *        High[i]        = max du running delta depuis prevClose
 *        Low[i]         = min du running delta depuis prevClose
 *
 * Le sub-TF (QChart1) est passé via ctx->ref* :
 *   refHighs      = volumes QChart1 (réutilisé pour stocker les volumes)
 *   refLows       = closes QChart1
 *   refOpens      = opens  QChart1
 *   refTimestamps = timestamps Unix QChart1
 *   refCount      = nombre de barres QChart1
 *   curTimestamps = timestamps Unix TF courant
 *
 * AnchorPeriod = 1 jour (86400 secondes) — reset à minuit UTC
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <objbase.h>
#include <gdiplus.h>
#include <cstdio>
#include <cstring>
#include <cmath>
#include "indicator_api.h"

using namespace Gdiplus;
using namespace Gdiplus::DllExports;

static const int MAX_B = 4096;

/* ── Recherche bisection : premier indice dans refTS où refTS[k] >= target ── */
/* refTS est trié en ordre croissant (0=plus ancien) */
static int LowerBound(const double* refTS, int refN, double target)
{
    int lo=0, hi=refN;
    while (lo<hi){
        int mid=(lo+hi)/2;
        if (refTS[mid]<target) lo=mid+1;
        else hi=mid;
    }
    return lo;
}

/* ── Bouton X ────────────────────────────────────────────────────────────── */
static void DrawCloseBtn(GpGraphics* g, float bx, float by, float bsz)
{
    GpSolidFill* br=nullptr; GdipCreateSolidFill(0xFFE8E8E8,&br);
    GdipFillRectangle(g,(GpBrush*)br,bx,by,bsz,bsz); GdipDeleteBrush((GpBrush*)br);
    GpPen* pB=nullptr; GdipCreatePen1(0xFFAAAAAA,1.0f,UnitPixel,&pB);
    GdipDrawRectangle(g,pB,bx,by,bsz,bsz); GdipDeletePen(pB);
    GpPen* pX=nullptr; GdipCreatePen1(0xFFCC0000,1.8f,UnitPixel,&pX);
    float mg=3.5f;
    GdipDrawLine(g,pX,bx+mg,by+mg,bx+bsz-mg,by+bsz-mg);
    GdipDrawLine(g,pX,bx+bsz-mg,by+mg,bx+mg,by+bsz-mg);
    GdipDeletePen(pX);
}

/* ── Callback DrawPanel ──────────────────────────────────────────────────── */
static void CVD_DrawPanel(
    GpGraphics*     g,
    HDC             hDC,
    const double*   closes,
    const double*   opens,
    const double*   highs,
    const double*   lows,
    const double*   volumes,
    const int*      /*weekdays*/,
    int             count,
    int             /*period*/,
    int             /*param2*/,
    int             panelIndex,
    int             panelCount,
    const ChartCtx* ctx,
    int             panelH,
    int             panelGap,
    int             closeBtnSz,
    double*         outVMin,
    double*         outVMax)
{
    /* Données sub-TF passées via ctx->ref* */
    const double* subVol  = ctx->refHighs;      /* volumes QChart1 (réutilisé) */
    const double* subCls  = ctx->refLows;       /* closes  QChart1 */
    const double* subOpn  = ctx->refOpens;      /* opens   QChart1 */
    const double* subTS   = ctx->refTimestamps; /* timestamps Unix QChart1 */
    int           subN    = (int)ctx->refCount;
    const double* curTS   = ctx->curTimestamps; /* timestamps Unix TF courant */

    bool hasSubTF = (subVol && subCls && subOpn && subTS && subN > 0 && curTS);

    float oriX        = ctx->oriX;
    float stepX       = ctx->stepX;
    float lenX        = ctx->lenX;
    int   mainChartH  = ctx->mainChartH;
    int   panelInnerH = panelH - 20;
    int   rTop        = mainChartH + panelIndex * (panelH + panelGap);
    int   rBottom     = rTop + panelInnerH;
    int   vs          = ctx->viewStart;
    int   li          = ctx->lastIdx;

    /* ── Calcul CVD ──────────────────────────────────────────────────────── */
    static double cvdClose[MAX_B];
    static double cvdOpen [MAX_B];
    static double cvdHigh [MAX_B];
    static double cvdLow  [MAX_B];

    for (int i=0;i<count;++i)
        cvdClose[i]=cvdOpen[i]=cvdHigh[i]=cvdLow[i]=NAN;

    if (!hasSubTF){
        /* Pas de données sub-TF : CVD simplifié depuis les volumes du TF courant */
        double prevC=0.0;
        for (int i=0;i<count;++i){
            /* Reset ancre journalière :
             * Dans QChart (0=ancien) : i+1 = barre plus récente
             * On compare le jour de la barre courante avec celui de la barre précédente (i-1=plus ancienne)
             * → reset si changement de jour entre i-1 et i */
            if (i>0 && curTS && !std::isnan(curTS[i]) && !std::isnan(curTS[i-1])){
                long day_i  = (long)(curTS[i]   / 86400.0);
                long day_ip = (long)(curTS[i-1]  / 86400.0);  /* i-1 = plus ancienne */
                if (day_i != day_ip) prevC = 0.0;
            }
            double vol = volumes ? volumes[i] : 0.0;
            double delta = (closes[i]>opens[i]) ? vol : (closes[i]<opens[i]) ? -vol : 0.0;
            cvdOpen[i]  = prevC;
            cvdHigh[i]  = prevC + (delta>0?delta:0.0);
            cvdLow[i]   = prevC + (delta<0?delta:0.0);
            cvdClose[i] = prevC + delta;
            prevC = cvdClose[i];
        }
    } else {
        /* Données sub-TF disponibles — algo original */
        double prevC = 0.0;

        /* Durée d'une barre TF courant en secondes */
        long long tfSec = 3600LL; /* défaut 1h */
        for (int k=1;k<count;++k){
            if (!std::isnan(curTS[k])&&!std::isnan(curTS[k-1])){
                double diff = curTS[k]-curTS[k-1];
                if (diff>30.0){ tfSec=(long long)diff; break; }
            }
        }

        for (int i=0;i<count;++i){
            /* Reset ancre journalière :
             * i-1 en QChart = barre plus ancienne (0=ancien, count-1=récent)
             * Comparer jour de i avec jour de i-1 */
            if (i>0 && !std::isnan(curTS[i]) && !std::isnan(curTS[i-1])){
                long day_i  = (long)(curTS[i]   / 86400.0);
                long day_ip = (long)(curTS[i-1]  / 86400.0);
                if (day_i != day_ip) prevC = 0.0;
            }

            /* Fenêtre sub-TF pour la barre i :
             * tStart = curTS[i]             (début de la barre H1)
             * tEnd   = curTS[i] + tfSec     (fin de la barre H1)
             * Tolérance de 0.5s pour les imprecisions flottantes */
            double tStart = curTS[i] - 0.5;
            double tEnd   = curTS[i] + (double)tfSec - 0.5;

            int jStart = LowerBound(subTS, subN, tStart);
            int jEnd   = LowerBound(subTS, subN, tEnd);

            double runDelta = 0.0;
            double h = 0.0, l = 0.0;

            for (int j=jStart; j<jEnd && j<subN; j++){
                double sv = subVol[j];
                double sc = subCls[j];
                double so = subOpn[j];
                if (sc > so)      runDelta += sv;
                else if (sc < so) runDelta -= sv;
                if (runDelta > h) h = runDelta;
                if (runDelta < l) l = runDelta;
            }

            cvdOpen[i]  = prevC;
            cvdHigh[i]  = prevC + h;
            cvdLow[i]   = prevC + l;
            cvdClose[i] = prevC + runDelta;
            prevC = cvdClose[i];
        }
    }

    /* ── Échelle dynamique ───────────────────────────────────────────────── */
    double vMin=1e30, vMax=-1e30;
    for (int i=vs;i<=li;++i){
        if (i<0||i>=count) continue;
        if (!std::isnan(cvdHigh[i]))  { if(cvdHigh[i] >vMax) vMax=cvdHigh[i];  }
        if (!std::isnan(cvdLow[i]))   { if(cvdLow[i]  <vMin) vMin=cvdLow[i];   }
        if (!std::isnan(cvdClose[i])) { if(cvdClose[i]>vMax) vMax=cvdClose[i]; if(cvdClose[i]<vMin) vMin=cvdClose[i]; }
    }
    if (vMin==1e30){vMin=-100;vMax=100;}
    double rng=vMax-vMin; if(rng<1.0)rng=1.0;
    vMin-=rng*0.05; vMax+=rng*0.05;
    if (outVMin) *outVMin=vMin;
    if (outVMax) *outVMax=vMax;

    auto yPx=[&](double v)->float{
        return (float)rBottom-(float)((v-vMin)/(vMax-vMin))*panelInnerH;
    };

    /* ── Cadre + ligne zéro ──────────────────────────────────────────────── */
    GpPen* pG=nullptr; GdipCreatePen1(0xFFCCCCCC,1.0f,UnitPixel,&pG);
    GdipDrawRectangleI(g,pG,(int)oriX,rTop,(int)lenX,panelInnerH);
    if (vMin<0&&vMax>0){
        float yZ=yPx(0.0f);
        GdipDrawLine(g,pG,oriX,yZ,oriX+lenX,yZ);
        SetBkMode(hDC,TRANSPARENT); SetTextColor(hDC,0x888888);
        TextOutA(hDC,(int)oriX-14,(int)yZ-7,"0",1);
    }
    GdipDeletePen(pG);

    /* ── Bougies CVD ─────────────────────────────────────────────────────── */
    for (int i=vs;i<=li;++i){
        if (i<0||i>=count||std::isnan(cvdClose[i])) continue;
        float x   = oriX + (i-vs)*stepX;
        float bw  = stepX>2?stepX-1.0f:stepX;
        float yO  = yPx(cvdOpen[i]);
        float yC  = yPx(cvdClose[i]);
        float yH  = yPx(std::isnan(cvdHigh[i])?cvdClose[i]:cvdHigh[i]);
        float yL  = yPx(std::isnan(cvdLow[i]) ?cvdClose[i]:cvdLow[i]);

        bool bull = cvdClose[i] >= cvdOpen[i];
        unsigned int colFill = bull ? 0xAA00CC44 : 0xAACC2200;
        unsigned int colLine = bull ? 0xFF00AA33 : 0xFFCC0000;

        /* Corps */
        float bodyTop = (yO<yC)?yO:yC;
        float bodyH   = std::abs(yC-yO); if(bodyH<1.0f)bodyH=1.0f;
        GpSolidFill* br=nullptr; GdipCreateSolidFill(colFill,&br);
        GdipFillRectangle(g,(GpBrush*)br,x,bodyTop,bw,bodyH);
        GdipDeleteBrush(br);

        /* Mèches */
        float xMid=x+bw*0.5f;
        GpPen* pw=nullptr; GdipCreatePen1(colLine,1.0f,UnitPixel,&pw);
        if (yH<bodyTop)      GdipDrawLine(g,pw,xMid,yH,xMid,bodyTop);
        if (yL>bodyTop+bodyH)GdipDrawLine(g,pw,xMid,bodyTop+bodyH,xMid,yL);
        GdipDeletePen(pw);
    }

    /* ── Ligne close (courbe rouge) ──────────────────────────────────────── */
    GpPen* pL=nullptr; GdipCreatePen1(0xFFCC0000,1.5f,UnitPixel,&pL);
    float ox=0,oy=0; bool fst=true;
    for (int i=vs;i<=li;++i){
        if (i<0||i>=count||std::isnan(cvdClose[i])){fst=true;continue;}
        float x=oriX+(i-vs)*stepX+stepX*0.5f;
        float y=yPx(cvdClose[i]);
        if (!fst) GdipDrawLine(g,pL,ox,oy,x,y);
        ox=x;oy=y;fst=false;
    }
    GdipDeletePen(pL);

    /* ── Label + bouton X ────────────────────────────────────────────────── */
    const char* lbl2 = hasSubTF ? "CVD (1m)" : "CVD";
    char lbl[32]; std::snprintf(lbl,sizeof(lbl),"%s",lbl2);
    if (panelCount>1) std::snprintf(lbl,sizeof(lbl),"%s #%d",lbl2,panelIndex+1);
    SetBkMode(hDC,TRANSPARENT); SetTextColor(hDC,0xCC0000);
    TextOutA(hDC,(int)oriX-55,rTop+2,lbl,(int)strlen(lbl));
    SetTextColor(hDC,0);
    float bxBtn=oriX+lenX-(float)closeBtnSz-2.0f;
    DrawCloseBtn(g,bxBtn,(float)rTop+2.0f,(float)closeBtnSz);
}

/* ── Enregistrement ──────────────────────────────────────────────────────── */
//QCHART_REGISTER: Register_CVD
extern "C" void Register_CVD(IndicatorRegistry* reg) {
    if (reg->count>=MAX_INDICATORS) return;
    IndicatorDef* d=&reg->defs[reg->count++];
    std::strncpy(d->name,       "CVD",               sizeof(d->name)-1);
    std::strncpy(d->labelPrefix,"CVD",               sizeof(d->labelPrefix)-1);
    std::strncpy(d->param2Label,"Anchor (0=D,1=W)",  sizeof(d->param2Label)-1);
    d->defaultPeriod = 1;     /* sub-TF minutes (1 = 1min) */
    d->defaultParam2 = 0;     /* 0=Daily anchor, 1=Weekly */
    d->isPanel       = 1;
    d->drawOverlay   = nullptr;
    d->drawPanel     = CVD_DrawPanel;
}
