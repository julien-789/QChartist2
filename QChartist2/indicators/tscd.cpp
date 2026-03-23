/*
 * indicators/tscd.cpp
 * TSCD — Time Series Convergence Divergence, panel séparé.
 *
 * Algorithme EXACT du MQL4 original (tscd.mq4) :
 *
 * Lreg(st0, st1) dans MQL4 (0=récent, index croissant=plus ancien) :
 *   n = st1-st0+1
 *   Sy = price[st0]           ← barre courante (x=0)
 *   boucle i=1..n-1 :
 *     x = i
 *     y = price[st0+i]        ← barres plus ANCIENNES
 *     accumule Sx, Sy, Sxx, Sxy
 *   Beta = (n*Sxy - Sx*Sy) / (Sxx*n - Sx*Sx)
 *   Alfa = (Sy - Beta*Sx) / n   ← valeur en x=0 (barre courante)
 *   return Alfa
 *
 * Dans QChart (0=ancien, count-1=récent) :
 *   st0 = barre courante i (plus récente de la fenêtre)
 *   st0+k en MQL4 = barres plus anciennes = i-k dans QChart
 *   Fenêtre : [i-n+1..i], avec x=0 pour i (plus récent), x=n-1 pour i-n+1 (plus ancien)
 *   Retourne la valeur en x=0 = barre i (courant)
 *
 * TSCD[i] = Lreg_fast[i] - Lreg_slow[i]
 * MA[i]   = SMA(TSCD, TSFma1)[i]
 *
 * period = TSFfast (défaut 20), param2 = TSFslow (défaut 50)
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

static const int MAX_B  = 4096;
static const int TSF_MA = 5;

/* ── Lreg fidèle au MQL4 ─────────────────────────────────────────────── */
/*
 * price[] en convention QChart (0=plus ancien).
 * i     = barre courante (st0 MQL4, x=0)
 * n     = nombre de barres (st1-st0+1)
 * barres : i (x=0), i-1 (x=1), ..., i-n+1 (x=n-1)
 * retourne Alfa = valeur de la droite en x=0
 */
static double Lreg(const double* price, int i, int n, int count)
{
    if (n<=0 || i<0 || i>=count || i-(n-1)<0) return 0.0;

    double Sx=0, Sxx=0, Sxy=0;
    /* Initialisation avec st0 (x=0, barre i) */
    double Sy = price[i];
    /* Boucle i=1..n-1 : st0+k en MQL4 = i-k dans QChart */
    for (int k=1; k<n; k++){
        double x = (double)k;
        double y = price[i-k];
        Sx  += x;
        Sy  += y;
        Sxx += x*x;
        Sxy += x*y;
    }
    double c = Sxx*n - Sx*Sx;
    if (c==0.0) return 0.0;
    double Beta = ((double)n*Sxy - Sx*Sy) / c;
    double Alfa = (Sy - Beta*Sx) / (double)n;
    return Alfa;
}

