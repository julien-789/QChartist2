/*
 * indicators/movingaverage.cpp
 * Simple Moving Average (SMA) — indicateur overlay.
 *
 * Compilation automatique via build.bat.
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <objbase.h>
#include <gdiplus.h>
#include <cstdio>
#include <cstring>
#include "indicator_api.h"

using namespace Gdiplus;
using namespace Gdiplus::DllExports;

/* ── Helpers ──────────────────────────────────────────────────────────── */

static double CalcSMA(const double* closes, int count, int i, int period) {
    if (i < period - 1 || i >= count) return -1.0;
    double sum = 0.0;
    for (int k = 0; k < period; ++k) sum += closes[i - k];
    return sum / period;
}

static void DrawCloseBtn(GpGraphics* g, float bx, float by, float bsz) {
    GpSolidFill* br = nullptr;
    GdipCreateSolidFill(0xFFE8E8E8, &br);
    GdipFillRectangle(g, (GpBrush*)br, bx, by, bsz, bsz);
    GdipDeleteBrush((GpBrush*)br);
    GpPen* pB = nullptr;
    GdipCreatePen1(0xFFAAAAAA, 1.0f, UnitPixel, &pB);
    GdipDrawRectangle(g, pB, bx, by, bsz, bsz);
    GdipDeletePen(pB);
    GpPen* pX = nullptr;
    GdipCreatePen1(0xFFCC0000, 1.8f, UnitPixel, &pX);
    float mg = 3.5f;
    GdipDrawLine(g, pX, bx+mg, by+mg, bx+bsz-mg, by+bsz-mg);
    GdipDrawLine(g, pX, bx+bsz-mg, by+mg, bx+mg, by+bsz-mg);
    GdipDeletePen(pX);
}

/* ── Callback DrawOverlay ─────────────────────────────────────────────── */

static void MA_DrawOverlay(
    GpGraphics*         g,
    HDC                 hDC,
    const double*       closes,
    const double*       opens,
    const double*       highs,
    const double*       lows,
    const double*   volumes,
    const int*      weekdays,
    int                 count,
    int                 period,
    int             param2,
    int                 panelIndex,
    const ChartCtx*     ctx,
    int                 closeBtnSz,
    const unsigned int* colors)
{
    float  oriX   = ctx->oriX;
    float  oriY   = ctx->oriY;
    float  stepX  = ctx->stepX;
    double vMin   = ctx->vMin;
    double scaleY = ctx->scaleY;
    /* viewStart et lastIdx sont dans ctx via les champs réservés —
       on les calcule depuis oriX/stepX/count si nécessaire.
       Ici on itère sur toutes les barres visibles : le caller garantit
       que closes[] couvre [0..count-1] et viewStart est l'origine X. */

    unsigned int maCol = colors[panelIndex % 8];

    /* Courbe SMA */
    if (count >= period) {
        GpPen* pen = nullptr;
        GdipCreatePen1(maCol, 1.5f, UnitPixel, &pen);
        float ox = 0, oy = 0; bool first = true;
        for (int i = ctx->viewStart; i <= ctx->lastIdx; ++i) {
            double v = CalcSMA(closes, count, i, period);
            if (v >= 0.0) {
                float x = oriX + (i - ctx->viewStart) * stepX + stepX * 0.5f;
                float y = oriY - (float)((v - vMin) * scaleY);
                if (!first) GdipDrawLine(g, pen, ox, oy, x, y);
                ox = x; oy = y; first = false;
            }
        }
        GdipDeletePen(pen);
    }

    /* Label + bouton X */
    char lbl[32];
    std::snprintf(lbl, sizeof(lbl), "MA(%d)", period);
    int lblX = (int)oriX + 4;
    int lblY = 28 + 14 + panelIndex * (closeBtnSz + 4);  /* 28 = ZOOM_BAR_H */

    unsigned int rC=(maCol>>16)&0xFF, gC=(maCol>>8)&0xFF, bC=maCol&0xFF;
    COLORREF cr = (COLORREF)((bC<<16)|(gC<<8)|rC);
    SetBkMode(hDC, TRANSPARENT);
    SetTextColor(hDC, cr);
    TextOutA(hDC, lblX, lblY, lbl, (int)std::strlen(lbl));
    SetTextColor(hDC, 0);
    float bx = (float)(lblX + (int)std::strlen(lbl)*7 + 3);
    DrawCloseBtn(g, bx, (float)(lblY-1), (float)closeBtnSz);
}

/* ── Enregistrement ───────────────────────────────────────────────────── */
//QCHART_REGISTER: Register_MovingAverage
extern "C" void Register_MovingAverage(IndicatorRegistry* reg) {
    if (reg->count >= MAX_INDICATORS) return;
    IndicatorDef* d = &reg->defs[reg->count++];
    std::strncpy(d->name,        "Moving Average", sizeof(d->name)-1);
    std::strncpy(d->labelPrefix, "MA",             sizeof(d->labelPrefix)-1);
    d->defaultPeriod = 20;
    d->isPanel       = 0;
    d->drawOverlay   = MA_DrawOverlay;
    d->drawPanel     = nullptr;
}
