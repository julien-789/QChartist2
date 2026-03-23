#pragma once
/*
 * indicator_api.h
 * Interface commune pour tous les indicateurs de QChart Pro.
 *
 * Pour créer un nouvel indicateur :
 *   1. Créer monIndicateur.cpp + monIndicateur.h dans ce dossier
 *   2. Implémenter les callbacks ci-dessous
 *   3. Exporter une fonction  void Register_MonIndicateur(IndicatorRegistry* reg)
 *   4. Relancer build.bat — il détecte et intègre automatiquement le nouveau fichier
 */

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <objbase.h>
#include <gdiplus.h>
#include "chartctx.h"

#ifdef __cplusplus
extern "C" {
#endif

/* ── Types de rendu ─────────────────────────────────────────────────────── */

/* OVERLAY : dessiné par-dessus les bougies (ex: Moving Average, Murrey Math)
 *
 *   g          : contexte GDI+
 *   hDC        : HDC GDI pour TextOut
 *   closes     : tableau de prix Close  (count éléments)
 *   highs      : tableau de prix High   (count éléments)
 *   lows       : tableau de prix Low    (count éléments)
 *   count      : nombre total de barres
 *   period     : période configurée par l'utilisateur
 *   panelIndex : index de ce panneau parmi les panneaux overlay (pour couleur/label)
 *   ctx        : coordonnées du graphe
 *   closeBtnSz : taille du bouton ✕ en pixels
 *   colors     : palette de 8 couleurs ARGB (partagée entre tous les overlays)
 */
typedef void (*DrawOverlayFn)(
    Gdiplus::GpGraphics* g,
    HDC                  hDC,
    const double*        closes,
    const double*        opens,
    const double*        highs,
    const double*        lows,
    const double*        volumes,
    const int*           weekdays,
    int                  count,
    int                  period,
    int                  param2,
    int                  panelIndex,
    const ChartCtx*      ctx,
    int                  closeBtnSz,
    const unsigned int*  colors
);

/* PANEL : dessiné dans un canvas séparé sous le graphe principal (ex: RSI, MACD)
 *
 *   g          : contexte GDI+
 *   hDC        : HDC GDI pour TextOut
 *   closes     : tableau de prix Close  (count éléments)
 *   highs      : tableau de prix High   (count éléments)
 *   lows       : tableau de prix Low    (count éléments)
 *   count      : nombre total de barres
 *   period     : période configurée
 *   panelIndex : index du panneau (position verticale absolue)
 *   panelCount : nombre total de panneaux de ce type (pour le label #N)
 *   ctx        : coordonnées du graphe
 *   panelH     : hauteur totale du panneau (pixels)
 *   panelGap   : espacement entre panneaux (pixels)
 *   closeBtnSz : taille du bouton ✕
 *   outVMin    : [out] valeur minimale de l'espace Y de ce panel
 *   outVMax    : [out] valeur maximale de l'espace Y de ce panel
 */
typedef void (*DrawPanelFn)(
    Gdiplus::GpGraphics* g,
    HDC                  hDC,
    const double*        closes,
    const double*        opens,
    const double*        highs,
    const double*        lows,
    const double*        volumes,
    const int*           weekdays,
    int                  count,
    int                  period,
    int                  param2,
    int                  panelIndex,
    int                  panelCount,
    const ChartCtx*      ctx,
    int                  panelH,
    int                  panelGap,
    int                  closeBtnSz,
    double*              outVMin,
    double*              outVMax
);

/* ── Descripteur d'un indicateur ────────────────────────────────────────── */
typedef struct {
    char         name[64];       /* Nom affiché dans la liste (ex: "Moving Average") */
    char         labelPrefix[16];/* Préfixe du label sur le graphe (ex: "MA", "RSI")*/
    int          defaultPeriod;  /* Période proposée par défaut dans l'UI           */
    int          defaultParam2;  /* Valeur par défaut du 2ème paramètre (0=absent)  */
    char         param2Label[32];/* Label du 2ème paramètre ("" = caché)            */
    int          isPanel;        /* 0 = overlay sur bougies, 1 = canvas séparé      */
    DrawOverlayFn drawOverlay;   /* Callback overlay (NULL si isPanel=1)            */
    DrawPanelFn   drawPanel;     /* Callback panel  (NULL si isPanel=0)             */
} IndicatorDef;

/* ── Registre global des indicateurs ────────────────────────────────────── */
#define MAX_INDICATORS 32

typedef struct {
    IndicatorDef defs[MAX_INDICATORS];
    int          count;
} IndicatorRegistry;

/* Appelé par chaque indicateur pour s'enregistrer.
 * La fonction Register_XXX() doit remplir une entrée dans reg->defs[reg->count++] */
typedef void (*RegisterFn)(IndicatorRegistry* reg);

#ifdef __cplusplus
}
#endif
