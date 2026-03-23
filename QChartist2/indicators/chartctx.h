#pragma once
/*
 * chartctx.h
 * Contexte graphique partagé entre FreeBASIC et les modules C++.
 * Passé par pointeur pour éviter les problèmes de convention d'appel Win64.
 */
#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    float  oriX;        /* X origine de la zone graphique (pixels)  */
    float  oriY;        /* Y bas de la zone graphique (pixels)       */
    float  stepX;       /* largeur d'une bougie (pixels)             */
    float  lenX;        /* largeur totale de la zone (pixels)        */
    double vMin;        /* prix minimum visible                      */
    double scaleY;      /* facteur pixels/unité prix                 */
    int    mainChartH;  /* Y bas du graphe principal                 */
    int    viewStart;   /* index première barre visible              */
    int    lastIdx;     /* index dernière barre visible              */
    /* Données du TF de référence (brut, non mappé sur le TF courant).
     * Rempli par le .bas avant l'appel au callback overlay/panel.
     * NULL si l'indicateur n'utilise pas de TF de référence.          */
    const double* refHighs;      /* Highs du TF de référence          */
    const double* refLows;       /* Lows  du TF de référence          */
    const double* refOpens;      /* Opens du TF de référence          */
    const double* refTimestamps; /* Timestamps Unix du TF de référence*/
    int    refCount;             /* Nombre de barres dans le TF ref   */
    int    refTFMinutes;         /* Durée d'une barre ref en minutes  */
    const double* curTimestamps; /* Timestamps Unix du TF courant     */
} ChartCtx;

#ifdef __cplusplus
}
#endif
