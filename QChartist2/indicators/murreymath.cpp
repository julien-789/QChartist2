/*
 * indicators/murreymath.cpp
 * Murrey Math Lines — indicateur overlay (13 niveaux de support/résistance).
 *
 * Principe :
 *   Sur une fenêtre glissante de P barres (paramètre "period"), on trouve le
 *   plus bas (v1) et le plus haut (v2) des cours de clôture.
 *   On calcule ensuite une octave de Murrey à partir d'un fractal binaire,
 *   puis 13 niveaux équidistants de -2/8 à +2/8 (0/8..8/8 = grille principale).
 *
 * Le paramètre "period" = P (fenêtre de recherche du range, défaut 64).
 * Les 13 lignes sont tracées sur toute la largeur de la fenêtre visible,
 * recalculées à chaque barre.
 *
 * Couleurs (fidèles à l'original MetaTrader) :
 *   -2/8  +2/8  = Rouge           (extrêmes)
 *   -1/8  +1/8  = OrangeRed       (overshoot)
 *    0/8   8/8  = DodgerBlue      (support/résistance ultime)
 *    1/8   7/8  = Jaune           (faible, stall & reverse)
 *    2/8   6/8  = DeepPink        (pivot, reverse)
 *    3/8   5/8  = Lime            (haut/bas du range de trading)
 *    4/8        = DodgerBlue épais (support/résistance majeur)
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

/* ── Couleurs des 13 niveaux (index 0 = -2/8 .. 12 = +2/8) ──────────── */
static const unsigned int MM_COLORS[13] = {
    0xFFCC0000,   /*  0 : -2/8  rouge             */
    0xFFFF4500,   /*  1 : -1/8  orangered          */
    0xFF1E90FF,   /*  2 :  0/8  dodgerblue         */
    0xFFFFFF00,   /*  3 :  1/8  jaune              */
    0xFFFF1493,   /*  4 :  2/8  deeppink           */
    0xFF00FF00,   /*  5 :  3/8  lime               */
    0xFF1E90FF,   /*  6 :  4/8  dodgerblue (épais) */
    0xFF00FF00,   /*  7 :  5/8  lime               */
    0xFFFF1493,   /*  8 :  6/8  deeppink           */
    0xFFFFFF00,   /*  9 :  7/8  jaune              */
    0xFF1E90FF,   /* 10 :  8/8  dodgerblue         */
    0xFFFF4500,   /* 11 : +1/8  orangered          */
    0xFFCC0000,   /* 12 : +2/8  rouge              */
};

static const float MM_WIDTH[13] = {
    1.0f, 1.0f, 1.5f, 1.0f, 1.5f,
    1.5f, 2.5f,                     /* 4/8 : ligne principale plus épaisse */
    1.5f, 1.5f, 1.0f, 1.5f,
    1.0f, 1.0f
};

static const char* MM_LABELS[13] = {
    "-2/8", "-1/8", "0/8",  "1/8",  "2/8",
    "3/8",  "4/8",  "5/8",  "6/8",  "7/8",
    "8/8",  "+1/8", "+2/8"
};

/* ── Calcul de la grille Murrey pour une barre donnée ────────────────── */
/*
 * Cherche le min/max sur les P barres précédant la barre `bar`,
 * puis calcule les 13 niveaux mml[0..12].
 * Retourne false si pas assez de données.
 */
