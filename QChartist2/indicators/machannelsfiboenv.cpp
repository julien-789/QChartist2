/*
 * indicators/machannelsfiboenv.cpp
 * MA Channels FiboEnv Mid — indicateur overlay.
 *
 * Algorithme (fidèle à MA_Chanels_FiboEnv_Mid.cpp) :
 *   MA = SMA(MedianPrice, period)   MedianPrice = (H+L)/2
 *
 *   Passe 1 : calculer max = max(H[i]-MA[i]) et min = min(L[i]-MA[i])
 *   Inc3 = (max-min) * 0.5     (niveau ±0.5)
 *   Inc2 = (max-min) * 0.264   (niveau ±0.264)
 *   Inc1 = (max-min) * 0.118   (niveau ±0.118)
 *
 *   7 courbes :
 *   buf1 = MA + Inc3   (MediumOrchid)
 *   buf2 = MA + Inc2   (Violet)
 *   buf3 = MA + Inc1   (MediumOrchid)
 *   buf4 = MA          (Violet — ligne centrale)
 *   buf5 = MA - Inc1   (MediumOrchid)
 *   buf6 = MA - Inc2   (Violet)
 *   buf7 = MA - Inc3   (MediumOrchid)
 *
 * period = MAPeriod (défaut 55, codé en dur dans l'original)
 * Le paramètre "period" de la fenêtre Technicals remplace le 55.
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

/* ── Dessiner une courbe ─────────────────────────────────────────────── */
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