/* ── SMA backward ────────────────────────────────────────────────────── */
static void CalcSMA(const double* src, int count, int per, double* out)
{
    for (int i=0;i<count;++i) out[i]=NAN;
    if (per<1||count<per) return;
    double sum=0;
    for (int i=0;i<per;++i) sum+=std::isnan(src[i])?0.0:src[i];
    if (!std::isnan(src[per-1])) out[per-1]=sum/per;
    for (int i=per;i<count;++i){
        double add=std::isnan(src[i])?0.0:src[i];
        double rem=std::isnan(src[i-per])?0.0:src[i-per];
        sum+=add-rem;
        if (!std::isnan(src[i])) out[i]=sum/per;
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
static void TSCD_DrawPanel(
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
    int fastPer = (period>0) ? period : 20;
    int slowPer = (param2>0) ? param2 : 50;
    if (fastPer<2)  fastPer=2;
    if (slowPer<4)  slowPer=4;
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

    /* ── Prix source (O+H+L+C)/4 ─────────────────────────────────────── */
    static double priceBuf[MAX_B];
    for (int i=0;i<count;++i)
        priceBuf[i]=(opens[i]+highs[i]+lows[i]+closes[i])*0.25;

    /* ── TSCD = Lreg(fast) - Lreg(slow) ─────────────────────────────── */
    static double tscdBuf[MAX_B];
    static double maBuf  [MAX_B];
    for (int i=0;i<count;++i) tscdBuf[i]=NAN;

    for (int i=slowPer-1;i<count;++i){
        double lf = Lreg(priceBuf, i, fastPer, count);
        double ls = Lreg(priceBuf, i, slowPer, count);
        tscdBuf[i] = lf - ls;
    }

    /* MA = SMA(TSCD, TSFma1) */
    CalcSMA(tscdBuf, count, TSF_MA, maBuf);

    /* ── Échelle dynamique ───────────────────────────────────────────── */
    double vMin=1e30, vMax=-1e30;
    for (int i=vs;i<=li;++i){
        if (i<0||i>=count) continue;
        if (!std::isnan(tscdBuf[i])){ if(tscdBuf[i]<vMin)vMin=tscdBuf[i]; if(tscdBuf[i]>vMax)vMax=tscdBuf[i]; }
        if (!std::isnan(maBuf[i]))  { if(maBuf[i]  <vMin)vMin=maBuf[i];   if(maBuf[i]  >vMax)vMax=maBuf[i]; }
    }
    if (vMin==1e30){vMin=-1;vMax=1;}
    double rng=vMax-vMin; if(rng<1e-10)rng=1.0;
    vMin-=rng*0.10; vMax+=rng*0.10;
    if (outVMin) *outVMin=vMin;
    if (outVMax) *outVMax=vMax;

    auto yPx=[&](double v)->float{
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

    /* ── Histogramme rouge/vert ──────────────────────────────────────── */
    float yZero=(vMin<0&&vMax>0)?yPx(0.0):(float)rBottom;
    for (int i=vs;i<=li;++i){
        if (i<0||i>=count||std::isnan(tscdBuf[i])) continue;
        float x=oriX+(i-vs)*stepX;
        float bw=stepX>1?stepX-0.5f:stepX;
        float y=yPx(tscdBuf[i]);
        float top,bot;
        if (tscdBuf[i]>=0){top=y;     bot=yZero;}
        else              {top=yZero; bot=y;}
        float h=bot-top; if(h<0.5f)h=0.5f;
        unsigned int col=(tscdBuf[i]>=0)?0xA000AA44:0xA0CC2200;
        GpSolidFill* br=nullptr; GdipCreateSolidFill(col,&br);
        GdipFillRectangle(g,(GpBrush*)br,x,top,bw,h);
        GdipDeleteBrush(br);
    }

    /* ── Ligne MA (DodgerBlue) ───────────────────────────────────────── */
    {
        GpPen* p=nullptr; GdipCreatePen1(0xFF1E90FF,1.5f,UnitPixel,&p);
        float ox=0,oy=0; bool fst=true;
        for (int i=vs;i<=li;++i){
            if (i<0||i>=count||std::isnan(maBuf[i])){fst=true;continue;}
            float x=oriX+(i-vs)*stepX+stepX*0.5f;
            float y=yPx(maBuf[i]);
            if (!fst) GdipDrawLine(g,p,ox,oy,x,y);
            ox=x;oy=y;fst=false;
        }
        GdipDeletePen(p);
    }

    /* ── Label + bouton X ────────────────────────────────────────────── */
    char lbl[48];
    if (panelCount>1) std::snprintf(lbl,sizeof(lbl),"TSCD(%d,%d) #%d",fastPer,slowPer,panelIndex+1);
    else              std::snprintf(lbl,sizeof(lbl),"TSCD(%d,%d)",fastPer,slowPer);
    SetBkMode(hDC,TRANSPARENT); SetTextColor(hDC,0xCC0000);
    TextOutA(hDC,(int)oriX-55,rTop+2,lbl,(int)strlen(lbl));
    SetTextColor(hDC,0);
    float bxBtn=oriX+lenX-(float)closeBtnSz-2.0f;
    DrawCloseBtn(g,bxBtn,(float)rTop+2.0f,(float)closeBtnSz);
}

/* ── Enregistrement ──────────────────────────────────────────────────── */
//QCHART_REGISTER: Register_TSCD
extern "C" void Register_TSCD(IndicatorRegistry* reg) {
    if (reg->count>=MAX_INDICATORS) return;
    IndicatorDef* d=&reg->defs[reg->count++];
    std::strncpy(d->name,       "TSCD",        sizeof(d->name)-1);
    std::strncpy(d->labelPrefix,"TSCD",        sizeof(d->labelPrefix)-1);
    std::strncpy(d->param2Label,"Slow Period", sizeof(d->param2Label)-1);
    d->defaultPeriod = 20;
    d->defaultParam2 = 50;
    d->isPanel       = 1;
    d->drawOverlay   = nullptr;
    d->drawPanel     = TSCD_DrawPanel;
}
