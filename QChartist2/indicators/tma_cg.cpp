/*
 * indicators/tma_cg.cpp
 * TMA+CG (Triangular Moving Average + Channel Generator) — overlay.
 *
 * Algorithme (fidèle à TMA_CG.cpp) :
 *
 * TMA[i] = moyenne pondérée triangulaire centrée sur i :
 *   sum  = (HalfLength+1)*price[i]
 *   sumw = (HalfLength+1)
 *   pour j=1..HalfLength, k=HalfLength..1 :
 *     sum  += k*price[i+j]  (barres plus récentes dans MQL4 = index plus haut)
 *     sumw += k
 *     si j<=i : sum += k*price[i-j]; sumw += k
 *   TMA[i] = sum/sumw
 *
 * Dans QChart (0=plus ancien, count-1=plus récent) :
 *   "i+j" MQL4 (plus ancien) → i-j  QChart
 *   "i-j" MQL4 (plus récent) → i+j  QChart
 *
 * diff = price[i] - TMA[i]
 * wuBuffer/wdBuffer : variance pondérée asymétrique (EMA sur diff² positifs/négatifs)
 * upBuffer[i] = TMA[i] + BandsDeviations * sqrt(wuBuffer[i])
 * dnBuffer[i] = TMA[i] - BandsDeviations * sqrt(wdBuffer[i])
 *
 * period = HalfLength (défaut 56)
 * BandsDeviations = 2.5 (codé)
 * Source = PRICE_WEIGHTED = (H+L+C+C)/4
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

static const int    MAX_B      = 4096;
static const double BANDS_DEV  = 2.5;

/* ── Prix pondéré (PRICE_WEIGHTED) ───────────────────────────────────── */
static double WPrice(const double* h, const double* l, const double* c, int i)
{
    return (h[i] + l[i] + c[i]*2.0) * 0.25;
}

