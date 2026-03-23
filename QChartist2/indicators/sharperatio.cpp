/*
 * indicators/sharperatio.cpp
 * Sharpe Ratio annualisé — indicateur panel séparé.
 *
 * Algorithme :
 *   Pour chaque barre i, on calcule sur une fenêtre glissante de `period` barres :
 *     - Rendements journaliers :  r[j] = (close[i-j] - close[i-j-1]) / close[i-j-1]
 *     - Moyenne des rendements :  mean = sum(r) / period
 *     - Écart-type annualisé  :   stdDev = sqrt(variance) * sqrt(period)
 *     - Sharpe annualisé      :   SR = (mean * 365 - RiskFreeRate) / stdDev
 *
 * Le paramètre "period" configure la fenêtre glissante (défaut : 180).
 * RiskFreeRate est fixé à 4 % (0.04) — valeur standard.
 *
 * outVMin / outVMax sont calculés dynamiquement sur les barres visibles
 * pour que les trendlines soient précises quelle que soit l'amplitude.
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

static const double RISK_FREE_RATE = 0.04;   /* taux sans risque annualisé */
static const int    MAX_BARS       = 4096;    /* taille max du tableau sur la pile */

/* ── Calcul du Sharpe Ratio ───────────────────────────────────────────── */

/*
 * CalcSharpe — retourne le Sharpe Ratio annualisé à la barre i.
 * Retourne NaN si pas assez de données (i < period + 1).
 */
static double CalcSharpe(const double* closes, int count, int i, int period)
{
    if (i < period + 1 || i >= count) return NAN;

    /* Calcul de la moyenne des rendements en un seul passage */
    double sum = 0.0;
    for (int j = 0; j < period; ++j) {
        int idx = i - j;
        if (idx < 1 || idx >= count) return NAN;
        sum += (closes[idx] - closes[idx - 1]) / closes[idx - 1];
    }
    double mean = sum / period;

    /* Variance (deuxième passage — pas de tableau nécessaire) */
    double variance = 0.0;
    for (int j = 0; j < period; ++j) {
        int idx = i - j;
        double r = (closes[idx] - closes[idx - 1]) / closes[idx - 1];
        variance += (r - mean) * (r - mean);
    }

    double stdDev = std::sqrt(variance / period) * std::sqrt((double)period);
    if (stdDev == 0.0) return NAN;

    return (mean * 365.0 - RISK_FREE_RATE) / stdDev;
}

/* ── Helpers UI ───────────────────────────────────────────────────────── */

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

