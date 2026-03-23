/*
 * indicators/stochasticrsi.cpp
 * Stochastic RSI [Ehlers] — panel séparé.
 *
 * Algorithme EXACT du MQL4 original :
 *   RSILength=5, StocLength=5, WMALength=5
 *
 *   Passe 1 : pour chaque barre i (QChart 0=ancien) :
 *     rsi = RSI(close, RSILength)[i]
 *     hh/ll sur [i-StocLength+1..i] (fenêtre backward, StocLength barres)
 *     Value3[i] = (hh==ll) ? 0 : (rsi-ll)/(hh-ll)
 *
 *   Passe 2 :
 *     StocRSI[i] = 2*(LWMA(Value3, WMALength)[i] - 0.5)
 *     Trigger[i] = StocRSI[i-1]  (MQL4: s+1 = plus ancienne = i-1 QChart)
 *
 * Note : l'original utilise irsi(60,...) = TF 60 min. Dans QChart Pro
 * on utilise le TF courant (les closes reçus sont ceux du TF affiché).
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

static const int MAX_B    = 4096;
static const int RSI_LEN  = 5;
static const int STOC_LEN = 5;
static const int WMA_LEN  = 5;

/* ── RSI de Wilder ───────────────────────────────────────────────────── */
static void CalcRSI(const double* c, int count, int per, double* out)
{
    for (int i=0;i<count;++i) out[i]=NAN;
    if (per<1||count<per+1) return;
    double au=0,ad=0;
    for (int i=1;i<=per;++i){
        double d=c[i]-c[i-1];
        if (d>0) au+=d; else ad-=d;
    }
    au/=per; ad/=per;
    out[per]=(ad==0)?100.0:(au==0)?0.0:100.0-100.0/(1.0+au/ad);
    for (int i=per+1;i<count;++i){
        double d=c[i]-c[i-1];
        double u=(d>0)?d:0.0, dn=(d<0)?-d:0.0;
        au=(au*(per-1)+u)/per;
        ad=(ad*(per-1)+dn)/per;
        out[i]=(ad==0)?100.0:(au==0)?0.0:100.0-100.0/(1.0+au/ad);
    }
}

