/*
 * indicators/stochastic.cpp
 * Stochastic — panel séparé.
 *
 * Algorithme MQL4 traduit correctement en convention QChart (0=plus ancien) :
 *
 *   LowesBuffer[i]  = Lowest(low,  i-KPeriod+1 .. i)   fenêtre backward
 *   HighesBuffer[i] = Highest(high, i-KPeriod+1 .. i)
 *
 *   MainBuffer[i] (K avec Slowing) :
 *     sumLow  = SUM(close[k]-Lowest[k],          k=i-Slowing+1..i)
 *     sumHigh = SUM(Highest[k]-Lowest[k],         k=i-Slowing+1..i)
 *     K = (sumHigh==0) ? 100 : sumLow/sumHigh*100
 *
 *   SignalBuffer[i] = SMA(MainBuffer, DPeriod)   backward
 *
 * Résultat dans [0,100]. Niveaux 80/50/20.
 *
 * period = KPeriod (défaut 5), param2 = DPeriod (défaut 3), Slowing=3 fixe
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

static const int MAX_B   = 4096;
static const int SLOWING = 3;

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

static void Stoch_DrawPanel(
    GpGraphics*     g,
    HDC             hDC,
    const double*   closes,
    const double*   opens,
    const double*   highs,
    const double*   lows,
    const double*   /*volumes*/,
    const int*      /*weekdays*/,
    int             count,
    int             period,
    int             param2,
    int             panelIndex,
    int             panelCount,
    const ChartCtx* ctx,
    int             panelH,
    int             panelGap,
    int             closeBtnSz,
    double*         outVMin,
    double*         outVMax)
{
    int KPeriod = (period>0) ? period : 5;
    int DPeriod = (param2>0) ? param2 : 3;
    int warmup  = KPeriod + SLOWING + DPeriod - 2;

    double vMin=0.0, vMax=100.0;
    if (outVMin) *outVMin=vMin;
    if (outVMax) *outVMax=vMax;

    if (count>MAX_B || count<warmup) return;

    float oriX        = ctx->oriX;
    float stepX       = ctx->stepX;
    float lenX        = ctx->lenX;
    int   mainChartH  = ctx->mainChartH;
    int   panelInnerH = panelH-20;
    int   rTop        = mainChartH+panelIndex*(panelH+panelGap);
    int   rBottom     = rTop+panelInnerH;
    int   vs          = ctx->viewStart;
    int   li          = ctx->lastIdx;

    auto yPx = [&](double v) -> float {
        return (float)rBottom-(float)((v-vMin)/(vMax-vMin))*panelInnerH;
    };

    /* ── Passe 1 : Lowest / Highest backward [i-KPeriod+1..i] ───────── */
    static double lowestBuf [MAX_B];
    static double highestBuf[MAX_B];

    for (int i=0;i<count;++i){
        if (i<KPeriod-1){ lowestBuf[i]=NAN; highestBuf[i]=NAN; continue; }
        double lo=lows[i], hi=highs[i];
        for (int k=1;k<KPeriod;++k){
            if (lows [i-k]<lo) lo=lows [i-k];
            if (highs[i-k]>hi) hi=highs[i-k];
        }
        lowestBuf[i] =lo;
        highestBuf[i]=hi;
    }

    /* ── Passe 2 : MainBuffer (K avec Slowing) backward ─────────────── */
    static double mainBuf[MAX_B];
    for (int i=0;i<count;++i){
        int start = i-SLOWING+1;
        if (start<0 || std::isnan(lowestBuf[i])){ mainBuf[i]=NAN; continue; }
        double sumLow=0, sumHigh=0; bool ok=true;
        for (int k=start;k<=i;++k){
            if (std::isnan(lowestBuf[k])){ ok=false; break; }
            sumLow  += closes[k]  - lowestBuf[k];
            sumHigh += highestBuf[k] - lowestBuf[k];
        }
        if (!ok){ mainBuf[i]=NAN; continue; }
        mainBuf[i] = (sumHigh==0.0) ? 100.0 : sumLow/sumHigh*100.0;
    }

    /* ── Passe 3 : SignalBuffer = SMA(mainBuf, DPeriod) backward ────── */
    static double signalBuf[MAX_B];
    for (int i=0;i<count;++i) signalBuf[i]=NAN;
    {
        double sum=0; int n=0;
        for (int i=0;i<count;++i){
            if (std::isnan(mainBuf[i])){ sum=0; n=0; continue; }
            sum+=mainBuf[i]; n++;
            if (n>DPeriod){
                sum-=mainBuf[i-DPeriod];
                n=DPeriod;
            }
            if (n==DPeriod) signalBuf[i]=sum/DPeriod;
        }
    }

    /* ── Cadre ───────────────────────────────────────────────────────── */
    GpPen* pG=nullptr; GdipCreatePen1(0xFFCCCCCC,1.0f,UnitPixel,&pG);
    GdipDrawRectangleI(g,pG,(int)oriX,rTop,(int)lenX,panelInnerH);
    GdipDeletePen(pG);

    /* ── Zone 20-80 ──────────────────────────────────────────────────── */
    float y80=yPx(80.0), y20=yPx(20.0);
    {
        GpSolidFill* brZ=nullptr; GdipCreateSolidFill(0x182196F3,&brZ);
        GdipFillRectangle(g,(GpBrush*)brZ,oriX,y80,lenX,y20-y80);
        GdipDeleteBrush(brZ);
    }

    /* ── Niveaux ─────────────────────────────────────────────────────── */
    struct { double v; unsigned int col; bool dash; const char* lbl; } lvls[]={
        {80.0, 0xFF808080, false, " 80"},
        {50.0, 0x80808080, true,  " 50"},
        {20.0, 0xFF808080, false, " 20"},
    };
    SetBkMode(hDC,TRANSPARENT);
    for (auto& lv : lvls){
        float y=yPx(lv.v);
        GpPen* p=nullptr; GdipCreatePen1(lv.col,1.0f,UnitPixel,&p);
        if (lv.dash) GdipSetPenDashStyle(p,DashStyleDash);
        GdipDrawLine(g,p,oriX,y,oriX+lenX,y);
        GdipDeletePen(p);
        SetTextColor(hDC,0x888888);
        TextOutA(hDC,(int)oriX-22,(int)y-7,lv.lbl,3);
    }

    /* ── Signal %D (rouge) ───────────────────────────────────────────── */
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

    /* ── Main %K (LightSeaGreen) ─────────────────────────────────────── */
    {
        GpPen* p=nullptr; GdipCreatePen1(0xFF20B2AA,1.5f,UnitPixel,&p);
        float ox=0,oy=0; bool fst=true;
        for (int i=vs;i<=li;++i){
            if (i<0||i>=count||std::isnan(mainBuf[i])){fst=true;continue;}
            float x=oriX+(i-vs)*stepX+stepX*0.5f;
            float y=yPx(mainBuf[i]);
            if (!fst) GdipDrawLine(g,p,ox,oy,x,y);
            ox=x;oy=y;fst=false;
        }
        GdipDeletePen(p);
    }

    /* ── Label + bouton X ────────────────────────────────────────────── */
    char lbl[48];
    if (panelCount>1) std::snprintf(lbl,sizeof(lbl),"Stoch(%d,%d,%d) #%d",KPeriod,DPeriod,SLOWING,panelIndex+1);
    else              std::snprintf(lbl,sizeof(lbl),"Stoch(%d,%d,%d)",KPeriod,DPeriod,SLOWING);
    SetTextColor(hDC,0x20B2AA);
    TextOutA(hDC,(int)oriX-55,rTop+2,lbl,(int)std::strlen(lbl));
    SetTextColor(hDC,0);
    float bxBtn=oriX+lenX-(float)closeBtnSz-2.0f;
    DrawCloseBtn(g,bxBtn,(float)rTop+2.0f,(float)closeBtnSz);
}

//QCHART_REGISTER: Register_Stochastic
extern "C" void Register_Stochastic(IndicatorRegistry* reg) {
    if (reg->count>=MAX_INDICATORS) return;
    IndicatorDef* d=&reg->defs[reg->count++];
    std::strncpy(d->name,       "Stochastic", sizeof(d->name)-1);
    std::strncpy(d->labelPrefix,"Stoch",      sizeof(d->labelPrefix)-1);
    std::strncpy(d->param2Label,"D Period",   sizeof(d->param2Label)-1);
    d->defaultPeriod = 5;
    d->defaultParam2 = 3;
    d->isPanel       = 1;
    d->drawOverlay   = nullptr;
    d->drawPanel     = Stoch_DrawPanel;
}
