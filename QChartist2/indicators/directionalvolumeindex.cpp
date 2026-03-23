/*
 * indicators/directionalvolumeindex.cpp
 * Directional Volume Index (DVI) — panel séparé.
 *
 * Algorithme Pine Script v4 :
 *   src   = hlc3 = (H+L+C)/3
 *   out1  = vwma(src, period)    VWMA sur les `period` barres précédentes
 *   out2  = sma(src, period)     SMA sur les `period` barres précédentes
 *   DVI   = out1 - out2
 *   DVI   = vwma(DVI, smooth)    lissage volume-pondéré
 *
 * period = len1=len2 (défaut 200), param2 = smooth (défaut 5)
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

/* ── VWMA backward [i-period+1..i] ──────────────────────────────────── */
static void CalcVWMA(
    const double* src, const double* vol,
    int count, int period, double* out)
{
    for (int i=0;i<count;++i) out[i]=NAN;
    if (period<1||count<period) return;

    double sumSV=0, sumV=0;
    /* Initialiser sur la première fenêtre complète [0..period-1] */
    for (int i=0;i<period;++i){
        sumSV += src[i]*vol[i];
        sumV  += vol[i];
    }
    out[period-1] = (sumV>0) ? sumSV/sumV : sumSV/period; /* fallback SMA si vol=0 */

    for (int i=period;i<count;++i){
        sumSV += src[i]*vol[i]       - src[i-period]*vol[i-period];
        sumV  += vol[i]              - vol[i-period];
        out[i] = (sumV>0) ? sumSV/sumV : (sumSV/period); /* fallback */
    }
}

/* ── SMA backward [i-period+1..i] ───────────────────────────────────── */
static void CalcSMA(
    const double* src, int count, int period, double* out)
{
    for (int i=0;i<count;++i) out[i]=NAN;
    if (period<1||count<period) return;

    double sum=0;
    for (int i=0;i<period;++i) sum+=src[i];
    out[period-1]=sum/period;

    for (int i=period;i<count;++i){
        sum += src[i]-src[i-period];
        out[i]=sum/period;
    }
}

/* ── Helper dessin courbe ────────────────────────────────────────────── */
static void DrawCurve(GpGraphics* g, GpPen* pen,
    const double* buf, int count, int vs, int li,
    float oriX, int rBottom, int panelInnerH,
    double vMin, double vMax, float stepX)
{
    float ox=0,oy=0; bool fst=true;
    for (int i=vs;i<=li;++i){
        if (i<0||i>=count||std::isnan(buf[i])){fst=true;continue;}
        float x=oriX+(i-vs)*stepX+stepX*0.5f;
        float y=(float)rBottom-(float)((buf[i]-vMin)/(vMax-vMin))*panelInnerH;
        if (!fst) GdipDrawLine(g,pen,ox,oy,x,y);
        ox=x;oy=y;fst=false;
    }
}

