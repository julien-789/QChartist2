/*
 * indicators/realmacd.cpp
 * Real MACD — panel séparé.
 *
 * Algorithme (fidèle à realMACD.cpp) :
 *   MACDLine[i]   = EMA(close, fast)[i] - EMA(close, slow)[i]
 *   Signal[i]     = alpha*MACDLine[i] + (1-alpha)*Signal[i+1]
 *                   où alpha = 2/(SignalPeriod+1)
 *                   (EMA récursive du plus récent vers le plus ancien en MQL4)
 *   Histogram[i]  = (MACDLine[i] - Signal[i]) * 2
 *
 * Convention MQL4 → QChart :
 *   MQL4 itère i=limit→0 (récent→ancien), Signal[i+1] = barre plus ancienne.
 *   Dans QChart (0=ancien) : on itère i=0→count-1 et Signal[i-1] = barre plus ancienne.
 *   L'EMA récursive du signal se propage donc de l'ancien vers le récent :
 *   Signal[i] = alpha*MACD[i] + (1-alpha)*Signal[i-1]
 *
 * period = FastPeriod (défaut 12), param2 = SlowPeriod (défaut 26)
 * SignalPeriod = 9 codé (standard MACD)
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

static const int MAX_B       = 4096;
static const int SIGNAL_PER  = 9;

/* ── EMA backward [i-1..0] ───────────────────────────────────────────── */
static void CalcEMA(const double* src, int count, int period, double* out)
{
    for (int i=0;i<count;++i) out[i]=NAN;
    if (period<1||count<period) return;
    double k = 2.0/(period+1.0);
    /* Initialiser avec SMA sur les premières `period` barres */
    double sum=0;
    for (int i=0;i<period;++i) sum+=src[i];
    out[period-1]=sum/period;
    for (int i=period;i<count;++i)
        out[i]=src[i]*k + out[i-1]*(1.0-k);
}

/* ── Bouton X ────────────────────────────────────────────────────────── */
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

