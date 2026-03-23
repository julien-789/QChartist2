/*
 * indicators/tsf.cpp
 * TSF / LSMA (Least Squares Moving Average) — overlay.
 *
 * Implémente `linreg(close, length, offset)` de Pine Script :
 *   linreg(src, length, offset) = valeur de la droite de régression
 *   calculée sur [i-length+1..i], évaluée à i+offset
 *   (offset=0 → valeur à la barre courante = TSF standard)
 *
 * Lreg fidèle au MQL4 TSF.mq4 :
 *   x=0 pour barre courante i (st0 MQL4)
 *   x=k pour barre i-k (st0+k MQL4, plus ancienne)
 *   Alfa = valeur en x=0 = TSF à la barre i
 *
 * Affiche :
 *   LSMA (blanc/rouge)         = linreg(close, length, 0)
 *   LSMA smoothed (bleu)       = WMA(LSMA, smooth)
 *
 * period = length (défaut 21), param2 = smooth (défaut 8)
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

/* ── linreg(src, length, offset=0) ──────────────────────────────────── */
/* x=0 pour barre i (courante), x=k pour barre i-k (plus ancienne)     */
static double Linreg(const double* src, int i, int n, int count)
{
    if (n<=0||i<0||i>=count||i-(n-1)<0) return NAN;
    double Sx=0,Sxx=0,Sxy=0;
    double Sy=src[i];   /* x=0 */
    for (int k=1;k<n;k++){
        double x=(double)k;
        double y=src[i-k];
        Sx +=x; Sy+=y; Sxx+=x*x; Sxy+=x*y;
    }
    double c=Sxx*(double)n-Sx*Sx;
    if (c==0.0) return Sy/(double)n;
    double Beta=(n*Sxy-Sx*Sy)/c;
    double Alfa=(Sy-Beta*Sx)/(double)n;
    return Alfa;
}

/* ── WMA backward ────────────────────────────────────────────────────── */
static void CalcWMA(const double* src, int count, int per, double* out)
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

