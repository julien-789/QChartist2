/*
 * indicators/weeklypivot.cpp
 * Weekly Pivot Points — indicateur overlay (7 niveaux : P, R1/S1, R2/S2, R3/S3).
 *
 * Algorithme (fidèle à WeeklyPivot.mq4 porté pour QChartist) :
 *   Détecte le premier jour de chaque semaine (lundi, weekday==1).
 *   Calcule les pivots à partir du High/Low de la semaine précédente
 *   et du Close/Open de transition :
 *     P  = (lastH + lastL + thisOpen + lastClose) / 4
 *     R1 = 2*P - lastL       S1 = 2*P - lastH
 *     R2 = P + (lastH-lastL) S2 = P - (lastH-lastL)
 *     R3 = 2*P + (lastH - 2*lastL)
 *     S3 = 2*P - (2*lastH - lastL)
 *
 * Le paramètre "period" est ignoré (les pivots sont hebdomadaires par définition).
 * weekdays[] doit contenir le jour de la semaine : 0=Dim, 1=Lun, ..., 6=Sam.
 *
 * Couleurs :
 *   P   = Magenta     (pivot principal)
 *   R1,R2,R3 = Crimson   (résistances)
 *   S1,S2,S3 = RoyalBlue (supports)
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

static const int MAX_B = 4096;

/* ── Structure pour un jeu de pivots ─────────────────────────────────── */
struct PivotSet {
    double P, R1, S1, R2, S2, R3, S3;
};

/* ── Calcul des pivots sur toute la série ─────────────────────────────── */
/*
 * Remplit pivots[0..count-1] avec les niveaux actifs à chaque barre.
 * weekdays[i] = 0=Dim, 1=Lun, ..., 6=Sam (ou -1 si inconnu).
 */
static void CalcWeeklyPivots(
    const double* closes, const double* highs, const double* lows,
    const int* weekdays, int count,
    PivotSet* pivots)
{
    double lastH = 0.0, lastL = 1e18;
    double lastClose = 0.0;
    double P=0, R1=0, S1=0, R2=0, S2=0, R3=0, S3=0;
    bool   initialized = false;

    /* Parcours du plus ancien au plus récent (index croissant) */
    for (int i = 0; i < count; ++i) {
        int wd   = weekdays[i];
        int wdPrev = (i > 0) ? weekdays[i-1] : -1;

        /* Détection du lundi (début de semaine) */
        bool isMonday = (wd == 1) && (wdPrev != 1) && (i > 0);

        if (isMonday) {
            double thisOpen = (i > 0) ? closes[i-1] : closes[i]; /* open ≈ close précédent en daily */
            lastClose = closes[i-1];

            if (lastH > 0.0 && lastL < 1e17) {
                P  = (lastH + lastL + thisOpen + lastClose) / 4.0;
                R1 = 2.0*P - lastL;
                S1 = 2.0*P - lastH;
                R2 = P + (lastH - lastL);
                S2 = P - (lastH - lastL);
                R3 = 2.0*P + (lastH - 2.0*lastL);
                S3 = 2.0*P - (2.0*lastH - lastL);
                initialized = true;
            }
            /* Réinitialiser le range de la nouvelle semaine */
            lastH = highs[i];
            lastL = lows[i];
        } else {
            /* Mettre à jour le range de la semaine en cours */
            if (highs[i] > lastH) lastH = highs[i];
            if (lows [i] < lastL) lastL = lows [i];
        }

        if (initialized) {
            pivots[i] = { P, R1, S1, R2, S2, R3, S3 };
        } else {
            pivots[i] = { -1, -1, -1, -1, -1, -1, -1 };
        }
    }
}