/* ── Remplissage entre deux courbes ──────────────────────────────────── */
static void FillBand(GpGraphics* g, unsigned int col,
    const double* top, const double* bot, int count, int vs, int li,
    float oriX, float oriY, float stepX, double vMin, double scaleY)
{
    for (int i=vs;i<=li;++i){
        if (i<0||i>=count||std::isnan(top[i])||std::isnan(bot[i])) continue;
        float x  = oriX+(i-vs)*stepX;
        float yT = oriY-(float)((top[i]-vMin)*scaleY);
        float yB = oriY-(float)((bot[i]-vMin)*scaleY);
        if (yT>yB){float t=yT;yT=yB;yB=t;}
        float h=yB-yT; if(h<0.5f)h=0.5f;
        GpSolidFill* br=nullptr; GdipCreateSolidFill(col,&br);
        GdipFillRectangle(g,(GpBrush*)br,x,yT,stepX,h);
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
static void FiboEnv_DrawOverlay(
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
    if (count>MAX_B||count<period) return;

    float  oriX=ctx->oriX, oriY=ctx->oriY;
    float  stepX=ctx->stepX, lenX=ctx->lenX;
    double vMin=ctx->vMin, scaleY=ctx->scaleY;
    int    vs=ctx->viewStart, li=ctx->lastIdx;

    /* ── Passe 1 : SMA sur MedianPrice = (H+L)/2 ────────────────────── */
    static double maBuf[MAX_B];
    for (int i=0;i<count;++i) maBuf[i]=NAN;
    {
        double sum=0;
        for (int i=0;i<period;++i) sum+=(highs[i]+lows[i])*0.5;
        maBuf[period-1]=sum/period;
        for (int i=period;i<count;++i){
            sum+=(highs[i]+lows[i])*0.5-(highs[i-period]+lows[i-period])*0.5;
            maBuf[i]=sum/period;
        }
    }

    /* ── Passe 2 : max(H-MA) et min(L-MA) sur toutes les barres ──────── */
    double maxDev=0, minDev=0;
    for (int i=period-1;i<count;++i){
        if (std::isnan(maBuf[i])) continue;
        double top = highs[i]-maBuf[i];
        double bot = lows[i] -maBuf[i];
        if (top>maxDev) maxDev=top;
        if (bot<minDev) minDev=bot;
    }
    double rng   = maxDev-minDev;
    double inc1  = rng*0.118;
    double inc2  = rng*0.264;
    double inc3  = rng*0.500;

    /* ── Passe 3 : 7 buffers ─────────────────────────────────────────── */
    static double b1[MAX_B],b2[MAX_B],b3[MAX_B],b4[MAX_B];
    static double b5[MAX_B],b6[MAX_B],b7[MAX_B];
    for (int i=0;i<count;++i){
        if (std::isnan(maBuf[i])){
            b1[i]=b2[i]=b3[i]=b4[i]=b5[i]=b6[i]=b7[i]=NAN;
            continue;
        }
        double ma=maBuf[i];
        b1[i]=ma+inc3; b2[i]=ma+inc2; b3[i]=ma+inc1;
        b4[i]=ma;
        b5[i]=ma-inc1; b6[i]=ma-inc2; b7[i]=ma-inc3;
    }

    /* ── Rendu : remplissages entre bandes ───────────────────────────── */
    /* Zone externe (b1/b7) : très transparent */
    FillBand(g,0x08BA55D3,b1,b2,count,vs,li,oriX,oriY,stepX,vMin,scaleY);
    FillBand(g,0x08BA55D3,b6,b7,count,vs,li,oriX,oriY,stepX,vMin,scaleY);
    /* Zone intermédiaire (b2/b3 et b5/b6) */
    FillBand(g,0x12EE82EE,b2,b3,count,vs,li,oriX,oriY,stepX,vMin,scaleY);
    FillBand(g,0x12EE82EE,b5,b6,count,vs,li,oriX,oriY,stepX,vMin,scaleY);
    /* Zone centrale (b3/b5) : un peu plus opaque */
    FillBand(g,0x18BA55D3,b3,b5,count,vs,li,oriX,oriY,stepX,vMin,scaleY);

    /* ── Courbes ─────────────────────────────────────────────────────── */
    /* MediumOrchid #BA55D3 et Violet #EE82EE alternés */
    struct { const double* buf; unsigned int col; float w; } lines[7]={
        {b1,0xFFBA55D3,1.2f},
        {b2,0xFFEE82EE,1.0f},
        {b3,0xFFBA55D3,1.0f},
        {b4,0xFFEE82EE,1.5f},  /* ligne centrale plus épaisse */
        {b5,0xFFBA55D3,1.0f},
        {b6,0xFFEE82EE,1.0f},
        {b7,0xFFBA55D3,1.2f},
    };
    for (int k=0;k<7;++k){
        GpPen* pen=nullptr;
        GdipCreatePen1(lines[k].col,lines[k].w,UnitPixel,&pen);
        DrawLine(g,pen,lines[k].buf,count,vs,li,oriX,oriY,stepX,vMin,scaleY);
        GdipDeletePen(pen);
    }

    /* ── Label + bouton X ────────────────────────────────────────────── */
    char lbl[32];
    std::snprintf(lbl,sizeof(lbl),"FiboEnv(%d)",period);
    int lblX=(int)oriX+4, lblY=28+14+panelIndex*(closeBtnSz+4);
    SetBkMode(hDC,TRANSPARENT);
    SetTextColor(hDC,0xBA55D3>>8|0xFF000000); /* MediumOrchid approx */
    SetTextColor(hDC,0x9900BB);
    TextOutA(hDC,lblX,lblY,lbl,(int)std::strlen(lbl));
    SetTextColor(hDC,0);
    float btnX=(float)(lblX+(int)std::strlen(lbl)*7+3);
    DrawCloseBtn(g,btnX,(float)(lblY-1),(float)closeBtnSz);
}

/* ── Enregistrement ──────────────────────────────────────────────────── */
//QCHART_REGISTER: Register_MAFiboEnv
extern "C" void Register_MAFiboEnv(IndicatorRegistry* reg) {
    if (reg->count>=MAX_INDICATORS) return;
    IndicatorDef* d=&reg->defs[reg->count++];
    std::strncpy(d->name,       "MA Channels FiboEnv", sizeof(d->name)-1);
    std::strncpy(d->labelPrefix,"FiboEnv",             sizeof(d->labelPrefix)-1);
    d->defaultPeriod = 55;
    d->defaultParam2 = 0;
    d->isPanel       = 0;
    d->drawOverlay   = FiboEnv_DrawOverlay;
    d->drawPanel     = nullptr;
}
