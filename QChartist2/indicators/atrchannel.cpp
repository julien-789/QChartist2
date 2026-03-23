/*
 * indicators/atrchannel.cpp
 * ATR Channel — indicateur overlay.
 *
 * Algorithme (fidèle à atrchannel.qti) :
 *   SMA(49) calculée sur le Typical Price = (H+L+C)/3
 *   ATR(period) = moyenne des True Range sur `period` barres
 *   Canal haut = SMA49 + ATR * 4.8
 *   Canal bas  = SMA49 - ATR * 4.8
 *
 * Le paramètre "period" configure la période ATR (défaut 18).
 * La période SMA est fixée à 49 (valeur originale).
 * Le multiplicateur est fixé à 4.8 (mult_factor3 de l'original).
 *
 * Compilation automatique via build.bat.
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

static const int    MAX_B        = 4096;
static const int    SMA_PERIOD   = 49;
static const double MULT_FACTOR  = 4.8;

/* ── Calcul de l'ATR ──────────────────────────────────────────────────── */
static double CalcATR(
    const double* closes, const double* highs, const double* lows,
    int count, int i, int period)
{
    if (i < period || i >= count) return 0.0;
    double atr = 0.0;
    for (int k = i; k > i - period; --k) {
        double tr = highs[k] - lows[k];
        if (k > 0) {
            double h = highs[k] - closes[k-1]; if (h < 0) h = -h;
            double l = lows[k]  - closes[k-1]; if (l < 0) l = -l;
            if (h > tr) tr = h;
            if (l > tr) tr = l;
        }
        atr += tr;
    }
    return atr / period;
}

/* ── Calcul de la SMA(49) sur typical price ──────────────────────────── */
static double CalcSMA49(
    const double* highs, const double* lows, const double* closes,
    int count, int i)
{
    if (i < SMA_PERIOD - 1 || i >= count) return -1.0;
    double sum = 0.0;
    for (int k = i; k > i - SMA_PERIOD; --k)
        sum += (highs[k] + lows[k] + closes[k]) / 3.0;
    return sum / SMA_PERIOD;
}

/* ── Helper dessin courbe ─────────────────────────────────────────────── */
static void DrawCurve(GpGraphics* g, GpPen* pen,
    const double* buf, int count, int vs, int li,
    float oriX, float oriY, float stepX, double vMin, double scaleY)
{
    float ox=0,oy=0; bool fst=true;
    for (int i=vs;i<=li;++i){
        if (i<0||i>=count||std::isnan(buf[i])||buf[i]<0){fst=true;continue;}
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
static void ATRChan_DrawOverlay(
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
    if (count > MAX_B || count < SMA_PERIOD + period) return;

    float  oriX   = ctx->oriX;
    float  oriY   = ctx->oriY;
    float  stepX  = ctx->stepX;
    float  lenX   = ctx->lenX;
    double vMin   = ctx->vMin;
    double scaleY = ctx->scaleY;
    int    vs     = ctx->viewStart;
    int    li     = ctx->lastIdx;

    /* ── Précalcul des buffers ────────────────────────────────────────── */
    static double bufUp[MAX_B], bufDn[MAX_B], bufMid[MAX_B];

    for (int i = 0; i < count; ++i) {
        bufUp[i] = bufDn[i] = bufMid[i] = NAN;
        double sma = CalcSMA49(highs, lows, closes, count, i);
        if (sma < 0.0) continue;
        double atr = CalcATR(closes, highs, lows, count, i, period);
        if (atr == 0.0) continue;
        bufMid[i] = sma;
        bufUp[i]  = sma + atr * MULT_FACTOR;
        bufDn[i]  = sma - atr * MULT_FACTOR;
    }

    /* ── Remplissage zone entre les canaux ────────────────────────────── */
    for (int i = vs; i <= li; ++i) {
        if (i<0||i>=count||std::isnan(bufUp[i])||std::isnan(bufDn[i])) continue;
        float x    = oriX + (i - vs) * stepX;
        float yTop = oriY - (float)((bufUp[i] - vMin) * scaleY);
        float yBot = oriY - (float)((bufDn[i] - vMin) * scaleY);
        float h    = yBot - yTop;
        if (h <= 0.0f) continue;
        GpSolidFill* brF = nullptr;
        GdipCreateSolidFill(0x10808000, &brF);   /* olive très transparent */
        GdipFillRectangle(g, (GpBrush*)brF, x, yTop, stepX, h);
        GdipDeleteBrush(brF);
    }

    /* ── Courbes ──────────────────────────────────────────────────────── */
    /* Canal haut/bas : olive (0xFF808000) */
    GpPen* pChan = nullptr;
    GdipCreatePen1(0xFF808000, 1.5f, UnitPixel, &pChan);
    DrawCurve(g, pChan, bufUp,  count, vs, li, oriX, oriY, stepX, vMin, scaleY);
    DrawCurve(g, pChan, bufDn,  count, vs, li, oriX, oriY, stepX, vMin, scaleY);
    GdipDeletePen(pChan);

    /* SMA49 centrale : olive plus clair en tirets */
    GpPen* pMid = nullptr;
    GdipCreatePen1(0xFFAAA000, 1.0f, UnitPixel, &pMid);
    GdipSetPenDashStyle(pMid, (GpDashStyle)1);
    DrawCurve(g, pMid, bufMid, count, vs, li, oriX, oriY, stepX, vMin, scaleY);
    GdipDeletePen(pMid);

    /* ── Label + bouton X ────────────────────────────────────────────── */
    char lbl[32];
    std::snprintf(lbl, sizeof(lbl), "ATRChan(%d)", period);
    int lblX = (int)oriX + 4;
    int lblY = 28 + 14 + panelIndex * (closeBtnSz + 4);
    SetBkMode(hDC, TRANSPARENT);
    SetTextColor(hDC, 0x007070);
    TextOutA(hDC, lblX, lblY, lbl, (int)std::strlen(lbl));
    SetTextColor(hDC, 0);
    float btnX = (float)(lblX + (int)std::strlen(lbl) * 7 + 3);
    DrawCloseBtn(g, btnX, (float)(lblY - 1), (float)closeBtnSz);
}

/* ── Enregistrement ───────────────────────────────────────────────────── */
//QCHART_REGISTER: Register_ATRChannel
extern "C" void Register_ATRChannel(IndicatorRegistry* reg) {
    if (reg->count >= MAX_INDICATORS) return;
    IndicatorDef* d = &reg->defs[reg->count++];
    std::strncpy(d->name,        "ATR Channel",  sizeof(d->name)-1);
    std::strncpy(d->labelPrefix, "ATRChan",      sizeof(d->labelPrefix)-1);
    d->defaultPeriod = 18;
    d->defaultParam2 = 0;
    d->isPanel       = 0;
    d->drawOverlay   = ATRChan_DrawOverlay;
    d->drawPanel     = nullptr;
}
