/*
 * indicators/anchoredvwap.cpp
 * Anchored VWAP — indicateur overlay avec bandes de déviation standard.
 *
 * Le VWAP ancré est calculé depuis une barre d'ancrage (définie par "period"
 * = nombre de barres depuis la fin de l'historique) jusqu'à la barre courante.
 *
 * Pour chaque barre i dans [0..anchorBar-1] (sens de l'algo original : barres
 * récentes = index bas) :
 *   WP[i]    = volume[i] * (high[i] + low[i] + close[i]) / 3
 *   VWAP[i]  = SUM(WP[i..anchor]) / SUM(volume[i..anchor])
 *   StdDev   = sqrt( SUM((WP[j]/vol[j] - VWAP[i])^2) / N )
 *   Upper[i] = VWAP[i] + devBand * StdDev
 *   Lower[i] = VWAP[i] - devBand * StdDev
 *
 * Note sur les index : dans QChart Pro, l'index 0 = barre la plus ancienne,
 * index count-1 = barre la plus récente. L'algo original utilise la convention
 * inverse (0 = récent). On adapte en utilisant anchorBar = count - 1 - period.
 *
 * Le paramètre "period" = nombre de barres depuis la fin à partir desquelles
 * on ancre le VWAP (défaut : 20). devBand est fixé à 1.0 (1 sigma).
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

static const double DEV_BAND = 1.0;   /* multiplicateur sigma des bandes */

/* ── Calcul du VWAP ancré et des bandes ──────────────────────────────── */
/*
 * Calcule VWAP, UpperBand, LowerBand pour toutes les barres [anchorBar..count-1].
 * Les résultats sont stockés dans les tableaux out* (déjà alloués, taille count).
 * Les barres avant anchorBar reçoivent -1 (pas de valeur).
 */
static void CalcAnchoredVWAP(
    const double* closes, const double* highs,
    const double* lows,   const double* volumes,
    int count, int anchorBar, double devBand,
    double* outVWAP, double* outUpper, double* outLower)
{
    /* Initialiser tout à -1 */
    for (int i = 0; i < count; ++i)
        outVWAP[i] = outUpper[i] = outLower[i] = -1.0;

    if (anchorBar < 0 || anchorBar >= count) return;

    /* Pré-calcul des weighted prices WP[i] = vol[i] * (H+L+C)/3 */
    /* On travaille sur [anchorBar..count-1] */
    int n = count - anchorBar;   /* nombre de barres depuis l'ancre */
    if (n <= 0) return;

    /* Calcul cumulatif depuis anchorBar */
    double cumWP  = 0.0;
    double cumVol = 0.0;

    for (int i = anchorBar; i < count; ++i) {
        double wp = volumes[i] * (highs[i] + lows[i] + closes[i]) / 3.0;
        cumWP  += wp;
        cumVol += volumes[i];

        double vwap = (cumVol > 0.0) ? cumWP / cumVol : closes[i];
        outVWAP[i] = vwap;
    }

    /* Deuxième passe : écart-type depuis anchorBar jusqu'à i */
    double cumSqDev = 0.0;
    double cumV2    = 0.0;
    int    cnt      = 0;

    for (int i = anchorBar; i < count; ++i) {
        double wp = volumes[i] * (highs[i] + lows[i] + closes[i]) / 3.0;
        cumV2 += volumes[i];
        /* contribution au stddev : (typical_price - VWAP_i)^2 */
        double tp = (highs[i] + lows[i] + closes[i]) / 3.0;
        cumSqDev += (tp - outVWAP[i]) * (tp - outVWAP[i]);
        cnt++;

        double stddev = (cnt > 0) ? std::sqrt(cumSqDev / cnt) : 0.0;
        outUpper[i] = outVWAP[i] + devBand * stddev;
        outLower[i] = outVWAP[i] - devBand * stddev;
    }
}