/* ── Helper dessin courbe ────────────────────────────────────────────── */
static void DrawLine(GpGraphics* g, GpPen* pen,
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

/* ── Remplissage kumo entre up et dn ────────────────────────────────── */
static void FillBand(GpGraphics* g,
    const double* up, const double* dn, int count, int vs, int li,
    float oriX, float oriY, float stepX, double vMin, double scaleY)
{
    for (int i=vs;i<=li;++i){
        if (i<0||i>=count||std::isnan(up[i])||std::isnan(dn[i])) continue;
        float x  = oriX+(i-vs)*stepX;
        float yU = oriY-(float)((up[i]-vMin)*scaleY);
        float yD = oriY-(float)((dn[i]-vMin)*scaleY);
        if (yU>yD){float t=yU;yU=yD;yD=t;}
        float h=yD-yU; if(h<0.5f)h=0.5f;
        GpSolidFill* br=nullptr; GdipCreateSolidFill(0x10888888,&br);
        GdipFillRectangle(g,(GpBrush*)br,x,yU,stepX,h);
        GdipDeleteBrush(br);
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
static void TMACG_DrawOverlay(
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
    int                 /*param2*/,
    int                 panelIndex,
    const ChartCtx*     ctx,
    int                 closeBtnSz,
    const unsigned int* /*colors*/)
{
    if (count>MAX_B) return;
    int HalfLength = (period>0) ? period : 56;
    if (HalfLength<1) HalfLength=1;
    double FullLength = 2.0*HalfLength + 1.0;

    float  oriX=ctx->oriX, oriY=ctx->oriY;
    float  stepX=ctx->stepX, lenX=ctx->lenX;
    double vMin=ctx->vMin, scaleY=ctx->scaleY;
    int    vs=ctx->viewStart, li=ctx->lastIdx;

    /* ── Calcul TMA ──────────────────────────────────────────────────── */
    static double tmBuf[MAX_B];
    static double upBuf[MAX_B];
    static double dnBuf[MAX_B];
    static double wuBuf[MAX_B];
    static double wdBuf[MAX_B];

    for (int i=0;i<count;++i)
        tmBuf[i]=upBuf[i]=dnBuf[i]=wuBuf[i]=wdBuf[i]=NAN;

    /* Calcul TMA sur toutes les barres.
     * Dans l'original MQL4 :
     *   i+j = barres plus ANCIENNES (index plus grand en MQL4)
     *   i-j = barres plus RÉCENTES  (index plus petit en MQL4)
     * Dans QChart (0=ancien, count-1=récent) :
     *   i-j = barres plus ANCIENNES
     *   i+j = barres plus RÉCENTES
     * On traduit directement : QChart[i-j] ↔ MQL4[i+j] et QChart[i+j] ↔ MQL4[i-j]
     */
    for (int i=0;i<count;++i){
        double price_i = WPrice(highs,lows,closes,i);
        double sum  = (HalfLength+1)*price_i;
        double sumw = (HalfLength+1);

        for (int j=1, k=HalfLength; j<=HalfLength; j++, k--){
            /* barres plus anciennes (MQL4: i+j) = QChart: i-j */
            if (i-j >= 0){
                sum  += k * WPrice(highs,lows,closes,i-j);
                sumw += k;
            }
            /* barres plus récentes (MQL4: i-j) = QChart: i+j */
            if (i+j < count){
                sum  += k * WPrice(highs,lows,closes,i+j);
                sumw += k;
            }
        }
        tmBuf[i] = sum/sumw;
    }

    /* ── Calcul bandes asymétriques ──────────────────────────────────── */
    /* Dans l'original MQL4, l'itération va de i=limit→0 (récent→ancien),
     * donc "i+1" en MQL4 = barre précédemment traitée = plus ancienne.
     * Dans QChart on itère du plus ancien (0) au plus récent (count-1),
     * donc "i-1" est la barre précédemment traitée = plus ancienne aussi.
     *
     * La barre d'initialisation MQL4 : i==(Bars-HalfLength-1)
     * → correspond à QChart : i == HalfLength (depuis le bas)
     */
    int initBar = HalfLength;   /* première barre calculable */
    if (initBar >= count) return;

    /* Initialisation à la barre initBar */
    {
        double diff = WPrice(highs,lows,closes,initBar) - tmBuf[initBar];
        upBuf[initBar] = tmBuf[initBar];
        dnBuf[initBar] = tmBuf[initBar];
        if (diff>=0){ wuBuf[initBar]=diff*diff; wdBuf[initBar]=0; }
        else        { wdBuf[initBar]=diff*diff; wuBuf[initBar]=0; }
    }

    /* Propagation vers les barres plus récentes */
    for (int i=initBar+1; i<count; ++i){
        double diff = WPrice(highs,lows,closes,i) - tmBuf[i];
        if (diff>=0){
            wuBuf[i] = (wuBuf[i-1]*(FullLength-1) + diff*diff) / FullLength;
            wdBuf[i] =  wdBuf[i-1]*(FullLength-1)              / FullLength;
        } else {
            wdBuf[i] = (wdBuf[i-1]*(FullLength-1) + diff*diff) / FullLength;
            wuBuf[i] =  wuBuf[i-1]*(FullLength-1)              / FullLength;
        }
        upBuf[i] = tmBuf[i] + BANDS_DEV * sqrt(wuBuf[i]);
        dnBuf[i] = tmBuf[i] - BANDS_DEV * sqrt(wdBuf[i]);
    }

    /* ── Rendu ───────────────────────────────────────────────────────── */

    /* Zone entre les bandes */
    FillBand(g,upBuf,dnBuf,count,vs,li,oriX,oriY,stepX,vMin,scaleY);

    /* Bande haute (rouge) */
    GpPen* pUp=nullptr; GdipCreatePen1(0xFFCC0000,1.2f,UnitPixel,&pUp);
    DrawLine(g,pUp,upBuf,count,vs,li,oriX,oriY,stepX,vMin,scaleY);
    GdipDeletePen(pUp);

    /* Bande basse (lime green) */
    GpPen* pDn=nullptr; GdipCreatePen1(0xFF32CD32,1.2f,UnitPixel,&pDn);
    DrawLine(g,pDn,dnBuf,count,vs,li,oriX,oriY,stepX,vMin,scaleY);
    GdipDeletePen(pDn);

    /* TMA centrale (dim gray) */
    GpPen* pTm=nullptr; GdipCreatePen1(0xFF696969,1.5f,UnitPixel,&pTm);
    GdipSetPenDashStyle(pTm,DashStyleDot);
    DrawLine(g,pTm,tmBuf,count,vs,li,oriX,oriY,stepX,vMin,scaleY);
    GdipDeletePen(pTm);

    /* ── Label + bouton X ────────────────────────────────────────────── */
    char lbl[32];
    std::snprintf(lbl,sizeof(lbl),"TMA+CG(%d)",HalfLength);
    int lblX=(int)oriX+4, lblY=28+14+panelIndex*(closeBtnSz+4);
    SetBkMode(hDC,TRANSPARENT);
    SetTextColor(hDC,0x696969);
    TextOutA(hDC,lblX,lblY,lbl,(int)std::strlen(lbl));
    SetTextColor(hDC,0);
    float btnX=(float)(lblX+(int)std::strlen(lbl)*7+3);
    DrawCloseBtn(g,btnX,(float)(lblY-1),(float)closeBtnSz);
}

/* ── Enregistrement ──────────────────────────────────────────────────── */
//QCHART_REGISTER: Register_TMACG
extern "C" void Register_TMACG(IndicatorRegistry* reg) {
    if (reg->count>=MAX_INDICATORS) return;
    IndicatorDef* d=&reg->defs[reg->count++];
    std::strncpy(d->name,       "TMA+CG",      sizeof(d->name)-1);
    std::strncpy(d->labelPrefix,"TMA+CG",      sizeof(d->labelPrefix)-1);
    d->defaultPeriod = 56;
    d->defaultParam2 = 0;
    d->isPanel       = 0;
    d->drawOverlay   = TMACG_DrawOverlay;
    d->drawPanel     = nullptr;
}
