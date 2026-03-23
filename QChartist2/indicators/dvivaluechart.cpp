/*
 * indicators/dvivaluechart.cpp
 * DVI Value Chart — indicateur panel séparé.
 *
 * Algorithme (fidèle à DVI_valuechart.cpp porté pour QChartist) :
 *   Pour chaque barre i :
 *     midpoint = moyenne des (H+L)/2 sur 5 barres [i..i+4]
 *     dvu      = moyenne de vol*(H-L) sur 5 barres, multipliée par 0.02
 *     dv       = vol[i] * (close[i] - midpoint) / midpoint / dvu
 *     buffer[i] = buffer[i+1] + dv   (cumulatif)
 *
 * Note sur les index : dans QChart Pro, l'index 0 = barre la plus ancienne.
 * L'algo original itère de limit→0 avec i+1 = barre précédente (plus ancienne).
 * On adapte : on itère de la plus ancienne à la plus récente, donc
 * i-1 correspond à l'ancien i+1.
 *
 * Le paramètre "period" est ignoré (le lookback est fixé à 5 barres).
 * outVMin/outVMax sont calculés dynamiquement sur les barres visibles.
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

static const int LOOKBACK = 5;   /* fenêtre de calcul midpoint / dvu */
static const int MAX_B    = 4096;

/* ── Calcul du buffer DVI Value Chart ────────────────────────────────── */
/*
 * Remplit buf[0..count-1].
 * buf[i] = NaN si pas assez de données (i < LOOKBACK).
 * On itère du plus ancien (0) au plus récent (count-1).
 * Pour reproduire "buffer[i] = buffer[i+1] + dv" de l'original
 * (où i+1 = barre plus ancienne), on écrit buffer[i] = buffer[i-1] + dv.
 */
static void CalcDVI(
    const double* closes, const double* highs,
    const double* lows,   const double* volumes,
    int count, double* buf)
{
    for (int i = 0; i < count; ++i) buf[i] = NAN;

    double cumul = 0.0;

    for (int i = LOOKBACK; i < count; ++i) {
        /* Midpoint = moyenne des (H+L)/2 sur les LOOKBACK barres précédentes */
        double midpoint = 0.0;
        for (int k = 0; k < LOOKBACK; ++k)
            midpoint += (highs[i - k] + lows[i - k]) * 0.5;
        midpoint /= LOOKBACK;

        /* dvu = moyenne de vol*(H-L) sur LOOKBACK barres, * 0.02 */
        double dvu = 0.0;
        for (int k = 0; k < LOOKBACK; ++k)
            dvu += volumes[i - k] * (highs[i - k] - lows[i - k]);
        dvu = (dvu / LOOKBACK) * 0.02;

        double dv = 0.0;
        if (dvu > 0.0 && midpoint > 0.0)
            dv = volumes[i] * (closes[i] - midpoint) / midpoint / dvu;

        cumul += dv;
        buf[i] = cumul;
    }
}