/* ── Dessin d'une ligne horizontale de pivot ──────────────────────────── */
static void DrawPivotLine(
    GpGraphics* g, HDC hDC,
    const PivotSet* pivots, int count,
    int viewStart, int lastIdx,
    float oriX, float oriY, float stepX,
    double vMin, double scaleY,
    double PivotSet::*field,
    unsigned int color, float width,
    bool dashed,
    const char* label)
{
    float ox = 0.0f, oy = 0.0f;
    bool  fst = true;
    float lastY = -1.0f;

    GpPen* pen = nullptr;
    GdipCreatePen1(color, width, UnitPixel, &pen);
    if (dashed) GdipSetPenDashStyle(pen, (GpDashStyle)1);

    for (int i = viewStart; i <= lastIdx; ++i) {
        if (i < 0 || i >= count) continue;
        double val = pivots[i].*field;
        if (val < 0.0) { fst = true; continue; }

        float x = oriX + (i - viewStart) * stepX + stepX * 0.5f;
        float y = oriY - (float)((val - vMin) * scaleY);
        if (!fst) GdipDrawLine(g, pen, ox, oy, x, y);
        ox = x; oy = y; fst = false;
        lastY = y;
    }
    GdipDeletePen(pen);

    /* Label sur le bord droit si la ligne est visible */
    if (lastY >= 0.0f && label) {
        float xRight = oriX + (lastIdx - viewStart + 1) * stepX;
        /* Fond semi-transparent */
        unsigned int bgCol = (color & 0x00FFFFFF) | 0x99000000;
        GpSolidFill* br = nullptr;
        GdipCreateSolidFill(bgCol, &br);
        int lw = (int)std::strlen(label) * 7 + 4;
        GdipFillRectangle(g, (GpBrush*)br, xRight + 2, lastY - 8.0f, (float)lw, 14.0f);
        GdipDeleteBrush(br);
        SetBkMode(hDC, TRANSPARENT);
        /* Couleur texte = blanc pour lisibilité */
        SetTextColor(hDC, 0xFFFFFF);
        TextOutA(hDC, (int)xRight + 4, (int)lastY - 8, label, (int)std::strlen(label));
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

static void WP_DrawOverlay(
    GpGraphics*         g,
    HDC                 hDC,
    const double*       closes,
    const double*       opens,
    const double*       highs,
    const double*       lows,
    const double*       /*volumes*/,
    const int*          weekdays,
    int                 count,
    int                 /*period*/,
    int             param2,
    int                 panelIndex,
    const ChartCtx*     ctx,
    int                 closeBtnSz,
    const unsigned int* /*colors*/)
{
    if (count < 2 || count > MAX_B) return;

    float  oriX   = ctx->oriX;
    float  oriY   = ctx->oriY;
    float  stepX  = ctx->stepX;
    float  lenX   = ctx->lenX;
    double vMin   = ctx->vMin;
    double scaleY = ctx->scaleY;
    int    vs     = ctx->viewStart;
    int    li     = ctx->lastIdx;

    /* Calcul des pivots sur toute la série */
    static PivotSet pivots[MAX_B];
    CalcWeeklyPivots(closes, highs, lows, weekdays, count, pivots);

    /* ── Tracer les 7 niveaux ─────────────────────────────────────────── */
    /* P  — Magenta,  plein, épais */
    DrawPivotLine(g, hDC, pivots, count, vs, li, oriX, oriY, stepX, vMin, scaleY,
        &PivotSet::P,  0xFFFF00FF, 1.8f, false, "P");
    /* R1 — Crimson */
    DrawPivotLine(g, hDC, pivots, count, vs, li, oriX, oriY, stepX, vMin, scaleY,
        &PivotSet::R1, 0xFFDC143C, 1.2f, false, "R1");
    /* S1 — RoyalBlue */
    DrawPivotLine(g, hDC, pivots, count, vs, li, oriX, oriY, stepX, vMin, scaleY,
        &PivotSet::S1, 0xFF4169E1, 1.2f, false, "S1");
    /* R2 — Crimson tirets */
    DrawPivotLine(g, hDC, pivots, count, vs, li, oriX, oriY, stepX, vMin, scaleY,
        &PivotSet::R2, 0xFFDC143C, 1.0f, true,  "R2");
    /* S2 — RoyalBlue tirets */
    DrawPivotLine(g, hDC, pivots, count, vs, li, oriX, oriY, stepX, vMin, scaleY,
        &PivotSet::S2, 0xFF4169E1, 1.0f, true,  "S2");
    /* R3 — Crimson pointillés */
    DrawPivotLine(g, hDC, pivots, count, vs, li, oriX, oriY, stepX, vMin, scaleY,
        &PivotSet::R3, 0xFFDC143C, 1.0f, true,  "R3");
    /* S3 — RoyalBlue pointillés */
    DrawPivotLine(g, hDC, pivots, count, vs, li, oriX, oriY, stepX, vMin, scaleY,
        &PivotSet::S3, 0xFF4169E1, 1.0f, true,  "S3");

    SetTextColor(hDC, 0);

    /* ── Label + bouton X ────────────────────────────────────────────── */
    const char* lbl = "WPivot";
    int lblX = (int)oriX + 4;
    int lblY = 28 + 14 + panelIndex * (closeBtnSz + 4);
    SetBkMode(hDC, TRANSPARENT);
    SetTextColor(hDC, 0xCC00CC);   /* Magenta */
    TextOutA(hDC, lblX, lblY, lbl, (int)std::strlen(lbl));
    SetTextColor(hDC, 0);
    float btnX = (float)(lblX + (int)std::strlen(lbl) * 7 + 3);
    DrawCloseBtn(g, btnX, (float)(lblY - 1), (float)closeBtnSz);
}

/* ── Enregistrement ───────────────────────────────────────────────────── */
//QCHART_REGISTER: Register_WeeklyPivot
extern "C" void Register_WeeklyPivot(IndicatorRegistry* reg) {
    if (reg->count >= MAX_INDICATORS) return;
    IndicatorDef* d = &reg->defs[reg->count++];
    std::strncpy(d->name,        "Weekly Pivot", sizeof(d->name)-1);
    std::strncpy(d->labelPrefix, "WPivot",       sizeof(d->labelPrefix)-1);
    d->defaultPeriod = 1;   /* ignoré, pivots hebdomadaires */
    d->isPanel       = 0;
    d->drawOverlay   = WP_DrawOverlay;
    d->drawPanel     = nullptr;
}
