/*
 * indicators/rsi.cpp
 * RSI (Relative Strength Index) — indicateur panel séparé.
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

static double CalcRSI(const double* closes, int count, int i, int period) {
    if (i < period || i >= count) return -1.0;
    double up = 0.0, dw = 0.0;
    for (int j = i - period + 1; j <= i; ++j) {
        double d = closes[j] - closes[j-1];
        if (d > 0.0) up += d; else dw -= d;
    }
    double avgUp  = up / period;
    double avgDwn = (dw == 0.0 ? 0.001 : dw) / period;
    return 100.0 - (100.0 / (1.0 + avgUp / avgDwn));
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

/* ── Callback DrawPanel ───────────────────────────────────────────────── */

static void RSI_DrawPanel(
    GpGraphics*  g,
    HDC          hDC,
    const double* closes,
    const double*   opens,
    const double* highs,
    const double* lows,
    const double*   volumes,
    const int*      weekdays,
    int           count,
    int           period,
    int             param2,
    int           panelIndex,
    int           panelCount,
    const ChartCtx* ctx,
    int           panelH,
    int           panelGap,
    int           closeBtnSz,
    double*       outVMin,
    double*       outVMax)
{
    /* RSI est toujours dans [0, 100] */
    if (outVMin) *outVMin = 0.0;
    if (outVMax) *outVMax = 100.0;
    float oriX  = ctx->oriX;
    float stepX = ctx->stepX;
    float lenX  = ctx->lenX;
    int   mainChartH = ctx->mainChartH;
    int   panelInnerH = panelH - 20;
    /* mainChartH reçu inclut déjà RSI_PANEL_MARGIN (ajouté côté FreeBASIC dans ctx.mainChartH).
       Le panel à panelIndex=0 commence donc directement à mainChartH + panelIndex*(panelH+panelGap). */
    int   rTop    = mainChartH + panelIndex * (panelH + panelGap);
    int   rBottom = rTop + panelInnerH;

    /* Cadre + niveaux 30/70 */
    GpPen* pG = nullptr;
    GdipCreatePen1(0xFFCCCCCC, 1.0f, UnitPixel, &pG);
    GdipDrawRectangleI(g, pG, (int)oriX, rTop, (int)lenX, panelInnerH);
    float y70 = rTop + panelInnerH * 0.30f;
    float y30 = rTop + panelInnerH * 0.70f;
    GdipDrawLine(g, pG, oriX, y70, oriX+lenX, y70);
    GdipDrawLine(g, pG, oriX, y30, oriX+lenX, y30);
    GdipDeletePen(pG);

    /* Courbe RSI */
    GpPen* pR = nullptr;
    GdipCreatePen1(0xFF0000FF, 1.5f, UnitPixel, &pR);
    float ox = 0, oy = 0; bool fst = true;
    for (int i = ctx->viewStart; i <= ctx->lastIdx; ++i) {
        double rv = CalcRSI(closes, count, i, period);
        if (rv >= 0.0) {
            float x = oriX + (i - ctx->viewStart) * stepX + stepX * 0.5f;
            float y = (float)rBottom - (float)(rv / 100.0) * panelInnerH;
            if (!fst) GdipDrawLine(g, pR, ox, oy, x, y);
            ox = x; oy = y; fst = false;
        }
    }
    GdipDeletePen(pR);

    /* Labels */
    char lbl[32];
    if (panelCount > 1) std::snprintf(lbl, sizeof(lbl), "RSI(%d) #%d", period, panelIndex+1);
    else                std::snprintf(lbl, sizeof(lbl), "RSI(%d)", period);
    TextOutA(hDC, (int)oriX-55, rTop+2, lbl, (int)std::strlen(lbl));
    TextOutA(hDC, (int)oriX-22, (int)y70-7, "70", 2);
    TextOutA(hDC, (int)oriX-22, (int)y30-7, "30", 2);

    /* Bouton X */
    float bx = oriX + lenX - (float)closeBtnSz - 2.0f;
    DrawCloseBtn(g, bx, (float)rTop+2.0f, (float)closeBtnSz);
}

/* ── Enregistrement ───────────────────────────────────────────────────── */
//QCHART_REGISTER: Register_RSI
extern "C" void Register_RSI(IndicatorRegistry* reg) {
    if (reg->count >= MAX_INDICATORS) return;
    IndicatorDef* d = &reg->defs[reg->count++];
    std::strncpy(d->name,        "RSI",  sizeof(d->name)-1);
    std::strncpy(d->labelPrefix, "RSI",  sizeof(d->labelPrefix)-1);
    d->defaultPeriod = 21;
    d->isPanel       = 1;
    d->drawOverlay   = nullptr;
    d->drawPanel     = RSI_DrawPanel;
}
