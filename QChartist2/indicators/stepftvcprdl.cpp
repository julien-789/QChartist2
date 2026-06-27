/*
 * indicators/stepftvcprdl.cpp
 * STEP Fisher Transform Value Chart Past Regression Deviated Log
 *
 * Convention QChartist2 : closes[0] = bar le plus ANCIEN
 *                         closes[count-1] = bar le plus RÉCENT
 *
 * Pipeline :
 *   1. Past Regression Deviated Log (LRlength=500 bars)
 *      → régression linéaire sur closea[], canaux stddev 3σ
 *   2. Value Chart : normalise le close par rapport à la bande 3σ
 *   3. Fisher Transform IIR (lissage)
 *   4. Step Fast (StepSize=5) + Step Slow (StepSize=15) sur le signal Fisher
 *
 * Sorties (panel séparé, échelle dynamique sur les barres visibles) :
 *   Line1 : Fisher VC              (orange)
 *   Line2 : Step Fast              (lightblue)
 *   Line3 : Step Slow              (rouge)
 *   Niveaux fixes 20 / 50 / 80    (gris pointillés)
 *
 * period = non utilisé algorithmiquement (défaut 20, héritage QTP)
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

static const int MAX_B     = 4096;
static const int LRLENGTH  = 500;
static const int P1        = 5;
static const int STEP_FAST = 5;
static const int STEP_SLOW = 15;

/* ── Helper bouton X ─────────────────────────────────────────────── */
static void DrawCloseBtn(GpGraphics* g, float bx, float by, float bsz)
{
    GpSolidFill* br=nullptr; GdipCreateSolidFill(0xFFE8E8E8,&br);
    GdipFillRectangle(g,(GpBrush*)br,bx,by,bsz,bsz); GdipDeleteBrush((GpBrush*)br);
    GpPen* pB=nullptr; GdipCreatePen1(0xFFAAAAAA,1.0f,UnitPixel,&pB);
    GdipDrawRectangle(g,pB,bx,by,bsz,bsz); GdipDeletePen(pB);
    GpPen* pX=nullptr; GdipCreatePen1(0xFFCC0000,1.8f,UnitPixel,&pX);
    float mg=3.5f;
    GdipDrawLine(g,pX,bx+mg,by+mg,bx+bsz-mg,by+bsz-mg);
    GdipDrawLine(g,pX,bx+bsz-mg,by+mg,bx+mg,by+bsz-mg);
    GdipDeletePen(pX);
}

