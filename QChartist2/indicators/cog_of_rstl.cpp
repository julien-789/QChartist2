/*
 * indicators/cog_of_rstl.cpp
 * COG of RSTL — Center of Gravity of the Regularized Smoothed Trend Line
 *
 * Pipeline :
 *   1. Filtre FIR 99 taps sur le close → RSTL
 *      closes[0]=plus ancien, closes[count-1]=plus récent
 *      Pour bar i, le filtre utilise closes[i-98..i] (98 bars d'historique)
 *   2. Régression polynomiale degré 2 sur une fenêtre de `period` bars → fx2
 *   3. Bandes résidu (sqh2/sql2) et stddev (stdh2/stdl2) × kstd
 *
 * Overlay sur le graphe prix.
 * period  = barsback   (défaut 240)
 * param2  = kstd × 10  (défaut 70 → kstd = 7.0)
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

/* ── Filtre FIR RSTL 99 taps ─────────────────────────────────────── */
static const double RSTL_COEFF[99] = {
    -0.00514293, -0.00398417, -0.00262594, -0.00107121,
     0.00066887,  0.00258172,  0.00465269,  0.00686394,
     0.00919334,  0.01161720,  0.01411056,  0.01664635,
     0.01919533,  0.02172747,  0.02421320,  0.02662203,
     0.02892446,  0.03109071,  0.03309496,  0.03490921,
     0.03651145,  0.03788045,  0.03899804,  0.03984915,
     0.04042329,  0.04071263,  0.04071263,  0.04042329,
     0.03984915,  0.03899804,  0.03788045,  0.03651145,
     0.03490921,  0.03309496,  0.03109071,  0.02892446,
     0.02662203,  0.02421320,  0.02172747,  0.01919533,
     0.01664635,  0.01411056,  0.01161720,  0.00919334,
     0.00686394,  0.00465269,  0.00258172,  0.00066887,
    -0.00107121, -0.00262594, -0.00398417, -0.00514293,
    -0.00609634, -0.00684602, -0.00739452, -0.00774847,
    -0.00791630, -0.00790940, -0.00774085, -0.00742482,
    -0.00697718, -0.00641613, -0.00576108, -0.00502957,
    -0.00423873, -0.00340812, -0.00255923, -0.00170217,
    -0.00085902, -0.00004113,  0.00073700,  0.00146422,
     0.00213007,  0.00272649,  0.00324752,  0.00368922,
     0.00405000,  0.00433024,  0.00453068,  0.00465046,
     0.00469058,  0.00466041,  0.00457855,  0.00442491,
     0.00423019,  0.00399201,  0.00372169,  0.00342736,
     0.00311822,  0.00280309,  0.00249088,  0.00219089,
     0.00191283,  0.00166683,  0.00146419,  0.00131867,
     0.00124645,  0.00126836, -0.00401854
};

/* ── Helpers GDI+ ────────────────────────────────────────────────── */
static void DrawCurve(GpGraphics* g, GpPen* pen,
    const double* buf, int count, int vs, int li,
    float oriX, float oriY, float stepX, double vMin, double scaleY)
{
    float ox=0,oy=0; bool fst=true;
    for (int i=vs; i<=li; ++i){
        if (i<0||i>=count||std::isnan(buf[i])){ fst=true; continue; }
        float x = oriX + (i-vs)*stepX + stepX*0.5f;
        float y = oriY - (float)((buf[i]-vMin)*scaleY);
        if (!fst) GdipDrawLine(g,pen,ox,oy,x,y);
        ox=x; oy=y; fst=false;
    }
}

static void FillBand(GpGraphics* g,
    const double* hi, const double* lo, int count, int vs, int li,
    float oriX, float oriY, float stepX, double vMin, double scaleY,
    unsigned int col)
{
    for (int i=vs; i<=li; ++i){
        if (i<0||i>=count||std::isnan(hi[i])||std::isnan(lo[i])) continue;
        float x  = oriX + (i-vs)*stepX;
        float yH = oriY - (float)((hi[i]-vMin)*scaleY);
        float yL = oriY - (float)((lo[i]-vMin)*scaleY);
        float h  = yL - yH; if (h<0.5f) h=0.5f;
        GpSolidFill* br=nullptr; GdipCreateSolidFill(col,&br);
        GdipFillRectangle(g,(GpBrush*)br,x,yH,stepX,h);
        GdipDeleteBrush(br);
    }
}

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

