/*
 * indicators/bbhl.cpp
 * BB-HL (Bollinger Bands High-Low) — indicateur overlay.
 *
 * Fidèle au Pine Script de référence :
 *   ma      = SMA( (H+L)/2, period )
 *   highDev = (H - ma)²
 *   lowDev  = (L - ma)²
 *   devMax  = max(highDev, lowDev)
 *   devAvg  = mean( devMax[i-period+1 .. i] )
 *   stdev   = sqrt(devAvg)
 *   upper   = ma + nDev * stdev
 *   lower   = ma - nDev * stdev
 *
 * Paramètres :
 *   period = fenêtre SMA (défaut 200)
 *   param2 = nDev * 10  ex: 20 = nDev 2.0  (entier car param2 est Long)
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

/* ── Helper dessin courbe ─────────────────────────────────────────────── */
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

/* ── Callback DrawOverlay ─────────────────────────────────────────────── */
static void BBHL_DrawOverlay(
    GpGraphics*         g,
    HDC                 hDC,
    const double*       closes,
    const double*       /*opens*/,
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
    if (count > MAX_B || count < period) return;

    float  oriX   = ctx->oriX;
    float  oriY   = ctx->oriY;
    float  stepX  = ctx->stepX;
    float  lenX   = ctx->lenX;
    double vMin   = ctx->vMin;
    double scaleY = ctx->scaleY;
    int    vs     = ctx->viewStart;
    int    li     = ctx->lastIdx;

    double ndev = (param2 > 0) ? param2 / 10.0 : 2.0;

    /* ── Étape 1 : SMA sur hl2 = (H+L)/2 ─────────────────────────────── */
    static double maBuf[MAX_B];
    for (int i = 0; i < count; ++i) maBuf[i] = NAN;

    /* Précalcul de la somme glissante */
    double runSum = 0.0;
    for (int i = 0; i < count; ++i) {
        runSum += (highs[i] + lows[i]) * 0.5;
        if (i >= period - 1) {
            maBuf[i] = runSum / period;
            runSum -= (highs[i - period + 1] + lows[i - period + 1]) * 0.5;
        }
    }

    /* ── Étape 2 : devMax[i] = max( (H-MA)², (L-MA)² ) ──────────────── */
    static double devMax[MAX_B];
    for (int i = 0; i < count; ++i) {
        if (std::isnan(maBuf[i])) { devMax[i] = NAN; continue; }
        double hd = highs[i] - maBuf[i]; hd = hd * hd;
        double ld = lows[i]  - maBuf[i]; ld = ld * ld;
        devMax[i] = (hd >= ld) ? hd : ld;
    }

    /* ── Étape 3 : devAvg[i] = mean( devMax[i-period+1..i] ) ─────────── */
    /* ── puis upper/lower ─────────────────────────────────────────────── */
    static double upBuf[MAX_B], dnBuf[MAX_B];
    for (int i = 0; i < count; ++i) upBuf[i] = dnBuf[i] = NAN;

    double devSum = 0.0;
    int    devN   = 0;

    for (int i = 0; i < count; ++i) {
        if (std::isnan(devMax[i])) { devSum = 0.0; devN = 0; continue; }

        devSum += devMax[i];
        devN++;

        /* Retirer la valeur qui sort de la fenêtre */
        if (devN > period) {
            int old = i - period;
            if (old >= 0 && !std::isnan(devMax[old]))
                devSum -= devMax[old];
            devN = period;
        }

        if (devN < period) continue;   /* pas encore assez de données */

        double stdev = std::sqrt(devSum / period);
        upBuf[i] = maBuf[i] + ndev * stdev;
        dnBuf[i] = maBuf[i] - ndev * stdev;
    }

    /* ── Remplissage zone entre les bandes ────────────────────────────── */
    for (int i=vs;i<=li;++i){
        if (i<0||i>=count||std::isnan(upBuf[i])||std::isnan(dnBuf[i])) continue;
        float x    = oriX+(i-vs)*stepX;
        float yTop = oriY-(float)((upBuf[i]-vMin)*scaleY);
        float yBot = oriY-(float)((dnBuf[i]-vMin)*scaleY);
        float h    = yBot-yTop; if (h<=0) continue;
        GpSolidFill* brF=nullptr;
        GdipCreateSolidFill(0x10800080,&brF);
        GdipFillRectangle(g,(GpBrush*)brF,x,yTop,stepX,h);
        GdipDeleteBrush(brF);
    }

    /* ── Courbes ──────────────────────────────────────────────────────── */
    /* Bandes : silver/gris */
    GpPen* pBand=nullptr;
    GdipCreatePen1(0xFFAAAAAA,1.5f,UnitPixel,&pBand);
    DrawCurve(g,pBand,upBuf,count,vs,li,oriX,oriY,stepX,vMin,scaleY);
    DrawCurve(g,pBand,dnBuf,count,vs,li,oriX,oriY,stepX,vMin,scaleY);
    GdipDeletePen(pBand);

    /* MA centrale : orange */
    GpPen* pMid=nullptr;
    GdipCreatePen1(0xFFFF8800,1.5f,UnitPixel,&pMid);
    DrawCurve(g,pMid,maBuf,count,vs,li,oriX,oriY,stepX,vMin,scaleY);
    GdipDeletePen(pMid);

    /* ── Label + bouton X ────────────────────────────────────────────── */
    char lbl[32];
    std::snprintf(lbl,sizeof(lbl),"BBHL(%d,%.1f)",period,ndev);
    int lblX=(int)oriX+4;
    int lblY=28+14+panelIndex*(closeBtnSz+4);
    SetBkMode(hDC,TRANSPARENT);
    SetTextColor(hDC,0x0088FF);
    TextOutA(hDC,lblX,lblY,lbl,(int)std::strlen(lbl));
    SetTextColor(hDC,0);
    float btnX=(float)(lblX+(int)std::strlen(lbl)*7+3);
    DrawCloseBtn(g,btnX,(float)(lblY-1),(float)closeBtnSz);
}

/* ── Enregistrement ───────────────────────────────────────────────────── */
//QCHART_REGISTER: Register_BBHL
extern "C" void Register_BBHL(IndicatorRegistry* reg) {
    if (reg->count>=MAX_INDICATORS) return;
    IndicatorDef* d=&reg->defs[reg->count++];
    std::strncpy(d->name,       "BB - HL",   sizeof(d->name)-1);
    std::strncpy(d->labelPrefix,"BBHL",      sizeof(d->labelPrefix)-1);
    std::strncpy(d->param2Label,"nDev x10",  sizeof(d->param2Label)-1);
    d->defaultPeriod = 200;
    d->defaultParam2 = 20;   /* 20 = ndev 2.0 */
    d->isPanel       = 0;
    d->drawOverlay   = BBHL_DrawOverlay;
    d->drawPanel     = nullptr;
}