/* ── DrawPanel ───────────────────────────────────────────────────── */
static void STEPFTVCPRDL_DrawPanel(
    GpGraphics*     g,
    HDC             hDC,
    const double*   closes,
    const double*   opens,
    const double*   /*highs*/,
    const double*   /*lows*/,
    const double*   /*volumes*/,
    const int*      /*weekdays*/,
    int             count,
    int             /*period*/,
    int             /*param2*/,
    int             panelIndex,
    int             panelCount,
    const ChartCtx* ctx,
    int             panelH,
    int             panelGap,
    int             closeBtnSz,
    double*         outVMin,
    double*         outVMax)
{
    /* outVMin/outVMax seront remplis après le calcul (échelle dynamique) */
    if (outVMin) *outVMin = 0.0;
    if (outVMax) *outVMax = 100.0;

    /* Besoin minimum : LRLENGTH + P1 + quelques bars */
    if (count < LRLENGTH + P1 + 10) return;

    /* ── Géométrie panel ─────────────────────────────────────────── */
    float oriX       = ctx->oriX;
    float stepX      = ctx->stepX;
    float lenX       = ctx->lenX;
    int   mainChartH = ctx->mainChartH;
    int   panelInnerH = panelH - 20;
    int   rTop    = mainChartH + panelIndex*(panelH+panelGap);
    int   rBottom = rTop + panelInnerH;
    int   vs      = ctx->viewStart;
    int   li      = ctx->lastIdx;

    /* ── Buffers de calcul (statiques) ───────────────────────────── */
    static double meanBuf[MAX_B];
    static double high3  [MAX_B];
    static double low3   [MAX_B];
    static double lrTL   [MAX_B];
    static double vc     [MAX_B];
    static double Line1  [MAX_B];
    static double Line2  [MAX_B];
    static double Line3  [MAX_B];

    for (int i=0;i<count;++i)
        meanBuf[i]=high3[i]=low3[i]=lrTL[i]=vc[i]=NAN;

    /* ── Étape 1 : Past Regression Deviated Log ──────────────────
     * closes[0]=plus ancien. On itère i = 0..count-1
     * Pour chaque i, la fenêtre de régression est [i-LRLENGTH .. i]
     * soit endbar=i-LRLENGTH (plus ancien) et startbar=i (plus récent)
     * (inversion par rapport à QC1 où i=0 était le plus récent)
     */
    for (int i = LRLENGTH; i < count; ++i)
    {
        int endbar   = i - LRLENGTH;   /* plus ancien */
        int startbar = i;              /* plus récent */
        int n        = startbar - endbar + 1;  /* = LRLENGTH+1 */

        double sumy=0, sumx=0, sumxy=0, sumx2=0;
        for (int ii=0; ii<n; ++ii){
            double val = closes[endbar+ii];
            sumy  += val;
            sumxy += val*(double)ii;
            sumx  += (double)ii;
            sumx2 += (double)ii*(double)ii;
        }
        double logSumx2 = (sumx2 > 0.0) ? std::log(sumx2) : 0.0;
        double logSumx  = (sumx  > 0.0) ? std::log(sumx)  : 0.0;
        double c = logSumx2*(double)n - sumx*sumx;
        if (c == 0.0) continue;

        double b_coef = (sumxy*(double)n - sumx*sumy) / c;
        double a_coef = (sumy - logSumx*b_coef) / (double)n;

        /* LRprice1 = valeur à endbar, LRprice2 = valeur à startbar */
        double LRprice1 = a_coef;                    /* endbar (n=0) */
        double LRprice2 = a_coef + b_coef*(double)(n-1); /* startbar     */

        meanBuf[i] = LRprice2;  /* valeur courante de la régression */

        /* Interpolation trendline */
        double range = LRprice2 - LRprice1;
        double step  = range / (double)(n-1);
        for (int j=0; j<n; ++j)
            lrTL[endbar+j] = LRprice1 + step*(double)j;

        /* Écart-type des résidus */
        double xsumsq=0.0;
        for (int j=0; j<n-1; ++j){
            double dev = std::fabs(closes[endbar+j] - lrTL[endbar+j]);
            xsumsq += dev*dev;
        }
        double stddev = (n>2) ? std::sqrt(xsumsq/(double)(n-2)) : 0.0;

        high3[i] = meanBuf[i] + 3.0*stddev;
        low3 [i] = meanBuf[i] - 3.0*stddev;
    }

    /* ── Étape 2 : Value Chart + Fisher Transform ─────────────────
     * On calcule de la gauche (plus ancien) vers la droite
     * pour que le terme de mémoire vc[i-1] soit déjà connu.
     */
    vc[LRLENGTH] = 0.0;   /* initialisation du terme de mémoire */

    for (int i = LRLENGTH; i < count; ++i)
    {
        /* Besoin de P1 bars en avant pour la moyenne */
        if (i + P1 - 1 >= count){ vc[i]=NAN; continue; }

        /* Moyenne glissante P1 du midpoint 3σ */
        double m1=0.0;
        for (int k=0; k<P1; ++k)
            m1 += 0.5*(high3[i+k] + low3[i+k]);
        m1 /= (double)P1;

        /* DVU = moyenne de la range 3σ sur P1 × 0.2 */
        double dvu=0.0;
        for (int k=0; k<P1; ++k)
            dvu += high3[i+k] - low3[i+k];
        dvu = (dvu/(double)P1) * 0.2;

        double vc_raw = closes[i] - m1;
        if (dvu != 0.0) vc_raw /= dvu;
        else            vc_raw  = 0.0;

        /* Fisher Transform IIR (mémoire = vc[i-1]) */
        double prev = (i > LRLENGTH && !std::isnan(vc[i-1])) ? vc[i-1] : 0.0;
        vc[i] = 0.5*((vc_raw+4.0)*12.5/100.0 - 0.5)*2.0 + 0.5*prev;
    }

    /* ── Étape 3 : Step Fast / Slow ──────────────────────────────
     * RSI0 = remappage Fisher [-1,1] → [0,100]
     * Itération gauche→droite (plus ancien→plus récent)
     */
    int    ftrend=0, strend=0;
    double fmin1=0, fmax1=0, smin1=0, smax1=0;

    for (int i = LRLENGTH; i < count; ++i)
    {
        if (std::isnan(vc[i])){ Line1[i]=NAN; Line2[i]=NAN; Line3[i]=NAN; continue; }

        double RSI0 = (vc[i]+1.0)*0.5*100.0;
        /* Clamp pour éviter les débordements extrêmes */
        if (RSI0 < 0.0)   RSI0 = 0.0;
        if (RSI0 > 100.0) RSI0 = 100.0;

        /* Step Fast */
        double fmax0 = RSI0 + 2.0*STEP_FAST;
        double fmin0 = RSI0 - 2.0*STEP_FAST;
        if (RSI0 > fmax1) ftrend =  1;
        if (RSI0 < fmin1) ftrend = -1;
        if (ftrend > 0 && fmin0 < fmin1) fmin0 = fmin1;
        if (ftrend < 0 && fmax0 > fmax1) fmax0 = fmax1;

        /* Step Slow */
        double smax0 = RSI0 + 2.0*STEP_SLOW;
        double smin0 = RSI0 - 2.0*STEP_SLOW;
        if (RSI0 > smax1) strend =  1;
        if (RSI0 < smin1) strend = -1;
        if (strend > 0 && smin0 < smin1) smin0 = smin1;
        if (strend < 0 && smax0 > smax1) smax0 = smax1;

        Line1[i] = RSI0;
        Line2[i] = (ftrend > 0) ? fmin0+(double)STEP_FAST : fmax0-(double)STEP_FAST;
        Line3[i] = (strend > 0) ? smin0+(double)STEP_SLOW : smax0-(double)STEP_SLOW;

        fmin1=fmin0; fmax1=fmax0;
        smin1=smin0; smax1=smax0;
    }

    /* ── Échelle dynamique sur les barres visibles ───────────────────
     * On scanne les 3 courbes sur [vs..li] pour trouver min/max réels,
     * puis on ajoute 10 % de marge — exactement comme sharperatio.cpp.
     * Cela "zoom" automatiquement sur ce qui est visible.
     */
    double vMin =  1e30;
    double vMax = -1e30;
    for (int i=vs; i<=li; ++i){
        if (i<0||i>=count) continue;
        double vals[3] = { Line1[i], Line2[i], Line3[i] };
        for (double v : vals){
            if (!std::isnan(v)){
                if (v < vMin) vMin = v;
                if (v > vMax) vMax = v;
            }
        }
    }
    if (vMin == 1e30){ vMin = 0.0; vMax = 100.0; }   /* fallback si rien de visible */
    double rng = vMax - vMin;
    if (rng < 1.0) rng = 1.0;
    vMin -= rng * 0.10;
    vMax += rng * 0.10;

    /* Transmettre l'espace de valeurs au moteur (trendlines / crosshair) */
    if (outVMin) *outVMin = vMin;
    if (outVMax) *outVMax = vMax;

    /* helper : valeur → pixel Y dans le panel (échelle dynamique) */
    auto toY = [&](double v) -> float {
        return (float)rBottom - (float)((v - vMin) / (vMax - vMin)) * (float)panelInnerH;
    };

    /* ── Cadre ───────────────────────────────────────────────────── */
    GpPen* pG=nullptr; GdipCreatePen1(0xFFCCCCCC,1.0f,UnitPixel,&pG);
    GdipDrawRectangleI(g,pG,(int)oriX,rTop,(int)lenX,panelInnerH);
    GdipDeletePen(pG);

    /* ── Niveaux de référence 20 / 50 / 80 (pointillés gris) ────── */
    auto DrawLevel = [&](double level, const char* lbl){
        if (level < vMin || level > vMax) return;   /* hors de l'échelle visible */
        float yLv = toY(level);
        GpPen* pLv=nullptr; GdipCreatePen1(0xFF888888,1.0f,UnitPixel,&pLv);
        GdipSetPenDashStyle(pLv,(GpDashStyle)2);    /* Dash */
        GdipDrawLine(g,pLv,oriX,yLv,oriX+lenX,yLv);
        GdipDeletePen(pLv);
        char tmp[8]; std::snprintf(tmp,sizeof(tmp),"%s",lbl);
        TextOutA(hDC,(int)oriX-22,(int)yLv-7,tmp,(int)std::strlen(tmp));
    };

    /* ── Tracé des 3 courbes ─────────────────────────────────────── */
    struct { const double* buf; unsigned int color; float width; } curves[3] = {
        { Line3, 0xFFCC0000, 1.5f },   /* Step Slow  — rouge      */
        { Line2, 0xFF00CCFF, 1.5f },   /* Step Fast  — lightblue  */
        { Line1, 0xFFFF8800, 2.0f },   /* Fisher VC  — orange     */
    };
    for (auto& c : curves){
        GpPen* p=nullptr; GdipCreatePen1(c.color,c.width,UnitPixel,&p);
        float ox=0,oy=0; bool fst=true;
        for (int i=vs; i<=li; ++i){
            if (i<0||i>=count||std::isnan(c.buf[i])){ fst=true; continue; }
            float x = oriX+(i-vs)*stepX+stepX*0.5f;
            float y = toY(c.buf[i]);
            if (!fst) GdipDrawLine(g,p,ox,oy,x,y);
            ox=x; oy=y; fst=false;
        }
        GdipDeletePen(p);
    }

    /* ── Labels niveaux (dessinés après les courbes, par-dessus) ─── */
    SetBkMode(hDC,TRANSPARENT);
    SetTextColor(hDC,0x888888);
    DrawLevel(80.0, "80");
    DrawLevel(50.0, "50");
    DrawLevel(20.0, "20");

    /* ── Label indicateur + bouton X ────────────────────────────── */
    char lbl[48];
    if (panelCount > 1)
        std::snprintf(lbl,sizeof(lbl),"STEPFTVCPRDL #%d",panelIndex+1);
    else
        std::snprintf(lbl,sizeof(lbl),"STEPFTVCPRDL");
    SetTextColor(hDC,0x0044CC);
    TextOutA(hDC,(int)oriX+4,rTop+2,lbl,(int)std::strlen(lbl));
    SetTextColor(hDC,0);

    float bx = oriX+lenX-(float)closeBtnSz-2.0f;
    DrawCloseBtn(g,bx,(float)rTop+2.0f,(float)closeBtnSz);
}

//QCHART_REGISTER: Register_STEPFTVCPRDL
extern "C" void Register_STEPFTVCPRDL(IndicatorRegistry* reg) {
    if (reg->count >= MAX_INDICATORS) return;
    IndicatorDef* d = &reg->defs[reg->count++];
    std::strncpy(d->name,        "STEPFTVCPRDL", sizeof(d->name)-1);
    std::strncpy(d->labelPrefix, "SFTVPRDL",     sizeof(d->labelPrefix)-1);
    d->defaultPeriod = 20;
    d->defaultParam2 = 0;
    d->isPanel       = 1;
    d->drawOverlay   = nullptr;
    d->drawPanel     = STEPFTVCPRDL_DrawPanel;
}