/* ── Callback DrawPanel ──────────────────────────────────────────────── */
static void MACD_DrawPanel(
    GpGraphics*     g,
    HDC             hDC,
    const double*   closes,
    const double*   opens,
    const double*   highs,
    const double*   lows,
    const double*   /*volumes*/,
    const int*      /*weekdays*/,
    int             count,
    int             period,    /* FastPeriod */
    int             param2,    /* SlowPeriod */
    int             panelIndex,
    int             panelCount,
    const ChartCtx* ctx,
    int             panelH,
    int             panelGap,
    int             closeBtnSz,
    double*         outVMin,
    double*         outVMax)
{
    int fastPer = (period>0) ? period : 12;
    int slowPer = (param2>0) ? param2 : 26;
    if (fastPer>=slowPer) fastPer=slowPer/2;
    if (count>MAX_B||count<slowPer) return;

    float oriX        = ctx->oriX;
    float stepX       = ctx->stepX;
    float lenX        = ctx->lenX;
    int   mainChartH  = ctx->mainChartH;
    int   panelInnerH = panelH-20;
    int   rTop        = mainChartH+panelIndex*(panelH+panelGap);
    int   rBottom     = rTop+panelInnerH;
    int   vs          = ctx->viewStart;
    int   li          = ctx->lastIdx;

    /* ── EMA rapide et lente ─────────────────────────────────────────── */
    static double emaFast[MAX_B], emaSlow[MAX_B];
    CalcEMA(closes, count, fastPer, emaFast);
    CalcEMA(closes, count, slowPer, emaSlow);

    /* ── MACD Line ───────────────────────────────────────────────────── */
    static double macdBuf[MAX_B];
    for (int i=0;i<count;++i){
        if (std::isnan(emaFast[i])||std::isnan(emaSlow[i]))
            macdBuf[i]=NAN;
        else
            macdBuf[i]=emaFast[i]-emaSlow[i];
    }

    /* ── Signal Line = EMA(MACD, SignalPeriod) ───────────────────────── */
    /* L'original MQL4 : Signal[i] = alpha*MACD[i] + alpha_1*Signal[i+1]
     * où i+1 = barre plus ancienne en MQL4.
     * Dans QChart (i-1 = plus ancienne), c'est exactement une EMA forward. */
    static double signalBuf[MAX_B];
    {
        double alpha  = 2.0/(SIGNAL_PER+1.0);
        double alpha1 = 1.0-alpha;
        for (int i=0;i<count;++i) signalBuf[i]=NAN;
        /* Trouver la première valeur MACD valide */
        int first=-1;
        for (int i=0;i<count;++i){ if (!std::isnan(macdBuf[i])){ first=i; break; } }
        if (first>=0){
            signalBuf[first]=macdBuf[first];
            for (int i=first+1;i<count;++i){
                if (std::isnan(macdBuf[i])){ signalBuf[i]=NAN; continue; }
                signalBuf[i]=alpha*macdBuf[i] + alpha1*signalBuf[i-1];
            }
        }
    }

    /* ── Histogram = (MACD - Signal) * 2 ────────────────────────────── */
    static double histBuf[MAX_B];
    for (int i=0;i<count;++i){
        if (std::isnan(macdBuf[i])||std::isnan(signalBuf[i]))
            histBuf[i]=NAN;
        else
            histBuf[i]=(macdBuf[i]-signalBuf[i])*2.0;
    }

    /* ── Échelle dynamique ───────────────────────────────────────────── */
    double vMin=1e30, vMax=-1e30;
    for (int i=vs;i<=li;++i){
        if (i<0||i>=count) continue;
        auto chk=[&](double v){ if(!std::isnan(v)){ if(v<vMin)vMin=v; if(v>vMax)vMax=v; } };
        chk(macdBuf[i]); chk(signalBuf[i]); chk(histBuf[i]);
    }
    if (vMin==1e30){vMin=-1;vMax=1;}
    double rng=vMax-vMin; if(rng<1e-10)rng=1.0;
    vMin-=rng*0.10; vMax+=rng*0.10;
    if (outVMin) *outVMin=vMin;
    if (outVMax) *outVMax=vMax;

    auto yPx=[&](double v) -> float {
        return (float)rBottom-(float)((v-vMin)/(vMax-vMin))*panelInnerH;
    };

    /* ── Cadre + ligne zéro ──────────────────────────────────────────── */
    GpPen* pG=nullptr; GdipCreatePen1(0xFFCCCCCC,1.0f,UnitPixel,&pG);
    GdipDrawRectangleI(g,pG,(int)oriX,rTop,(int)lenX,panelInnerH);
    if (vMin<0&&vMax>0){
        float yZ=yPx(0.0);
        GdipDrawLine(g,pG,oriX,yZ,oriX+lenX,yZ);
        SetBkMode(hDC,TRANSPARENT); SetTextColor(hDC,0x888888);
        TextOutA(hDC,(int)oriX-14,(int)yZ-7,"0",1);
    }
    GdipDeletePen(pG);

    /* ── Histogramme (jaune/rouge/vert selon valeur) ─────────────────── */
    float yZero=(vMin<0&&vMax>0)?yPx(0.0):(float)rBottom;
    for (int i=vs;i<=li;++i){
        if (i<0||i>=count||std::isnan(histBuf[i])) continue;
        float x=oriX+(i-vs)*stepX;
        float bw=stepX>1?stepX-0.5f:stepX;
        float y=yPx(histBuf[i]);
        float top,bot;
        if (histBuf[i]>=0){top=y;     bot=yZero;}
        else              {top=yZero; bot=y;}
        float h=bot-top; if(h<0.5f)h=0.5f;
        /* Couleur : vert si positif et croissant, rouge si positif et décroissant,
         * et inversement pour négatif — comme le vrai MACD coloré */
        bool rising=(i>0&&!std::isnan(histBuf[i-1])&&histBuf[i]>=histBuf[i-1]);
        unsigned int col;
        if (histBuf[i]>=0) col=rising?0xA000C800:0xA0FF4444;
        else               col=rising?0xA0FF8800:0xA0CC0000;
        GpSolidFill* br=nullptr; GdipCreateSolidFill(col,&br);
        GdipFillRectangle(g,(GpBrush*)br,x,top,bw,h);
        GdipDeleteBrush(br);
    }

    /* ── Signal Line (rouge) ─────────────────────────────────────────── */
    {
        GpPen* p=nullptr; GdipCreatePen1(0xFFCC0000,1.5f,UnitPixel,&p);
        float ox=0,oy=0; bool fst=true;
        for (int i=vs;i<=li;++i){
            if (i<0||i>=count||std::isnan(signalBuf[i])){fst=true;continue;}
            float x=oriX+(i-vs)*stepX+stepX*0.5f;
            float y=yPx(signalBuf[i]);
            if (!fst) GdipDrawLine(g,p,ox,oy,x,y);
            ox=x;oy=y;fst=false;
        }
        GdipDeletePen(p);
    }

    /* ── MACD Line (bleue) ───────────────────────────────────────────── */
    {
        GpPen* p=nullptr; GdipCreatePen1(0xFF0044CC,2.0f,UnitPixel,&p);
        float ox=0,oy=0; bool fst=true;
        for (int i=vs;i<=li;++i){
            if (i<0||i>=count||std::isnan(macdBuf[i])){fst=true;continue;}
            float x=oriX+(i-vs)*stepX+stepX*0.5f;
            float y=yPx(macdBuf[i]);
            if (!fst) GdipDrawLine(g,p,ox,oy,x,y);
            ox=x;oy=y;fst=false;
        }
        GdipDeletePen(p);
    }

    /* ── Label + bouton X ────────────────────────────────────────────── */
    char lbl[48];
    if (panelCount>1) std::snprintf(lbl,sizeof(lbl),"MACD(%d,%d,%d) #%d",fastPer,slowPer,SIGNAL_PER,panelIndex+1);
    else              std::snprintf(lbl,sizeof(lbl),"MACD(%d,%d,%d)",fastPer,slowPer,SIGNAL_PER);
    SetBkMode(hDC,TRANSPARENT); SetTextColor(hDC,0x0044CC);
    TextOutA(hDC,(int)oriX-55,rTop+2,lbl,(int)strlen(lbl));
    SetTextColor(hDC,0);
    float bxBtn=oriX+lenX-(float)closeBtnSz-2.0f;
    DrawCloseBtn(g,bxBtn,(float)rTop+2.0f,(float)closeBtnSz);
}

/* ── Enregistrement ──────────────────────────────────────────────────── */
//QCHART_REGISTER: Register_RealMACD
extern "C" void Register_RealMACD(IndicatorRegistry* reg) {
    if (reg->count>=MAX_INDICATORS) return;
    IndicatorDef* d=&reg->defs[reg->count++];
    std::strncpy(d->name,       "Real MACD",   sizeof(d->name)-1);
    std::strncpy(d->labelPrefix,"MACD",        sizeof(d->labelPrefix)-1);
    std::strncpy(d->param2Label,"Slow Period", sizeof(d->param2Label)-1);
    d->defaultPeriod = 12;   /* FastPeriod  */
    d->defaultParam2 = 26;   /* SlowPeriod  */
    d->isPanel       = 1;
    d->drawOverlay   = nullptr;
    d->drawPanel     = MACD_DrawPanel;
}
