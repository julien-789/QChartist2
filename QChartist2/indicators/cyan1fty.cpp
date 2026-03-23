/*
 * indicators/cyan1fty.cpp
 * CyAn_1_Fty — Fisher Transform sur Stochastique, panel séparé.
 *
 * Algorithme (fidèle au Pine Script de référence) :
 *   k    = ta.stoch(close, high, low, lenth)   [0,100]
 *   aux  = 0.5 * ((k/100 - 0.5) * 2) + 0.5 * aux_prev
 *        = (k/100 - 0.5) + 0.5 * aux_prev       (simplifié)
 *   fish = 0.25 * log((1+aux)/(1-aux)) + 0.5 * fish_prev
 *
 * Le paramètre "period" = length du stochastique (défaut 5).
 * outVMin = -1.2, outVMax = +1.2, niveaux ±0.8
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

/* ── Stochastique brut %K sans lissage ───────────────────────────────── */
static double CalcStochRaw(
    const double* closes, const double* highs, const double* lows,
    int count, int i, int lenth)
{
    if (i < lenth - 1 || i >= count) return 50.0;
    double lo = lows[i], hi = highs[i];
    for (int k = 1; k < lenth; ++k) {
        if (lows [i-k] < lo) lo = lows [i-k];
        if (highs[i-k] > hi) hi = highs[i-k];
    }
    double range = hi - lo;
    return (range > 0.0) ? 100.0 * (closes[i] - lo) / range : 50.0;
}

/* ── Helper dessin courbe ─────────────────────────────────────────────── */
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

/* ── Helper bouton X ──────────────────────────────────────────────────── */
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

/* ── Callback DrawPanel ───────────────────────────────────────────────── */
static void CyAn_DrawPanel(
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
    if (count > MAX_B || period < 1 || count < period + 1) return;

    double vMin = -1.2, vMax = 1.2;
    if (outVMin) *outVMin = vMin;
    if (outVMax) *outVMax = vMax;

    float oriX        = ctx->oriX;
    float stepX       = ctx->stepX;
    float lenX        = ctx->lenX;
    int   mainChartH  = ctx->mainChartH;
    int   panelInnerH = panelH - 20;
    int   rTop        = mainChartH + panelIndex * (panelH + panelGap);
    int   rBottom     = rTop + panelInnerH;
    int   vs          = ctx->viewStart;
    int   li          = ctx->lastIdx;

    /* ── Calcul des buffers ─────────────────────────────────────────── */
    static double auxBuf[MAX_B];
    for (int i=0;i<count;++i) auxBuf[i]=NAN;

    double prevAux  = 0.0;
    double prevFish = 0.0;

    for (int i = 0; i < count; ++i) {
        if (i <= period) { prevAux=0.0; prevFish=0.0; continue; }

        double k   = CalcStochRaw(closes, highs, lows, count, i, period);
        /* Pine: 0.5 * ((k/100 - 0.5) * 2) = (k/100 - 0.5) */
        double aux = (k / 100.0 - 0.5) + 0.5 * prevAux;

        /* Clamp strict pour éviter log(0) */
        if (aux >=  1.0) aux =  0.9999;
        if (aux <= -1.0) aux = -0.9999;

        auxBuf[i] = aux;
        prevAux   = aux;
        prevFish  = 0.25 * log((1.0+aux)/(1.0-aux)) + 0.5 * prevFish;
    }

    /* ── Cadre + niveaux ────────────────────────────────────────────── */
    GpPen* pG=nullptr; GdipCreatePen1(0xFFCCCCCC,1.0f,UnitPixel,&pG);
    GdipDrawRectangleI(g,pG,(int)oriX,rTop,(int)lenX,panelInnerH);

    float yZero=(float)rBottom-(float)((0.0 -vMin)/(vMax-vMin))*panelInnerH;
    float yP8  =(float)rBottom-(float)((0.8 -vMin)/(vMax-vMin))*panelInnerH;
    float yM8  =(float)rBottom-(float)((-0.8-vMin)/(vMax-vMin))*panelInnerH;

    GdipDrawLine(g,pG,oriX,yZero,oriX+lenX,yZero);
    GdipSetPenDashStyle(pG,(GpDashStyle)2);   /* DashStyleDot */
    GdipDrawLine(g,pG,oriX,yP8,oriX+lenX,yP8);
    GdipDrawLine(g,pG,oriX,yM8,oriX+lenX,yM8);
    GdipDeletePen(pG);

    SetBkMode(hDC,TRANSPARENT); SetTextColor(hDC,0x888888);
    TextOutA(hDC,(int)oriX-22,(int)yP8 -7,"+.8",3);
    TextOutA(hDC,(int)oriX-22,(int)yM8 -7,"-.8",3);
    TextOutA(hDC,(int)oriX-22,(int)yZero-7,"  0",3);

    /* ── Courbe Aux : jaune (comme Pine) ────────────────────────────── */
    GpPen* pAux=nullptr;
    GdipCreatePen1(0xFFFFFF00,2.0f,UnitPixel,&pAux);
    DrawCurve(g,pAux,auxBuf,count,vs,li,oriX,rBottom,panelInnerH,vMin,vMax,stepX);
    GdipDeletePen(pAux);

    /* ── Label + bouton X ───────────────────────────────────────────── */
    char lbl[32];
    if (panelCount>1) std::snprintf(lbl,sizeof(lbl),"CyAn(%d) #%d",period,panelIndex+1);
    else              std::snprintf(lbl,sizeof(lbl),"CyAn(%d)",period);
    SetTextColor(hDC,0xCCCC00);
    TextOutA(hDC,(int)oriX-55,rTop+2,lbl,(int)std::strlen(lbl));
    SetTextColor(hDC,0);
    float bxBtn=oriX+lenX-(float)closeBtnSz-2.0f;
    DrawCloseBtn(g,bxBtn,(float)rTop+2.0f,(float)closeBtnSz);
}

/* ── Enregistrement ───────────────────────────────────────────────────── */
//QCHART_REGISTER: Register_CyAn1Fty
extern "C" void Register_CyAn1Fty(IndicatorRegistry* reg) {
    if (reg->count>=MAX_INDICATORS) return;
    IndicatorDef* d=&reg->defs[reg->count++];
    std::strncpy(d->name,       "CyAn_1_Fty", sizeof(d->name)-1);
    std::strncpy(d->labelPrefix,"CyAn",       sizeof(d->labelPrefix)-1);
    d->defaultPeriod = 5;
    d->defaultParam2 = 0;
    d->isPanel       = 1;
    d->drawOverlay   = nullptr;
    d->drawPanel     = CyAn_DrawPanel;
}