/* ── Helper bouton X ─────────────────────────────────────────────────── */
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
static void DVI_DrawPanel(
    GpGraphics*     g,
    HDC             hDC,
    const double*   closes,
    const double*   opens,
    const double*   highs,
    const double*   lows,
    const double*   volumes,
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
    if (count>MAX_B||count<period) return;
    int smooth=(param2>0)?param2:5;

    float oriX        = ctx->oriX;
    float stepX       = ctx->stepX;
    float lenX        = ctx->lenX;
    int   mainChartH  = ctx->mainChartH;
    int   panelInnerH = panelH-20;
    int   rTop        = mainChartH+panelIndex*(panelH+panelGap);
    int   rBottom     = rTop+panelInnerH;
    int   vs          = ctx->viewStart;
    int   li          = ctx->lastIdx;

    /* ── src = HLC3 ──────────────────────────────────────────────────── */
    static double src[MAX_B];
    for (int i=0;i<count;++i)
        src[i]=(highs[i]+lows[i]+closes[i])/3.0;

    /* ── out1 = VWMA(src, period) ────────────────────────────────────── */
    static double out1[MAX_B];
    CalcVWMA(src, volumes, count, period, out1);

    /* ── out2 = SMA(src, period) ─────────────────────────────────────── */
    static double out2[MAX_B];
    CalcSMA(src, count, period, out2);

    /* ── DVI brut : remplacer NaN par 0 pour permettre le lissage ────── */
    static double dviRaw[MAX_B];
    for (int i=0;i<count;++i){
        if (std::isnan(out1[i])||std::isnan(out2[i]))
            dviRaw[i]=0.0;
        else
            dviRaw[i]=out1[i]-out2[i];
    }

    /* ── DVI lissé = VWMA(DVI, smooth) ──────────────────────────────── */
    static double dvi[MAX_B];
    CalcVWMA(dviRaw, volumes, count, smooth, dvi);

    /* NaN sur les barres avant period+smooth-2 (pas assez de données) */
    int warmup=period+smooth-2;
    for (int i=0;i<warmup&&i<count;++i) dvi[i]=NAN;

    /* ── Échelle dynamique ───────────────────────────────────────────── */
    double vMin=1e30, vMax=-1e30;
    for (int i=vs;i<=li;++i){
        if (i<0||i>=count||std::isnan(dvi[i])) continue;
        if (dvi[i]<vMin) vMin=dvi[i];
        if (dvi[i]>vMax) vMax=dvi[i];
    }
    if (vMin==1e30){vMin=-1.0;vMax=1.0;}
    double rng=vMax-vMin; if (rng<1e-10) rng=1.0;
    vMin-=rng*0.10; vMax+=rng*0.10;
    if (outVMin) *outVMin=vMin;
    if (outVMax) *outVMax=vMax;

    /* ── Cadre + ligne zéro ──────────────────────────────────────────── */
    GpPen* pG=nullptr; GdipCreatePen1(0xFFCCCCCC,1.0f,UnitPixel,&pG);
    GdipDrawRectangleI(g,pG,(int)oriX,rTop,(int)lenX,panelInnerH);
    if (vMin<0&&vMax>0){
        float yZ=(float)rBottom-(float)((0.0-vMin)/(vMax-vMin))*panelInnerH;
        GdipDrawLine(g,pG,oriX,yZ,oriX+lenX,yZ);
        SetBkMode(hDC,TRANSPARENT);
        SetTextColor(hDC,0x888888);
        TextOutA(hDC,(int)oriX-14,(int)yZ-7,"0",1);
    }
    GdipDeletePen(pG);

    /* ── Histogramme ─────────────────────────────────────────────────── */
    float yZF=(vMin<0&&vMax>0)?
        (float)rBottom-(float)((0.0-vMin)/(vMax-vMin))*panelInnerH:(float)rBottom;
    if (yZF<(float)rTop)    yZF=(float)rTop;
    if (yZF>(float)rBottom) yZF=(float)rBottom;

    for (int i=vs;i<=li;++i){
        if (i<0||i>=count||std::isnan(dvi[i])) continue;
        float x=oriX+(i-vs)*stepX;
        float bw=stepX>1?stepX-0.5f:stepX;
        float y=(float)rBottom-(float)((dvi[i]-vMin)/(vMax-vMin))*panelInnerH;
        float top,bot;
        if (dvi[i]>=0){top=y;  bot=yZF;}
        else          {top=yZF;bot=y;}
        float h=bot-top; if (h<0.5f) h=0.5f;
        unsigned int col=(dvi[i]>=0)?0x8000AA44:0x80CC2200;
        GpSolidFill* brH=nullptr; GdipCreateSolidFill(col,&brH);
        GdipFillRectangle(g,(GpBrush*)brH,x,top,bw,h);
        GdipDeleteBrush(brH);
    }

    /* ── Courbe DVI : orange ─────────────────────────────────────────── */
    GpPen* pDVI=nullptr; GdipCreatePen1(0xFFFFAA00,2.0f,UnitPixel,&pDVI);
    DrawCurve(g,pDVI,dvi,count,vs,li,oriX,rBottom,panelInnerH,vMin,vMax,stepX);
    GdipDeletePen(pDVI);

    /* ── Label + bouton X ────────────────────────────────────────────── */
    char lbl[48];
    if (panelCount>1) std::snprintf(lbl,sizeof(lbl),"DVI(%d,%d) #%d",period,smooth,panelIndex+1);
    else              std::snprintf(lbl,sizeof(lbl),"DVI(%d,%d)",period,smooth);
    SetBkMode(hDC,TRANSPARENT);
    SetTextColor(hDC,0xFFAA00);
    TextOutA(hDC,(int)oriX-55,rTop+2,lbl,(int)std::strlen(lbl));
    SetTextColor(hDC,0);
    float bxBtn=oriX+lenX-(float)closeBtnSz-2.0f;
    DrawCloseBtn(g,bxBtn,(float)rTop+2.0f,(float)closeBtnSz);
}

/* ── Enregistrement ──────────────────────────────────────────────────── */
//QCHART_REGISTER: Register_DirectionalVolumeIndex
extern "C" void Register_DirectionalVolumeIndex(IndicatorRegistry* reg) {
    if (reg->count>=MAX_INDICATORS) return;
    IndicatorDef* d=&reg->defs[reg->count++];
    std::strncpy(d->name,       "Directional Volume Index", sizeof(d->name)-1);
    std::strncpy(d->labelPrefix,"DVI",                     sizeof(d->labelPrefix)-1);
    std::strncpy(d->param2Label,"Smooth",                  sizeof(d->param2Label)-1);
    d->defaultPeriod = 200;
    d->defaultParam2 = 5;
    d->isPanel       = 1;
    d->drawOverlay   = nullptr;
    d->drawPanel     = DVI_DrawPanel;
}