static void Sharpe_DrawPanel(
    GpGraphics*     g,
    HDC             hDC,
    const double*   closes,
    const double*   opens,
    const double*   highs,
    const double*   lows,
    const double*   volumes,
    const int*      weekdays,
    int             count,
    int             period,
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
    float oriX       = ctx->oriX;
    float stepX      = ctx->stepX;
    float lenX       = ctx->lenX;
    int   mainChartH = ctx->mainChartH;
    int   panelInnerH = panelH - 20;
    int   rTop    = mainChartH + panelIndex * (panelH + panelGap);
    int   rBottom = rTop + panelInnerH;

    /* ── Précalcul des valeurs visibles pour l'échelle dynamique ──────── */
    double vMin =  1e30;
    double vMax = -1e30;
    for (int i = ctx->viewStart; i <= ctx->lastIdx; ++i) {
        double sr = CalcSharpe(closes, count, i, period);
        if (!std::isnan(sr)) {
            if (sr < vMin) vMin = sr;
            if (sr > vMax) vMax = sr;
        }
    }
    /* Marges de 10 % + garantie que 0 est visible */
    if (vMin == 1e30) { vMin = -1.0; vMax = 1.0; }
    double range = vMax - vMin;
    if (range < 0.01) range = 0.01;
    vMin -= range * 0.10;
    vMax += range * 0.10;

    /* Transmettre l'espace de valeurs au caller (pour trendlines / crosshair) */
    if (outVMin) *outVMin = vMin;
    if (outVMax) *outVMax = vMax;

    /* ── Cadre ────────────────────────────────────────────────────────── */
    GpPen* pG = nullptr;
    GdipCreatePen1(0xFFCCCCCC, 1.0f, UnitPixel, &pG);
    GdipDrawRectangleI(g, pG, (int)oriX, rTop, (int)lenX, panelInnerH);

    /* Ligne zéro */
    if (vMin < 0.0 && vMax > 0.0) {
        float yZero = (float)rBottom - (float)((0.0 - vMin) / (vMax - vMin)) * panelInnerH;
        GdipDrawLine(g, pG, oriX, yZero, oriX + lenX, yZero);
        /* Label "0" */
        TextOutA(hDC, (int)oriX - 14, (int)yZero - 7, "0", 1);
    }
    GdipDeletePen(pG);

    /* Niveaux de référence colorés : OverValued (vert), UnderValued (rouge) */
    auto DrawLevel = [&](double level, unsigned int color, const char* lbl) {
        if (level < vMin || level > vMax) return;
        float yLv = (float)rBottom - (float)((level - vMin) / (vMax - vMin)) * panelInnerH;
        GpPen* pLv = nullptr;
        GdipCreatePen1(color, 1.0f, UnitPixel, &pLv);
        GdipSetPenDashStyle(pLv, (GpDashStyle)3);   /* DashDot */
        GdipDrawLine(g, pLv, oriX, yLv, oriX + lenX, yLv);
        GdipDeletePen(pLv);
        TextOutA(hDC, (int)oriX - 22, (int)yLv - 7, lbl, (int)std::strlen(lbl));
    };
    DrawLevel( 5.0, 0xFF008800, " 5");   /* surévalué    */
    DrawLevel(-1.0, 0xFFCC4400, "-1");   /* sous-évalué  */
    DrawLevel(-3.0, 0xFFCC0000, "-3");   /* critique     */

    /* ── Courbe Sharpe ────────────────────────────────────────────────── */
    GpPen* pS = nullptr;
    GdipCreatePen1(0xFF8800CC, 1.5f, UnitPixel, &pS);   /* violet */
    float ox = 0.0f, oy = 0.0f;
    bool  fst = true;
    for (int i = ctx->viewStart; i <= ctx->lastIdx; ++i) {
        double sr = CalcSharpe(closes, count, i, period);
        if (!std::isnan(sr)) {
            float x = oriX + (i - ctx->viewStart) * stepX + stepX * 0.5f;
            float y = (float)rBottom - (float)((sr - vMin) / (vMax - vMin)) * panelInnerH;
            if (!fst) GdipDrawLine(g, pS, ox, oy, x, y);
            ox = x; oy = y; fst = false;
        } else {
            fst = true;   /* trou de données : lever le crayon */
        }
    }
    GdipDeletePen(pS);

    /* ── Labels ───────────────────────────────────────────────────────── */
    char lbl[48];
    if (panelCount > 1)
        std::snprintf(lbl, sizeof(lbl), "Sharpe(%d) #%d", period, panelIndex + 1);
    else
        std::snprintf(lbl, sizeof(lbl), "Sharpe(%d)", period);
    TextOutA(hDC, (int)oriX - 55, rTop + 2, lbl, (int)std::strlen(lbl));

    /* ── Bouton X ─────────────────────────────────────────────────────── */
    float bx = oriX + lenX - (float)closeBtnSz - 2.0f;
    DrawCloseBtn(g, bx, (float)rTop + 2.0f, (float)closeBtnSz);
}

/* ── Enregistrement ───────────────────────────────────────────────────── */
//QCHART_REGISTER: Register_SharpeRatio
extern "C" void Register_SharpeRatio(IndicatorRegistry* reg) {
    if (reg->count >= MAX_INDICATORS) return;
    IndicatorDef* d = &reg->defs[reg->count++];
    std::strncpy(d->name,        "Sharpe Ratio", sizeof(d->name)-1);
    std::strncpy(d->labelPrefix, "Sharpe",       sizeof(d->labelPrefix)-1);
    d->defaultPeriod = 180;
    d->isPanel       = 1;
    d->drawOverlay   = nullptr;
    d->drawPanel     = Sharpe_DrawPanel;
}