/* ── LWMA (Linear Weighted MA) ───────────────────────────────────────── */
/* Poids : period pour le plus récent, 1 pour le plus ancien */
static void CalcLWMA(const double* src, int count, int per, double* out)
{
    for (int i=0;i<count;++i) out[i]=NAN;
    if (per<1||count<per) return;
    double denom=per*(per+1)/2.0;
    for (int i=per-1;i<count;++i){
        double sum=0; bool ok=true;
        for (int k=0;k<per;++k){
            if (std::isnan(src[i-k])){ ok=false; break; }
            sum+=(double)(per-k)*src[i-k];
        }
        if (ok) out[i]=sum/denom;
    }
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
static void StochRSI_DrawPanel(
    GpGraphics*     g,
    HDC             hDC,
    const double*   closes,
    const double*   opens,
    const double*   highs,
    const double*   lows,
    const double*   /*volumes*/,
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
    double vMin=-1.2, vMax=1.2;
    if (outVMin) *outVMin=vMin;
    if (outVMax) *outVMax=vMax;
    if (count>MAX_B||count<RSI_LEN+STOC_LEN+WMA_LEN) return;

    float oriX        = ctx->oriX;
    float stepX       = ctx->stepX;
    float lenX        = ctx->lenX;
    int   mainChartH  = ctx->mainChartH;
    int   panelInnerH = panelH-20;
    int   rTop        = mainChartH+panelIndex*(panelH+panelGap);
    int   rBottom     = rTop+panelInnerH;
    int   vs          = ctx->viewStart;
    int   li          = ctx->lastIdx;

    auto yPx=[&](double v)->float{
        return (float)rBottom-(float)((v-vMin)/(vMax-vMin))*panelInnerH;
    };

    /* ── RSI ─────────────────────────────────────────────────────────── */
    static double rsiBuf[MAX_B];
    CalcRSI(closes, count, RSI_LEN, rsiBuf);

    /* ── Stochastic sur RSI (fenêtre backward [i-STOC_LEN+1..i]) ────── */
    static double value3[MAX_B];
    for (int i=0;i<count;++i) value3[i]=0.0;
    for (int i=STOC_LEN-1;i<count;++i){
        if (std::isnan(rsiBuf[i])){ continue; }
        double hh=rsiBuf[i], ll=rsiBuf[i]; bool ok=true;
        for (int k=1;k<STOC_LEN;++k){
            if (std::isnan(rsiBuf[i-k])){ ok=false; break; }
            if (rsiBuf[i-k]>hh) hh=rsiBuf[i-k];
            if (rsiBuf[i-k]<ll) ll=rsiBuf[i-k];
        }
        if (!ok) continue;
        double rng=hh-ll;
        value3[i]=(rng!=0.0)?(rsiBuf[i]-ll)/rng:0.0;
    }

    /* ── LWMA → StocRSI ──────────────────────────────────────────────── */
    static double lwmaBuf[MAX_B];
    CalcLWMA(value3, count, WMA_LEN, lwmaBuf);

    static double stocBuf[MAX_B];
    static double trigBuf[MAX_B];
    for (int i=0;i<count;++i){
        stocBuf[i] = std::isnan(lwmaBuf[i]) ? NAN : 2.0*(lwmaBuf[i]-0.5);
    }
    /* Trigger[s] = StocRSI[s+1] en MQL4
     * s+1 en MQL4 (index croissant = plus ancien) → i-1 dans QChart */
    trigBuf[0]=NAN;
    for (int i=1;i<count;++i){
        trigBuf[i]=std::isnan(stocBuf[i-1])?NAN:stocBuf[i-1];
    }

    /* ── Cadre ───────────────────────────────────────────────────────── */
    GpPen* pG=nullptr; GdipCreatePen1(0xFFCCCCCC,1.0f,UnitPixel,&pG);
    GdipDrawRectangleI(g,pG,(int)oriX,rTop,(int)lenX,panelInnerH);
    GdipDeletePen(pG);

    /* ── Niveaux ─────────────────────────────────────────────────────── */
    struct { double v; GpDashStyle ds; const char* lbl; } lvls[]={
        { 1.0, DashStyleDash, " +1"},
        { 0.0, DashStyleDot,  "  0"},
        {-1.0, DashStyleDash, " -1"},
    };
    SetBkMode(hDC,TRANSPARENT);
    for (auto& lv:lvls){
        float y=yPx(lv.v);
        GpPen* p=nullptr; GdipCreatePen1(0xFF888888,1.0f,UnitPixel,&p);
        GdipSetPenDashStyle(p,lv.ds);
        GdipDrawLine(g,p,oriX,y,oriX+lenX,y);
        GdipDeletePen(p);
        SetTextColor(hDC,0x888888);
        TextOutA(hDC,(int)oriX-22,(int)y-7,lv.lbl,3);
    }

    /* ── Trigger (bleu) ──────────────────────────────────────────────── */
    {
        GpPen* p=nullptr; GdipCreatePen1(0xFF0044CC,1.5f,UnitPixel,&p);
        float ox=0,oy=0; bool fst=true;
        for (int i=vs;i<=li;++i){
            if (i<0||i>=count||std::isnan(trigBuf[i])){fst=true;continue;}
            float x=oriX+(i-vs)*stepX+stepX*0.5f;
            float y=yPx(trigBuf[i]);
            if (!fst) GdipDrawLine(g,p,ox,oy,x,y);
            ox=x;oy=y;fst=false;
        }
        GdipDeletePen(p);
    }

    /* ── StocRSI (rouge) ─────────────────────────────────────────────── */
    {
        GpPen* p=nullptr; GdipCreatePen1(0xFFCC0000,1.5f,UnitPixel,&p);
        float ox=0,oy=0; bool fst=true;
        for (int i=vs;i<=li;++i){
            if (i<0||i>=count||std::isnan(stocBuf[i])){fst=true;continue;}
            float x=oriX+(i-vs)*stepX+stepX*0.5f;
            float y=yPx(stocBuf[i]);
            if (!fst) GdipDrawLine(g,p,ox,oy,x,y);
            ox=x;oy=y;fst=false;
        }
        GdipDeletePen(p);
    }

    /* ── Label + bouton X ────────────────────────────────────────────── */
    char lbl[48];
    if (panelCount>1) std::snprintf(lbl,sizeof(lbl),"StochRSI(%d,%d,%d) #%d",RSI_LEN,STOC_LEN,WMA_LEN,panelIndex+1);
    else              std::snprintf(lbl,sizeof(lbl),"StochRSI(%d,%d,%d)",RSI_LEN,STOC_LEN,WMA_LEN);
    SetTextColor(hDC,0xCC0000);
    TextOutA(hDC,(int)oriX-55,rTop+2,lbl,(int)strlen(lbl));
    SetTextColor(hDC,0);
    float bxBtn=oriX+lenX-(float)closeBtnSz-2.0f;
    DrawCloseBtn(g,bxBtn,(float)rTop+2.0f,(float)closeBtnSz);
}

//QCHART_REGISTER: Register_StochasticRSI
extern "C" void Register_StochasticRSI(IndicatorRegistry* reg) {
    if (reg->count>=MAX_INDICATORS) return;
    IndicatorDef* d=&reg->defs[reg->count++];
    std::strncpy(d->name,       "Stochastic RSI", sizeof(d->name)-1);
    std::strncpy(d->labelPrefix,"StochRSI",       sizeof(d->labelPrefix)-1);
    d->defaultPeriod = 5;
    d->defaultParam2 = 0;
    d->isPanel       = 1;
    d->drawOverlay   = nullptr;
    d->drawPanel     = StochRSI_DrawPanel;
}