/* ── DrawOverlay ─────────────────────────────────────────────────── */
static void COG_DrawOverlay(
    GpGraphics* g, HDC hDC,
    const double* closes, const double* /*opens*/,
    const double* /*highs*/, const double* /*lows*/,
    const double* /*vol*/, const int* /*wd*/,
    int count, int period, int param2, int panelIndex,
    const ChartCtx* ctx, int closeBtnSz, const unsigned int* /*col*/)
{
    if (count > MAX_B) return;

    int    barsback = (period > 0) ? period : 240;
    double kstd     = (param2  > 0) ? param2 * 0.1 : 7.0;

    /* Besoin minimum : 98 bars pour le FIR + barsback pour la régression */
    if (count < 98 + barsback) return;

    float  oriX   = ctx->oriX;
    float  oriY   = ctx->oriY;
    float  stepX  = ctx->stepX;
    double vMin   = ctx->vMin;
    double scaleY = ctx->scaleY;
    int    vs     = ctx->viewStart;
    int    li     = ctx->lastIdx;

    /* ── Étape 1 : filtre FIR RSTL ──────────────────────────────────
     * closes[0]=plus ancien, closes[count-1]=plus récent
     * Pour bar i, on utilise closes[i-98..i]  (i >= 98)
     * rstl[i] est valide pour i = 98 .. count-1
     */
    static double rstl[MAX_B];
    for (int i=0; i<count; ++i) rstl[i] = NAN;
    for (int i=98; i<count; ++i){
        double s=0.0;
        for (int t=0; t<99; ++t)
            s += RSTL_COEFF[t] * closes[i-t];   /* coeff[0]*close[i], coeff[1]*close[i-1]... */
        rstl[i] = s;
    }

    /* ── Étape 2 : régression poly deg.2 sur la fenêtre
     * On prend les `barsback+1` dernières valeurs RSTL valides
     * i.e. rstl[count-1-barsback .. count-1]
     * On les indexe localement n=0..barsback  où n=0 → bar le plus ancien
     */
    int base = count - 1 - barsback;   /* premier bar de la fenêtre */
    if (base < 98) return;             /* pas assez d'historique FIR */

    int    p  = barsback;
    int    nn = 3;   /* deg 2 → 3 coefficients */

    /* sx[1..4] : sommes des puissances de n (1-based) */
    double sx[6]={0};
    sx[1] = (double)(p+1);
    for (int mi=1; mi<=nn*2-2; ++mi){
        double sum=0.0;
        for (int n=0; n<=p; ++n) sum += std::pow((double)n,(double)mi);
        sx[mi+1] = sum;
    }

    /* b[1..3] : sommes de rstl * n^(mi-1) */
    double b[4]={0};
    for (int mi=1; mi<=nn; ++mi){
        double sum=0.0;
        for (int n=0; n<=p; ++n){
            double rv = rstl[base+n];
            if (std::isnan(rv)) return;
            if (mi==1) sum += rv;
            else       sum += rv * std::pow((double)n,(double)(mi-1));
        }
        b[mi]=sum;
    }

    /* Matrice Vandermonde */
    double ai[4][4]={{0}};
    for (int jj=1;jj<=nn;++jj)
        for (int ii=1;ii<=nn;++ii)
            ai[ii][jj]=sx[ii+jj-1];

    /* Élimination de Gauss */
    for (int kk=1;kk<=nn-1;++kk){
        int ll=0; double mm=0.0;
        for (int ii=kk;ii<=nn;++ii)
            if (std::fabs(ai[ii][kk])>mm){ mm=std::fabs(ai[ii][kk]); ll=ii; }
        if (ll==0) return;
        if (ll!=kk){
            for (int jj=1;jj<=nn;++jj){ double t=ai[kk][jj]; ai[kk][jj]=ai[ll][jj]; ai[ll][jj]=t; }
            double t=b[kk]; b[kk]=b[ll]; b[ll]=t;
        }
        for (int ii=kk+1;ii<=nn;++ii){
            double qq=ai[ii][kk]/ai[kk][kk];
            for (int jj=1;jj<=nn;++jj)
                ai[ii][jj]=(jj==kk)?0.0:ai[ii][jj]-qq*ai[kk][jj];
            b[ii]-=qq*b[kk];
        }
    }
    double x[4]={0};
    x[nn]=b[nn]/ai[nn][nn];
    for (int ii=nn-1;ii>=1;--ii){
        double tt=0.0;
        for (int jj=1;jj<=nn-ii;++jj) tt+=ai[ii][ii+jj]*x[ii+jj];
        x[ii]=(b[ii]-tt)/ai[ii][ii];
    }

    /* fx2[n] = polynôme  (n=0=plus ancien dans la fenêtre) */
    static double fx2  [MAX_B];
    static double sqh2 [MAX_B];
    static double sql2 [MAX_B];
    static double stdh2[MAX_B];
    static double stdl2[MAX_B];
    for (int i=0;i<count;++i) fx2[i]=sqh2[i]=sql2[i]=stdh2[i]=stdl2[i]=NAN;

    for (int n=0;n<=p;++n)
        fx2[base+n] = x[1] + x[2]*(double)n + x[3]*(double)n*(double)n;

    /* sq = écart-type des résidus × kstd */
    double sq=0.0;
    for (int n=0;n<=p;++n)
        sq += (rstl[base+n]-fx2[base+n])*(rstl[base+n]-fx2[base+n]);
    sq = std::sqrt(sq/(p+1)) * kstd;

    /* std = stddev rolling du close sur la fenêtre × kstd */
    double sumc=0.0, sumc2=0.0;
    for (int n=0;n<=p;++n){ sumc+=closes[base+n]; sumc2+=closes[base+n]*closes[base+n]; }
    double meanc = sumc/(p+1);
    double varc  = sumc2/(p+1) - meanc*meanc;
    double stdc  = (varc>0.0) ? std::sqrt(varc)*kstd : 0.0;

    for (int n=0;n<=p;++n){
        sqh2 [base+n] = fx2[base+n] + sq;
        sql2 [base+n] = fx2[base+n] - sq;
        stdh2[base+n] = fx2[base+n] + stdc;
        stdl2[base+n] = fx2[base+n] - stdc;
    }

    /* ── Rendu ───────────────────────────────────────────────────── */
    FillBand(g,stdh2,stdl2,count,vs,li,oriX,oriY,stepX,vMin,scaleY,0x100044CC);
    FillBand(g,sqh2, sql2, count,vs,li,oriX,oriY,stepX,vMin,scaleY,0x1000AA44);

    GpPen* pSH=nullptr; GdipCreatePen1(0xFF0044CC,1.0f,UnitPixel,&pSH);
    DrawCurve(g,pSH,stdh2,count,vs,li,oriX,oriY,stepX,vMin,scaleY); GdipDeletePen(pSH);
    GpPen* pSL=nullptr; GdipCreatePen1(0xFF0044CC,1.0f,UnitPixel,&pSL);
    DrawCurve(g,pSL,stdl2,count,vs,li,oriX,oriY,stepX,vMin,scaleY); GdipDeletePen(pSL);

    GpPen* pQH=nullptr; GdipCreatePen1(0xFFCCCC00,1.2f,UnitPixel,&pQH);
    DrawCurve(g,pQH,sqh2,count,vs,li,oriX,oriY,stepX,vMin,scaleY); GdipDeletePen(pQH);
    GpPen* pQL=nullptr; GdipCreatePen1(0xFFCCCC00,1.2f,UnitPixel,&pQL);
    DrawCurve(g,pQL,sql2,count,vs,li,oriX,oriY,stepX,vMin,scaleY); GdipDeletePen(pQL);

    GpPen* pF=nullptr; GdipCreatePen1(0xFF00AADD,2.0f,UnitPixel,&pF);
    DrawCurve(g,pF,fx2,count,vs,li,oriX,oriY,stepX,vMin,scaleY); GdipDeletePen(pF);

    /* Label + bouton X */
    char lbl[48];
    std::snprintf(lbl,sizeof(lbl),"COG-RSTL(%d,%.1f)",barsback,kstd);
    int lblX=(int)oriX+4;
    int lblY=28+14+panelIndex*(closeBtnSz+4);
    SetBkMode(hDC,TRANSPARENT);
    SetTextColor(hDC,0xDD8800);
    TextOutA(hDC,lblX,lblY,lbl,(int)std::strlen(lbl));
    SetTextColor(hDC,0);
    float btnX=(float)(lblX+(int)std::strlen(lbl)*7+3);
    DrawCloseBtn(g,btnX,(float)(lblY-1),(float)closeBtnSz);
}

//QCHART_REGISTER: Register_COG_RSTL
extern "C" void Register_COG_RSTL(IndicatorRegistry* reg) {
    if (reg->count >= MAX_INDICATORS) return;
    IndicatorDef* d = &reg->defs[reg->count++];
    std::strncpy(d->name,        "COG of RSTL", sizeof(d->name)-1);
    std::strncpy(d->labelPrefix, "COG-RSTL",    sizeof(d->labelPrefix)-1);
    std::strncpy(d->param2Label, "kstd(x10)",   sizeof(d->param2Label)-1);
    d->defaultPeriod = 240;
    d->defaultParam2 = 70;
    d->isPanel       = 0;
    d->drawOverlay   = COG_DrawOverlay;
    d->drawPanel     = nullptr;
}
