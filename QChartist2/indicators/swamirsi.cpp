/*
 * indicators/swamirsi.cpp
 * Swami RSI — heatmap 2D (période × temps) en canvas séparé.
 *
 * Principe :
 *   Pour chaque barre visible et chaque période P dans [StartLength..EndLength],
 *   on calcule un RSI "fuzzy" via EMA(change) / EMA(|change|).
 *   Le résultat (0..1) est mappé sur une couleur (bleu→cyan→vert→jaune→rouge).
 *   La heatmap est dessinée en rectangles empilés verticalement dans le panel.
 *
 *   Le paramètre "period" configure EndLength (défaut 48).
 *   StartLength est fixé à EndLength / 4 (minimum 2).
 *   SampleLength = EndLength / 2 : trace une courbe RSI médiane en blanc.
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

/* ── Constantes ───────────────────────────────────────────────────────── */
static const int SMOOTH       = 5;      /* période de lissage EMA finale */
static const int MAX_BARS     = 4096;
static const int MAX_PERIODS  = 280;    /* EndLength max */

/* ── EMA stateless (calculée sur toute la série depuis bar=0) ─────────── */
/*
 * Pour éviter les états persistants (pas de tableau statique partagé entre
 * appels), on recalcule l'EMA depuis le début de la série à chaque appel.
 * C'est O(count) par valeur — acceptable car count est typiquement < 2000.
 */
static double ComputeEMA(const double* series, int count, int targetBar, int per)
{
    if (per < 1) per = 1;
    double ema = series[0];
    double k   = 1.0 / per;
    for (int i = 1; i <= targetBar && i < count; ++i)
        ema = ema + k * (series[i] - ema);
    return ema;
}

/* ── Calcul du RSI Swami pour une période donnée à la barre i ────────── */
/*
 * On précalcule les séries change[] et |change|[] puis on passe les EMA.
 * netChgAvg  = EMA(change,     period)
 * totChgAvg  = EMA(|change|,   period)
 * chgRatio   = netChgAvg / totChgAvg   (ou 0 si denom=0)
 * rsi        = EMA(2*chgRatio + 0.5,   SMOOTH)   clampé [0,1]
 *
 * Pour la heatmap on n'a besoin que de la valeur à la barre i,
 * donc on repart de bar=0 pour chaque période — O(count * swamisize) total.
 */
static double CalcSwamiRSI_bar(
    const double* closes, int count,
    int targetBar, int period)
{
    if (targetBar < 1 || targetBar >= count) return 0.5;

    double k  = 1.0 / period;
    double ks = 1.0 / SMOOTH;

    /* EMA du changement net et de la valeur absolue du changement */
    double netAvg = 0.0;
    double totAvg = 0.0;
    for (int i = 1; i <= targetBar && i < count; ++i) {
        double chg = closes[i] - closes[i - 1];
        netAvg = netAvg + k * (chg           - netAvg);
        totAvg = totAvg + k * (std::fabs(chg) - totAvg);
    }

    /* EMA du signal fuzzy 2*ChgRatio+0.5 */
    double signal = 0.5;
    double netA2  = 0.0, totA2 = 0.0;
    for (int i = 1; i <= targetBar && i < count; ++i) {
        double chg = closes[i] - closes[i - 1];
        netA2 = netA2 + k * (chg           - netA2);
        totA2 = totA2 + k * (std::fabs(chg) - totA2);
        double cr = (totA2 != 0.0) ? netA2 / totA2 : 0.0;
        signal = signal + ks * ((2.0 * cr + 0.5) - signal);
    }

    if (signal > 1.0) signal = 1.0;
    if (signal < 0.0) signal = 0.0;
    return signal;
}

/* ── Mapping valeur [0,1] → couleur ARGB ─────────────────────────────── */
/*
 * Gradient 5 étapes : bleu→cyan→vert→jaune→rouge
 * 0.0=bleu  0.25=cyan  0.50=vert  0.75=jaune  1.0=rouge
 */