static bool CalcMurreyLevels(
    const double* closes, const double* highs, const double* lows,
    int count, int bar, int P,
    double mml[13])
{
    if (bar < P || bar >= count) return false;

    /* Recherche du min/max sur P barres */
    double v1 = lows[bar],  v2 = highs[bar];
    for (int k = 0; k < P && (bar - k) >= 0; ++k) {
        if (lows [bar - k] < v1) v1 = lows [bar - k];
        if (highs[bar - k] > v2) v2 = highs[bar - k];
    }
    if (v2 <= 0.0 || v2 <= v1) return false;

    /* Détermination du fractal binaire */
    double fractal = 0.1953125;
    if      (v2 > 25000.0)  fractal = 100000.0;
    else if (v2 > 2500.0)   fractal = 10000.0;
    else if (v2 > 250.0)    fractal = 1000.0;
    else if (v2 > 25.0)     fractal = 100.0;
    else if (v2 > 12.5)     fractal = 12.5;
    else if (v2 > 6.25)     fractal = 12.5;
    else if (v2 > 3.125)    fractal = 6.25;
    else if (v2 > 1.5625)   fractal = 3.125;
    else if (v2 > 0.390625) fractal = 1.5625;

    double range  = v2 - v1;
    double sum    = std::floor(std::log(fractal / range) / std::log(2.0));
    double octave = fractal * std::pow(0.5, sum);
    double mn     = std::floor(v1 / octave) * octave;
    double mx     = (mn + octave > v2) ? mn + octave : mn + 2.0 * octave;

    /* Calcul de finalH (x1..x6) */
    double x1=0, x2=0, x3=0, x4=0, x5=0, x6=0;
    double y1=0, y2=0, y3=0, y4=0, y5=0, y6=0;
    double rng = mx - mn;

    if (v1 >= (3.0*rng/16.0 + mn) && v2 <= (9.0*rng/16.0 + mn))
        x2 = mn + rng / 2.0;
    if (v1 >= (mn - rng/8.0) && v2 <= (5.0*rng/8.0 + mn) && x2 == 0)
        x1 = mn + rng / 2.0;
    if (v1 >= (mn + 7.0*rng/16.0) && v2 <= (13.0*rng/16.0 + mn))
        x4 = mn + 3.0*rng / 4.0;
    if (v1 >= (mn + 3.0*rng/8.0) && v2 <= (9.0*rng/8.0 + mn) && x4 == 0)
        x5 = mx;
    if (v1 >= (mn + rng/8.0) && v2 <= (7.0*rng/8.0 + mn)
        && x1==0 && x2==0 && x4==0 && x5==0)
        x3 = mn + 3.0*rng / 4.0;
    if ((x1+x2+x3+x4+x5) == 0)
        x6 = mx;

    double finalH = x1+x2+x3+x4+x5+x6;

    if (x1 > 0) y1 = mn;
    if (x2 > 0) y2 = mn + rng / 4.0;
    if (x3 > 0) y3 = mn + rng / 4.0;
    if (x4 > 0) y4 = mn + rng / 2.0;
    if (x5 > 0) y5 = mn + rng / 2.0;
    if (finalH > 0 && (y1+y2+y3+y4+y5) == 0) y6 = mn;

    double finalL = y1+y2+y3+y4+y5+y6;
    double dmml   = (finalH - finalL) / 8.0;
    if (dmml == 0.0) return false;

    mml[0] = finalL - dmml * 2.0;   /* -2/8 */
    for (int i = 1; i < 13; ++i)
        mml[i] = mml[i-1] + dmml;

    return true;
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

static void MM_DrawOverlay(
    GpGraphics*         g,
    HDC                 hDC,
    const double*       closes,
    const double*       opens,
    const double*        highs,
    const double*        lows,
    const double*   volumes,
    const int*      weekdays,
    int                 count,
    int                 period,
    int             param2,
    int                 panelIndex,
    const ChartCtx*     ctx,
    int                 closeBtnSz,
    const unsigned int* /*colors*/)   /* couleurs internes, palette ignorée */
{
    float  oriX   = ctx->oriX;
    float  oriY   = ctx->oriY;
    float  stepX  = ctx->stepX;
    float  lenX   = ctx->lenX;
    double vMin   = ctx->vMin;
    double scaleY = ctx->scaleY;
    int    vs     = ctx->viewStart;
    int    li     = ctx->lastIdx;

    if (count < period + 1) return;

    /* ── Calculer les niveaux Murrey sur la dernière barre visible ──────
       L'original recalculait barre par barre, mais les niveaux varient peu.
       On calcule une fois sur la barre centrale de la vue pour la lisibilité,
       et on trace des lignes horizontales continues sur toute la vue. */
    int midBar = vs + (li - vs) / 2;
    double mml[13] = {};
    if (!CalcMurreyLevels(closes, highs, lows, count, midBar, period, mml))
        return;

    /* ── Tracer les 13 niveaux ─────────────────────────────────────────── */
    float xLeft  = oriX;
    float xRight = oriX + lenX;

    for (int lvl = 0; lvl < 13; ++lvl) {
        double price = mml[lvl];
        /* Ne pas dessiner les niveaux hors de la vue Y */
        float y = oriY - (float)((price - vMin) * scaleY);
        if (y < 0 || y > oriY + 60) continue;   /* hors vue, skip */

        GpPen* pen = nullptr;
        GdipCreatePen1(MM_COLORS[lvl], MM_WIDTH[lvl], UnitPixel, &pen);

        /* Tirets pour les niveaux extrêmes (-2/8, -1/8, +1/8, +2/8) */
        if (lvl == 0 || lvl == 1 || lvl == 11 || lvl == 12)
            GdipSetPenDashStyle(pen, (GpDashStyle)1);   /* DashStyleDash */

        GdipDrawLine(g, pen, xLeft, y, xRight, y);
        GdipDeletePen(pen);

        /* Label sur le bord droit avec fond semi-transparent */
        char lbl[8];
        std::snprintf(lbl, sizeof(lbl), "%s", MM_LABELS[lvl]);

        /* Fond du label */
        unsigned int bgCol = (MM_COLORS[lvl] & 0x00FFFFFF) | 0x99000000;
        GpSolidFill* br = nullptr;
        GdipCreateSolidFill(bgCol, &br);
        GdipFillRectangle(g, (GpBrush*)br,
            xRight + 2, y - 8.0f,
            (float)(std::strlen(lbl) * 7 + 4), 14.0f);
        GdipDeleteBrush(br);

        /* Texte blanc */
        SetBkMode(hDC, TRANSPARENT);
        SetTextColor(hDC, 0xFFFFFF);
        TextOutA(hDC, (int)xRight + 4, (int)y - 8, lbl, (int)std::strlen(lbl));
    }

    /* ── Label + bouton X dans le coin supérieur gauche ─────────────────── */
    char lbl[32];
    std::snprintf(lbl, sizeof(lbl), "MM(%d)", period);
    int lblX = (int)oriX + 4;
    int lblY = 28 + 14 + panelIndex * (closeBtnSz + 4);

    SetTextColor(hDC, 0x1E90FF);   /* DodgerBlue */
    TextOutA(hDC, lblX, lblY, lbl, (int)std::strlen(lbl));
    SetTextColor(hDC, 0);

    float btnX = (float)(lblX + (int)std::strlen(lbl) * 7 + 3);
    DrawCloseBtn(g, btnX, (float)(lblY - 1), (float)closeBtnSz);
}

/* ── Enregistrement ───────────────────────────────────────────────────── */
//QCHART_REGISTER: Register_MurreyMath
extern "C" void Register_MurreyMath(IndicatorRegistry* reg) {
    if (reg->count >= MAX_INDICATORS) return;
    IndicatorDef* d = &reg->defs[reg->count++];
    std::strncpy(d->name,        "Murrey Math",  sizeof(d->name)-1);
    std::strncpy(d->labelPrefix, "MM",           sizeof(d->labelPrefix)-1);
    d->defaultPeriod = 64;
    d->isPanel       = 0;
    d->drawOverlay   = MM_DrawOverlay;
    d->drawPanel     = nullptr;
}