/* ── Helper dessin d'une courbe ──────────────────────────────────────── */
static void DrawCurveFromBuffer(
    GpGraphics* g, GpPen* pen,
    const double* vals, int count,
    int viewStart, int lastIdx,
    float oriX, float oriY, float stepX,
    double vMin, double scaleY)
{
    float ox = 0.0f, oy = 0.0f;
    bool  fst = true;
    for (int i = viewStart; i <= lastIdx; ++i) {
        if (i < 0 || i >= count || vals[i] < 0.0) { fst = true; continue; }
        float x = oriX + (i - viewStart) * stepX + stepX * 0.5f;
        float y = oriY - (float)((vals[i] - vMin) * scaleY);
        if (!fst) GdipDrawLine(g, pen, ox, oy, x, y);
        ox = x; oy = y; fst = false;
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

/* ── Callback DrawOverlay ─────────────────────────────────────────────── */

static void AVWAP_DrawOverlay(
    GpGraphics*         g,
    HDC                 hDC,
    const double*       closes,
    const double*       opens,
    const double*       highs,
    const double*       lows,
    const double*       volumes,
    const int*      weekdays,
    int                 count,
    int                 period,       /* = barres depuis la fin jusqu'à l'ancre */
    int                 param2,
    int                 panelIndex,
    const ChartCtx*     ctx,
    int                 closeBtnSz,
    const unsigned int* /*colors*/)
{
    if (count < 2) return;

    float  oriX   = ctx->oriX;
    float  oriY   = ctx->oriY;
    float  stepX  = ctx->stepX;
    double vMin   = ctx->vMin;
    double scaleY = ctx->scaleY;
    int    vs     = ctx->viewStart;
    int    li     = ctx->lastIdx;

    /* Barre d'ancrage : period barres avant la fin */
    int anchorBar = count - 1 - period;
    if (anchorBar < 0) anchorBar = 0;

    /* Tableaux de résultats sur la pile — MAX_BARS limité */
    static const int MAX_B = 4096;
    if (count > MAX_B) return;

    static double vwap [MAX_B];
    static double upper[MAX_B];
    static double lower[MAX_B];

    CalcAnchoredVWAP(closes, highs, lows, volumes,
                     count, anchorBar, DEV_BAND,
                     vwap, upper, lower);

    /* ── Dessin zone remplie entre les bandes ────────────────────────── */
    unsigned int fillCol = 0x1500AA00;   /* vert très transparent */
    for (int i = vs; i <= li; ++i) {
        if (i < 0 || i >= count) continue;
        if (upper[i] < 0.0 || lower[i] < 0.0) continue;
        float x    = oriX + (i - vs) * stepX;
        float yTop = oriY - (float)((upper[i] - vMin) * scaleY);
        float yBot = oriY - (float)((lower[i] - vMin) * scaleY);
        float h    = yBot - yTop;
        if (h <= 0.0f) continue;
        GpSolidFill* brF = nullptr;
        GdipCreateSolidFill(fillCol, &brF);
        GdipFillRectangle(g, (GpBrush*)brF, x, yTop, stepX, h);
        GdipDeleteBrush(brF);
    }

    /* ── Bandes de déviation (rouge pointillé) ───────────────────────── */
    GpPen* pBand = nullptr;
    GdipCreatePen1(0xFFCC0000, 1.2f, UnitPixel, &pBand);
    GdipSetPenDashStyle(pBand, (GpDashStyle)1);   /* DashStyleDash */
    DrawCurveFromBuffer(g, pBand, upper, count, vs, li, oriX, oriY, stepX, vMin, scaleY);
    DrawCurveFromBuffer(g, pBand, lower, count, vs, li, oriX, oriY, stepX, vMin, scaleY);
    GdipDeletePen(pBand);

    /* ── Ligne VWAP centrale (vert plein) ────────────────────────────── */
    GpPen* pVWAP = nullptr;
    GdipCreatePen1(0xFF00AA00, 2.0f, UnitPixel, &pVWAP);
    DrawCurveFromBuffer(g, pVWAP, vwap, count, vs, li, oriX, oriY, stepX, vMin, scaleY);
    GdipDeletePen(pVWAP);

    /* ── Ligne verticale d'ancrage ───────────────────────────────────── */
    if (anchorBar >= vs && anchorBar <= li) {
        float xAnchor = oriX + (anchorBar - vs) * stepX + stepX * 0.5f;
        GpPen* pAnc = nullptr;
        GdipCreatePen1(0xFF888800, 1.0f, UnitPixel, &pAnc);
        GdipSetPenDashStyle(pAnc, (GpDashStyle)2);   /* DashStyleDot */
        GdipDrawLine(g, pAnc, xAnchor, (float)(ctx->oriY - (ctx->oriY - 40) * 0.95f),
                     xAnchor, oriY);
        GdipDeletePen(pAnc);
        /* Label "Anchor" */
        SetBkMode(hDC, TRANSPARENT);
        SetTextColor(hDC, 0x007777);
        TextOutA(hDC, (int)xAnchor + 3, 42, "Anchor", 6);
        SetTextColor(hDC, 0);
    }

    /* ── Label + bouton X ────────────────────────────────────────────── */
    char lbl[32];
    std::snprintf(lbl, sizeof(lbl), "AVWAP(%d)", period);
    int lblX = (int)oriX + 4;
    int lblY = 28 + 14 + panelIndex * (closeBtnSz + 4);

    SetBkMode(hDC, TRANSPARENT);
    SetTextColor(hDC, 0x007700);   /* vert foncé */
    TextOutA(hDC, lblX, lblY, lbl, (int)std::strlen(lbl));
    SetTextColor(hDC, 0);

    float btnX = (float)(lblX + (int)std::strlen(lbl) * 7 + 3);
    DrawCloseBtn(g, btnX, (float)(lblY - 1), (float)closeBtnSz);
}

/* ── Enregistrement ───────────────────────────────────────────────────── */
//QCHART_REGISTER: Register_AnchoredVWAP
extern "C" void Register_AnchoredVWAP(IndicatorRegistry* reg) {
    if (reg->count >= MAX_INDICATORS) return;
    IndicatorDef* d = &reg->defs[reg->count++];
    std::strncpy(d->name,        "Anchored VWAP", sizeof(d->name)-1);
    std::strncpy(d->labelPrefix, "AVWAP",         sizeof(d->labelPrefix)-1);
    d->defaultPeriod = 20;
    d->isPanel       = 0;
    d->drawOverlay   = AVWAP_DrawOverlay;
    d->drawPanel     = nullptr;
}