/* ── Helper bouton X ──────────────────────────────────────────────────── */
static void DrawCloseBtn(GpGraphics* g, float bx, float by, float bsz)
{
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
    int             /*period*/,
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
    if (count > MAX_B || count < LOOKBACK + 1) return;

    float oriX       = ctx->oriX;
    float stepX      = ctx->stepX;
    float lenX       = ctx->lenX;
    int   mainChartH = ctx->mainChartH;
    int   panelInnerH = panelH - 20;
    int   rTop    = mainChartH + panelIndex * (panelH + panelGap);
    int   rBottom = rTop + panelInnerH;
    int   vs      = ctx->viewStart;
    int   li      = ctx->lastIdx;

    /* ── Calcul du buffer sur toute la série ─────────────────────────── */
    static double buf[MAX_B];
    CalcDVI(closes, highs, lows, volumes, count, buf);

    /* ── Échelle dynamique sur les barres visibles ───────────────────── */
    double vMin =  1e30, vMax = -1e30;
    for (int i = vs; i <= li; ++i) {
        if (i < 0 || i >= count || std::isnan(buf[i])) continue;
        if (buf[i] < vMin) vMin = buf[i];
        if (buf[i] > vMax) vMax = buf[i];
    }
    if (vMin == 1e30) { vMin = -1.0; vMax = 1.0; }
    double range = vMax - vMin;
    if (range < 1e-10) range = 1.0;
    vMin -= range * 0.10;
    vMax += range * 0.10;

    if (outVMin) *outVMin = vMin;
    if (outVMax) *outVMax = vMax;

    /* ── Cadre ────────────────────────────────────────────────────────── */
    GpPen* pG = nullptr;
    GdipCreatePen1(0xFFCCCCCC, 1.0f, UnitPixel, &pG);
    GdipDrawRectangleI(g, pG, (int)oriX, rTop, (int)lenX, panelInnerH);

    /* Ligne zéro */
    if (vMin < 0.0 && vMax > 0.0) {
        float yZero = (float)rBottom
            - (float)((0.0 - vMin) / (vMax - vMin)) * panelInnerH;
        GdipDrawLine(g, pG, oriX, yZero, oriX + lenX, yZero);
        TextOutA(hDC, (int)oriX - 14, (int)yZero - 7, "0", 1);
    }
    GdipDeletePen(pG);

    /* ── Histogramme (barres colorées selon positif/négatif) ────────── */
    float yZeroF = (float)rBottom
        - (float)((0.0 - vMin) / (vMax - vMin)) * panelInnerH;
    /* Clamp yZeroF dans le panel */
    if (yZeroF < (float)rTop)    yZeroF = (float)rTop;
    if (yZeroF > (float)rBottom) yZeroF = (float)rBottom;

    for (int i = vs; i <= li; ++i) {
        if (i < 0 || i >= count || std::isnan(buf[i])) continue;
        float x = oriX + (i - vs) * stepX;
        float bw = stepX > 2.0f ? stepX - 1.0f : stepX;
        float y  = (float)rBottom
            - (float)((buf[i] - vMin) / (vMax - vMin)) * panelInnerH;

        float top, bot;
        if (buf[i] >= 0.0) { top = y;      bot = yZeroF; }
        else               { top = yZeroF; bot = y;      }

        float h = bot - top;
        if (h < 0.5f) h = 0.5f;

        unsigned int col = (buf[i] >= 0.0) ? 0xFF00AA44 : 0xFFCC2200;
        GpSolidFill* brH = nullptr;
        GdipCreateSolidFill(col, &brH);
        GdipFillRectangle(g, (GpBrush*)brH, x, top, bw, h);
        GdipDeleteBrush(brH);
    }

    /* ── Courbe de valeur par-dessus ─────────────────────────────────── */
    GpPen* pC = nullptr;
    GdipCreatePen1(0xFF0055CC, 1.5f, UnitPixel, &pC);
    float ox = 0.0f, oy = 0.0f;
    bool  fst = true;
    for (int i = vs; i <= li; ++i) {
        if (i < 0 || i >= count || std::isnan(buf[i])) { fst = true; continue; }
        float x = oriX + (i - vs) * stepX + stepX * 0.5f;
        float y = (float)rBottom
            - (float)((buf[i] - vMin) / (vMax - vMin)) * panelInnerH;
        if (!fst) GdipDrawLine(g, pC, ox, oy, x, y);
        ox = x; oy = y; fst = false;
    }
    GdipDeletePen(pC);

    /* ── Label + bouton X ────────────────────────────────────────────── */
    char lbl[48];
    if (panelCount > 1)
        std::snprintf(lbl, sizeof(lbl), "DVI #%d", panelIndex + 1);
    else
        std::snprintf(lbl, sizeof(lbl), "DVI Value Chart");
    TextOutA(hDC, (int)oriX - 55, rTop + 2, lbl, (int)std::strlen(lbl));

    float bxBtn = oriX + lenX - (float)closeBtnSz - 2.0f;
    DrawCloseBtn(g, bxBtn, (float)rTop + 2.0f, (float)closeBtnSz);
}

/* ── Enregistrement ───────────────────────────────────────────────────── */
//QCHART_REGISTER: Register_DVIValueChart
extern "C" void Register_DVIValueChart(IndicatorRegistry* reg) {
    if (reg->count >= MAX_INDICATORS) return;
    IndicatorDef* d = &reg->defs[reg->count++];
    std::strncpy(d->name,        "DVI Value Chart", sizeof(d->name)-1);
    std::strncpy(d->labelPrefix, "DVI",             sizeof(d->labelPrefix)-1);
    d->defaultPeriod = 5;
    d->isPanel       = 1;
    d->drawOverlay   = nullptr;
    d->drawPanel     = DVI_DrawPanel;
}
