/*
 * indicators/bollingerbands.cpp
 * Bollinger Bands — indicateur overlay (3 courbes sur les bougies).
 *
 * Les Bandes de Bollinger se composent de :
 *   - Bande médiane  : SMA(period)
 *   - Bande haute    : SMA + stdDev * multiplier
 *   - Bande basse    : SMA - stdDev * multiplier
 *
 * Le paramètre "period" configure la fenêtre de calcul (défaut : 20).
 * Le multiplicateur est fixé à 2.0 (valeur standard).
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

static const double BB_MULTIPLIER = 2.0;

/* ── Calculs ──────────────────────────────────────────────────────────── */

/* Moyenne simple sur [i-period+1 .. i]. Retourne -1 si pas assez de données. */
static double BB_SMA(const double* closes, int count, int i, int period) {
    if (i < period - 1 || i >= count) return -1.0;
    double sum = 0.0;
    for (int k = 0; k < period; ++k) sum += closes[i - k];
    return sum / period;
}

/* Écart-type de population sur la même fenêtre. Retourne -1 si pas assez. */
static double BB_StdDev(const double* closes, int count, int i, int period, double mean) {
    if (i < period - 1 || i >= count || mean < 0.0) return -1.0;
    double variance = 0.0;
    for (int k = 0; k < period; ++k) {
        double diff = closes[i - k] - mean;
        variance += diff * diff;
    }
    return std::sqrt(variance / period);
}

/* ── Helper bouton ✕ ──────────────────────────────────────────────────── */

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

/* ── Dessin d'une courbe unique ───────────────────────────────────────── */

static void DrawCurve(GpGraphics* g, GpPen* pen,
                      const double* vals, int vcount,
                      int viewStart, int lastIdx,
                      float oriX, float oriY, float stepX,
                      double vMin, double scaleY)
{
    float ox = 0, oy = 0; bool first = true;
    for (int i = viewStart; i <= lastIdx; ++i) {
        if (i < 0 || i >= vcount) continue;
        double v = vals[i];
        if (v < 0.0) { first = true; continue; }   /* trou : lever le crayon */
        float x = oriX + (i - viewStart) * stepX + stepX * 0.5f;
        float y = oriY - (float)((v - vMin) * scaleY);
        if (!first) GdipDrawLine(g, pen, ox, oy, x, y);
        ox = x; oy = y; first = false;
    }
}

/* ── Callback DrawOverlay ─────────────────────────────────────────────── */

static void BB_DrawOverlay(
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
    int    vs     = ctx->viewStart;
    int    li     = ctx->lastIdx;

    if (count < period) return;

    /* Tableaux sur la pile — taille max 4096 barres.
       new[]/delete[] ne sont pas disponibles sans libstdc++. */
    const int MAX_BARS = 4096;
    if (count > MAX_BARS) return;
    double mid[MAX_BARS], high[MAX_BARS], low[MAX_BARS];
    for (int i = 0; i < count; ++i) {
        double sma = BB_SMA(closes, count, i, period);
        double sd  = BB_StdDev(closes, count, i, period, sma);
        mid[i]  = sma;
        high[i] = (sma >= 0.0 && sd >= 0.0) ? sma + BB_MULTIPLIER * sd : -1.0;
        low[i]  = (sma >= 0.0 && sd >= 0.0) ? sma - BB_MULTIPLIER * sd : -1.0;
    }

    /* Couleur de base tirée de la palette (même logique que MA) */
    unsigned int baseCol = colors[panelIndex % 8];

    /* Bande médiane : couleur de base, trait plein */
    GpPen* penMid = nullptr;
    GdipCreatePen1(baseCol, 1.2f, UnitPixel, &penMid);
    DrawCurve(g, penMid, mid, count, vs, li, oriX, oriY, stepX, vMin, scaleY);
    GdipDeletePen(penMid);

    /* Bandes haute et basse : même couleur mais plus transparent, tirets */
    unsigned int bandCol = (baseCol & 0x00FFFFFF) | 0xAA000000;  /* alpha 170/255 */
    GpPen* penBand = nullptr;
    GdipCreatePen1(bandCol, 1.0f, UnitPixel, &penBand);
    DrawCurve(g, penBand, high, count, vs, li, oriX, oriY, stepX, vMin, scaleY);
    DrawCurve(g, penBand, low,  count, vs, li, oriX, oriY, stepX, vMin, scaleY);
    GdipDeletePen(penBand);

    /* Zone de remplissage semi-transparente entre les bandes haute et basse */
    unsigned int fillCol = (baseCol & 0x00FFFFFF) | 0x18000000;  /* alpha 24/255 */
    for (int i = vs; i <= li; ++i) {
        if (i < 0 || i >= count) continue;
        if (high[i] < 0.0 || low[i] < 0.0) continue;
        float x    = oriX + (i - vs) * stepX;
        float yTop = oriY - (float)((high[i] - vMin) * scaleY);
        float yBot = oriY - (float)((low[i]  - vMin) * scaleY);
        float h    = yBot - yTop;
        if (h <= 0.0f) continue;
        GpSolidFill* brFill = nullptr;
        GdipCreateSolidFill(fillCol, &brFill);
        GdipFillRectangle(g, (GpBrush*)brFill, x, yTop, stepX, h);
        GdipDeleteBrush((GpBrush*)brFill);
    }

    /* Label + bouton ✕ */
    char lbl[32];
    std::snprintf(lbl, sizeof(lbl), "BB(%d)", period);
    int lblX = (int)oriX + 4;
    int lblY = 42 + panelIndex * (closeBtnSz + 4);

    unsigned int rC = (baseCol >> 16) & 0xFF;
    unsigned int gC = (baseCol >>  8) & 0xFF;
    unsigned int bC =  baseCol        & 0xFF;
    COLORREF cr = (COLORREF)((bC << 16) | (gC << 8) | rC);
    SetBkMode(hDC, TRANSPARENT);
    SetTextColor(hDC, cr);
    TextOutA(hDC, lblX, lblY, lbl, (int)std::strlen(lbl));
    SetTextColor(hDC, 0);
    float btnX = (float)(lblX + (int)std::strlen(lbl) * 7 + 3);
    DrawCloseBtn(g, btnX, (float)(lblY - 1), (float)closeBtnSz);
}

/* ── Enregistrement ───────────────────────────────────────────────────── */
//QCHART_REGISTER: Register_BollingerBands
extern "C" void Register_BollingerBands(IndicatorRegistry* reg) {
    if (reg->count >= MAX_INDICATORS) return;
    IndicatorDef* d = &reg->defs[reg->count++];
    std::strncpy(d->name,        "Bollinger Bands", sizeof(d->name)-1);
    std::strncpy(d->labelPrefix, "BB",              sizeof(d->labelPrefix)-1);
    d->defaultPeriod = 20;
    d->isPanel       = 0;
    d->drawOverlay   = BB_DrawOverlay;
    d->drawPanel     = nullptr;
}