static unsigned int ValueToColor(double v)
{
    if (v < 0.0) v = 0.0;
    if (v > 1.0) v = 1.0;
    unsigned char r, g, b;
    if (v < 0.25) {
        double t = v / 0.25;
        r = 0; g = (unsigned char)(255 * t); b = 255;
    } else if (v < 0.5) {
        double t = (v - 0.25) / 0.25;
        r = 0; g = 255; b = (unsigned char)(255 * (1.0 - t));
    } else if (v < 0.75) {
        double t = (v - 0.5) / 0.25;
        r = (unsigned char)(255 * t); g = 255; b = 0;
    } else {
        double t = (v - 0.75) / 0.25;
        r = 255; g = (unsigned char)(255 * (1.0 - t)); b = 0;
    }
    return 0xFF000000u | ((unsigned int)r << 16) | ((unsigned int)g << 8) | b;
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

static void SwamiRSI_DrawPanel(
    GpGraphics*     g,
    HDC             hDC,
    const double*   closes,
    const double*   opens,
    const double*   highs,
    const double*   lows,
    const double*   volumes,
    const int*      weekdays,
    int             count,
    int             period,          /* = EndLength, configurable par l'user */
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
    /* L'espace Y du panel correspond aux périodes StartLength..EndLength */
    int endLen   = period;
    int startLen = endLen / 4;
    if (startLen < 2) startLen = 2;
    int sampleLen = (startLen + endLen) / 2;   /* courbe médiane */
    int swamisize = endLen - startLen + 1;

    /* Espace de valeurs = périodes (pour crosshair/trendlines) */
    if (outVMin) *outVMin = (double)startLen;
    if (outVMax) *outVMax = (double)endLen;

    float oriX       = ctx->oriX;
    float stepX      = ctx->stepX;
    float lenX       = ctx->lenX;
    int   mainChartH = ctx->mainChartH;
    int   panelInnerH = panelH - 20;
    int   rTop    = mainChartH + panelIndex * (panelH + panelGap);
    int   rBottom = rTop + panelInnerH;

    if (swamisize < 1 || panelInnerH < 1) return;

    /* Hauteur d'une bande de période */
    float bandH = (float)panelInnerH / swamisize;
    if (bandH < 1.0f) bandH = 1.0f;

    /* ── Heatmap ─────────────────────────────────────────────────────── */
    int viewStart = ctx->viewStart;
    int lastIdx   = ctx->lastIdx;

    for (int bar = viewStart; bar <= lastIdx; ++bar) {
        float bx = oriX + (bar - viewStart) * stepX;
        float bw = stepX;
        if (bw < 1.0f) bw = 1.0f;

        for (int pi = 0; pi < swamisize; ++pi) {
            int   per = startLen + pi;
            double val = CalcSwamiRSI_bar(closes, count, bar, per);

            unsigned int col = ValueToColor(val);
            float by2 = (float)rBottom - (pi + 1) * bandH;

            GpSolidFill* br = nullptr;
            GdipCreateSolidFill(col, &br);
            GdipFillRectangle(g, (GpBrush*)br, bx, by2, bw, bandH + 0.5f);
            GdipDeleteBrush(br);
        }
    }

    /* ── Courbe RSI médiane (SampleLength) en blanc ───────────────────── */
    GpPen* pMed = nullptr;
    GdipCreatePen1(0xFFFFFFFF, 1.5f, UnitPixel, &pMed);
    float ox = 0.0f, oy = 0.0f;
    bool  fst = true;
    int   sampleIdx = sampleLen - startLen;   /* index dans [0..swamisize-1] */
    for (int bar = viewStart; bar <= lastIdx; ++bar) {
        double val = CalcSwamiRSI_bar(closes, count, bar, sampleLen);
        float x = oriX + (bar - viewStart) * stepX + stepX * 0.5f;
        /* val in [0,1] → Y dans le panel : val=1 → haut, val=0 → bas */
        float y = (float)rBottom - (float)(val * panelInnerH);
        if (!fst) GdipDrawLine(g, pMed, ox, oy, x, y);
        ox = x; oy = y; fst = false;
    }
    GdipDeletePen(pMed);

    /* ── Cadre + labels ──────────────────────────────────────────────── */
    GpPen* pG = nullptr;
    GdipCreatePen1(0xFF888888, 1.0f, UnitPixel, &pG);
    GdipDrawRectangleI(g, pG, (int)oriX, rTop, (int)lenX, panelInnerH);
    GdipDeletePen(pG);

    char lbl[48];
    if (panelCount > 1)
        std::snprintf(lbl, sizeof(lbl), "SwamiRSI(%d) #%d", endLen, panelIndex + 1);
    else
        std::snprintf(lbl, sizeof(lbl), "SwamiRSI(%d)", endLen);
    TextOutA(hDC, (int)oriX - 55, rTop + 2, lbl, (int)std::strlen(lbl));

    /* Légende des périodes min/max sur l'axe gauche */
    char lblMin[8], lblMax[8];
    std::snprintf(lblMin, sizeof(lblMin), "%d", startLen);
    std::snprintf(lblMax, sizeof(lblMax), "%d", endLen);
    TextOutA(hDC, (int)oriX - 22, rBottom - 10, lblMin, (int)std::strlen(lblMin));
    TextOutA(hDC, (int)oriX - 22, rTop   +  2, lblMax, (int)std::strlen(lblMax));

    /* ── Bouton X ────────────────────────────────────────────────────── */
    float bxBtn = oriX + lenX - (float)closeBtnSz - 2.0f;
    DrawCloseBtn(g, bxBtn, (float)rTop + 2.0f, (float)closeBtnSz);
}

/* ── Enregistrement ───────────────────────────────────────────────────── */
//QCHART_REGISTER: Register_SwamiRSI
extern "C" void Register_SwamiRSI(IndicatorRegistry* reg) {
    if (reg->count >= MAX_INDICATORS) return;
    IndicatorDef* d = &reg->defs[reg->count++];
    std::strncpy(d->name,        "Swami RSI",  sizeof(d->name)-1);
    std::strncpy(d->labelPrefix, "SwamiRSI",   sizeof(d->labelPrefix)-1);
    d->defaultPeriod = 48;
    d->isPanel       = 1;
    d->drawOverlay   = nullptr;
    d->drawPanel     = SwamiRSI_DrawPanel;
}