/* ── Helper dessin courbe ────────────────────────────────────────────── */
static void DrawCurve(GpGraphics* g, GpPen* pen,
    const double* buf, int count, int vs, int li,
    float oriX, float oriY, float stepX, double vMin, double scaleY)
{
    float ox=0,oy=0; bool fst=true;
    for (int i=vs;i<=li;++i){
        if (i<0||i>=count||std::isnan(buf[i])){fst=true;continue;}
        float x=oriX+(i-vs)*stepX+stepX*0.5f;
        float y=oriY-(float)((buf[i]-vMin)*scaleY);
        if (!fst) GdipDrawLine(g,pen,ox,oy,x,y);
        ox=x;oy=y;fst=false;
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

/* ── Callback DrawOverlay ────────────────────────────────────────────── */
static void TSF_DrawOverlay(
    GpGraphics*         g,
    HDC                 hDC,
    const double*       closes,
    const double*       opens,
    const double*       highs,
    const double*       lows,
    const double*       /*volumes*/,
    const int*          /*weekdays*/,
    int                 count,
    int                 period,
    int                 param2,
    int                 panelIndex,
    const ChartCtx*     ctx,
    int                 closeBtnSz,
    const unsigned int* /*colors*/)
{
    int length = (period>0) ? period : 225;
    int smooth = (param2>0) ? param2 : 8;
    if (count>MAX_B||count<length) return;

    float  oriX=ctx->oriX, oriY=ctx->oriY;
    float  stepX=ctx->stepX, lenX=ctx->lenX;
    double vMin=ctx->vMin, scaleY=ctx->scaleY;
    int    vs=ctx->viewStart, li=ctx->lastIdx;

    /* ── LSMA = linreg(close, length, 0) ────────────────────────────── */
    static double lsmaBuf[MAX_B];
    for (int i=0;i<count;++i) lsmaBuf[i]=NAN;
    for (int i=length-1;i<count;++i)
        lsmaBuf[i]=Linreg(closes,i,length,count);

    /* ── LSMA smoothed = WMA(LSMA, smooth) ──────────────────────────── */
    static double lsmaS[MAX_B];
    CalcWMA(lsmaBuf,count,smooth,lsmaS);

    /* ── Rendu ───────────────────────────────────────────────────────── */

    /* LSMA smoothed : bleu (#2299CC) */
    GpPen* pS=nullptr; GdipCreatePen1(0xFF2299CC,2.0f,UnitPixel,&pS);
    DrawCurve(g,pS,lsmaS,count,vs,li,oriX,oriY,stepX,vMin,scaleY);
    GdipDeletePen(pS);

    /* LSMA : colorée selon position vs lsmaS (blanc si au-dessus, rouge si en-dessous) */
    {
        float ox=0,oy=0; bool fst=true;
        for (int i=vs;i<=li;++i){
            if (i<0||i>=count||std::isnan(lsmaBuf[i])){fst=true;continue;}
            float x=oriX+(i-vs)*stepX+stepX*0.5f;
            float y=oriY-(float)((lsmaBuf[i]-vMin)*scaleY);
            if (!fst){
                /* Couleur : blanc si LSMA > lsmaS, rouge sinon */
                bool above=(!std::isnan(lsmaS[i-1])&&lsmaBuf[i-1]>lsmaS[i-1]);
                unsigned int col=above?0xFFEEEEEE:0xFFCC2222;
                GpPen* p=nullptr; GdipCreatePen1(col,2.0f,UnitPixel,&p);
                GdipDrawLine(g,p,ox,oy,x,y);
                GdipDeletePen(p);
            }
            ox=x;oy=y;fst=false;
        }
    }

    /* Croix aux croisements LSMA/lsmaS */
    for (int i=vs+1;i<=li;++i){
        if (i<1||i>=count) continue;
        if (std::isnan(lsmaBuf[i])||std::isnan(lsmaS[i])) continue;
        if (std::isnan(lsmaBuf[i-1])||std::isnan(lsmaS[i-1])) continue;
        bool crossUp  =(lsmaBuf[i-1]<=lsmaS[i-1]&&lsmaBuf[i]>lsmaS[i]);
        bool crossDown=(lsmaBuf[i-1]>=lsmaS[i-1]&&lsmaBuf[i]<lsmaS[i]);
        if (crossUp||crossDown){
            float xc=oriX+(i-vs)*stepX+stepX*0.5f;
            float yc=oriY-(float)(((lsmaBuf[i]+lsmaS[i])*0.5-vMin)*scaleY);
            unsigned int col=crossUp?0xFF00CC00:0xFFCC0000;
            GpPen* px=nullptr; GdipCreatePen1(col,1.5f,UnitPixel,&px);
            float r=4.0f;
            GdipDrawLine(g,px,xc-r,yc-r,xc+r,yc+r);
            GdipDrawLine(g,px,xc+r,yc-r,xc-r,yc+r);
            GdipDeletePen(px);
        }
    }

    /* ── Label + bouton X ────────────────────────────────────────────── */
    char lbl[32];
    std::snprintf(lbl,sizeof(lbl),"TSF(%d,%d)",length,smooth);
    int lblX=(int)oriX+4, lblY=28+14+panelIndex*(closeBtnSz+4);
    SetBkMode(hDC,TRANSPARENT);
    SetTextColor(hDC,0xCC0000);
    TextOutA(hDC,lblX,lblY,lbl,(int)strlen(lbl));
    SetTextColor(hDC,0);
    float btnX=(float)(lblX+(int)strlen(lbl)*7+3);
    DrawCloseBtn(g,btnX,(float)(lblY-1),(float)closeBtnSz);
}

/* ── Enregistrement ──────────────────────────────────────────────────── */
//QCHART_REGISTER: Register_TSF
extern "C" void Register_TSF(IndicatorRegistry* reg) {
    if (reg->count>=MAX_INDICATORS) return;
    IndicatorDef* d=&reg->defs[reg->count++];
    std::strncpy(d->name,       "TSF / LSMA",  sizeof(d->name)-1);
    std::strncpy(d->labelPrefix,"TSF",         sizeof(d->labelPrefix)-1);
    std::strncpy(d->param2Label,"WMA Smooth",  sizeof(d->param2Label)-1);
    d->defaultPeriod = 225;   /* length */
    d->defaultParam2 = 8;    /* smooth */
    d->isPanel       = 0;
    d->drawOverlay   = TSF_DrawOverlay;
    d->drawPanel     = nullptr;
}
