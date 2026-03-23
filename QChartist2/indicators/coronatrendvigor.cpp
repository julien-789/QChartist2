/*
 * indicators/coronatrendvigor.cpp
 * Corona Trend Vigor v2.1 — panel séparé.
 *
 * Algorithme (fidèle au Pine Script de référence) :
 *   1. HP  = high-pass filter (alpha1 basé sur période 30)
 *   2. SmoothHP = lissage 6 barres de HP
 *   3. DFT sur n=11..59 → amplitude spectrale → Dominant Cycle (DC)
 *   4. Bandpass filter (IP) sur DC → Ampl2
 *   5. Trend amplitude = (price - price[DC]) / Ampl2 → Ratio
 *   6. mTV = 0.05*(Ratio+10) clampé [0,1]
 *   7. TV_value = 20*mTV - 10  (affiché sur [-10,+10])
 *
 * param2 = PriceMode (0=Close,1=Open,2=High,3=Low,4=Median,5=Typical,6=WClose)
 *          défaut 4 (Median = (H+L)/2)
 *
 * outVMin = -12, outVMax = +12 (fixe, niveaux ±2 visibles)
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
static const double PI = 3.14159265358979323846;

/* ── Sélection du prix selon PriceMode ───────────────────────────────── */
static double GetPrice(const double* closes, const double* highs,
                       const double* lows, const double* opens,
                       int i, int mode)
{
    switch (mode) {
        case 0: return closes[i];
        case 1: return opens[i];
        case 2: return highs[i];
        case 3: return lows[i];
        case 4: return (highs[i] + lows[i]) * 0.5;
        case 5: return (highs[i] + lows[i] + closes[i]) / 3.0;
        case 6: return (highs[i] + lows[i] + closes[i]*2.0) * 0.25;
        default: return closes[i];
    }
}

/* ── Médiane sur un tableau ──────────────────────────────────────────── */
static double Median5(double a, double b, double c, double d, double e)
{
    double arr[5] = {a,b,c,d,e};
    /* tri à bulles simple sur 5 éléments */
    for (int p=0;p<4;++p)
        for (int q=0;q<4-p;++q)
            if (arr[q]>arr[q+1]){double t=arr[q];arr[q]=arr[q+1];arr[q+1]=t;}
    return arr[2];
}

/* ── Calcul des buffers TV et Corona ─────────────────────────────────── */
static void CalcCTV(
    const double* closes, const double* highs,
    const double* lows,   const double* opens,
    int count, int priceMode,
    double* tvBuf,      /* TV_value [-10,+10] */
    double* coronaBuf)  /* avg_raster [0,20] */
{
    for (int i=0;i<count;++i) tvBuf[i]=coronaBuf[i]=NAN;
    if (count < 70) return;

    /* Buffers DFT (n=0..59) */
    double Q[60]={}, I_[60]={}, Real_[60]={}, Imag_[60]={};
    double Ampl[60]={}, DB[60]={};
    double OldI[60]={}, OlderI[60]={};
    double OldQ[60]={}, OlderQ[60]={};
    double OldReal[60]={}, OlderReal[60]={};
    double OldImag[60]={}, OlderImag[60]={};
    double OldDB[60]={};
    double Raster[51]={}, OldRaster[51]={};

    double alpha1 = (1.0 - sin(2.0*PI/30.0)) / cos(2.0*PI/30.0);

    /* État persistent barre par barre */
    double HP=0, prevHP=0, prev2HP=0, prev3HP=0, prev4HP=0, prev5HP=0;
    double SmoothHP=0;
    double DC_arr[MAX_B]={};
    double prevIP=0, prev2IP=0;
    double prevRatio=0;

    for (int y=0; y<count; ++y) {
        double price  = GetPrice(closes,highs,lows,opens, y, priceMode);
        double pricep = (y>0) ? GetPrice(closes,highs,lows,opens, y-1, priceMode) : price;

        /* HP filter */
        double curHP = 0.5*(1.0+alpha1)*(price - pricep) + alpha1*prevHP;

        /* SmoothHP */
        double curSHP;
        if (y == 0)
            curSHP = 0.0;
        else if (y < 5)
            curSHP = price - pricep;
        else
            curSHP = (curHP + 2.0*prevHP + 3.0*prev2HP + 3.0*prev3HP
                      + 2.0*prev4HP + prev5HP) / 12.0;

        /* Shift HP history */
        prev5HP=prev4HP; prev4HP=prev3HP; prev3HP=prev2HP;
        prev2HP=prevHP;  prevHP=curHP;
        SmoothHP = curSHP;

        /* delta for DFT */
        double delta = -0.015*(y+1) + 0.5;
        if (delta < 0.1) delta = 0.1;

        /* DFT loop n=11..59 */
        if (y > 11) {
            for (int n=11;n<60;++n) {
                OlderI[n]=OldI[n];   OldI[n]=I_[n];
                OlderQ[n]=OldQ[n];   OldQ[n]=Q[n];
                OlderReal[n]=OldReal[n]; OldReal[n]=Real_[n];
                OlderImag[n]=OldImag[n]; OldImag[n]=Imag_[n];
                OldDB[n]=DB[n];

                double beta  = cos(4.0*PI/(n+1));
                double gamma = 1.0/cos(4.0*PI*delta/(n+1));
                double alpha = gamma - sqrt(gamma*gamma - 1.0);

                /* SmoothHP des barres précédentes */
                /* On utilise SmoothHP courant comme SHP[y] */
                /* SHP[y-1] = la valeur stockée au tour précédent */
                /* Approx : on recalcule depuis HP history — simplifié */
                double shp  = SmoothHP;
                /* Pour shp[y-1] et shp[y-2] on utilise prevSHP */
                /* Stocké dans OldI avant shift */
                double shpM1 = OldI[n];   /* approximation : I était SmoothHP */
                double shpM2 = OlderI[n];

                Q[n]     = ((n+1)/(4.0*PI)) * (shp - shpM1);
                I_[n]    = shp;
                Real_[n] = 0.5*(1-alpha)*(I_[n]-OlderI[n])
                         + beta*(1+alpha)*OldReal[n] - alpha*OlderReal[n];
                Imag_[n] = 0.5*(1-alpha)*(Q[n]-OlderQ[n])
                         + beta*(1+alpha)*OldImag[n] - alpha*OlderImag[n];
                Ampl[n]  = Real_[n]*Real_[n] + Imag_[n]*Imag_[n];
            }

            /* MaxAmpl */
            double MaxAmpl = Ampl[11];
            for (int n=12;n<60;++n)
                if (Ampl[n]>MaxAmpl) MaxAmpl=Ampl[n];

            /* DB */
            for (int n=11;n<60;++n) {
                double dbc=0;
                if (MaxAmpl!=0 && Ampl[n]/MaxAmpl > 0)
                    dbc = -10.0*log10(0.01/(1.0 - 0.99*Ampl[n]/MaxAmpl));
                DB[n] = 0.33*dbc + 0.67*OldDB[n];
                if (DB[n]>20) DB[n]=20.0;
            }

            /* Dominant Cycle */
            double Num=0, Denom=0;
            for (int n=11;n<60;++n) {
                if (DB[n]<=6) {
                    Num   += (n+1)*(20.0-DB[n]);
                    Denom += 20.0-DB[n];
                }
            }
            double DC = (Denom!=0) ? 0.5*Num/Denom
                      : (y>0 ? DC_arr[y-1] : 0.0);
            DC_arr[y] = DC;
        } else {
            DC_arr[y] = (y>0) ? DC_arr[y-1] : 0.0;
        }

        /* Médiane DC sur 5 barres */
        double mDC = DC_arr[y];
        if (y >= 4)
            mDC = Median5(DC_arr[y],DC_arr[y-1],DC_arr[y-2],DC_arr[y-3],DC_arr[y-4]);
        if (mDC < 6) mDC = 6.0;

        /* Bandpass filter IP */
        double delta1 = 0.1;
        double beta1  = cos(2.0*PI/mDC);
        double gamma1 = 1.0/cos(4.0*PI*delta1/mDC);
        double alpha2 = gamma1 - sqrt(gamma1*gamma1 - 1.0);
        double pricep2 = (y>1) ? GetPrice(closes,highs,lows,opens,y-2,priceMode) : price;
        double curIP = 0.5*(1-alpha2)*(price - pricep2)
                     + beta1*(1+alpha2)*prevIP - alpha2*prev2IP;
        prev2IP=prevIP; prevIP=curIP;

        /* Quadrature et amplitude cycle */
        double prevIPv = (y>0) ? prevIP : 0.0;
        double Q1   = (mDC/(2.0*PI)) * (curIP - prevIPv);
        double Ampl2= sqrt(curIP*curIP + Q1*Q1);

        /* Trend Ratio */
        int iDC = (int)round(mDC);
        double priceOld = (y > iDC) ? GetPrice(closes,highs,lows,opens,y-iDC-1,priceMode) : price;
        double trend = price - priceOld;
        double Ratio = prevRatio;
        if (trend!=0 && Ampl2!=0)
            Ratio = 0.33*trend/Ampl2 + 0.67*prevRatio;
        if (Ratio >  10) Ratio =  10.0;
        if (Ratio < -10) Ratio = -10.0;
        prevRatio = Ratio;

        /* mTV */
        double mTV = 0.05*(Ratio + 10.0);
        if (mTV<0) mTV=0; if (mTV>1) mTV=1;

        tvBuf[y] = 20.0*mTV - 10.0;

        /* Raster / Corona */
        double Width = 0.01;
        if (mTV>=0.3 && mTV<0.5)       Width = mTV - 0.3;
        else if (mTV>0.5 && mTV<=0.7)  Width = -mTV + 0.7;

        double avgR = 0.0;
        for (int n=1;n<=50;++n) {
            double rn = 20.0;
            int mid = (int)round(50.0*mTV);
            if (n < mid) {
                double base = (Width!=0) ? (20.0*mTV - 0.4*n)/Width : 0.0;
                if (base<0) base=0;
                rn = 0.8*(pow(base,0.85) + 0.2*OldRaster[n]);
            } else if (n > mid) {
                double base = (Width!=0) ? (-20.0*mTV + 0.4*n)/Width : 0.0;
                if (base<0) base=0;
                rn = 0.8*(pow(base,0.85) + 0.2*OldRaster[n]);
            } else {
                rn = 0.5*OldRaster[n];
            }
            if (rn<0) rn=0;
            if (rn>20 || mTV<0.3 || mTV>0.7) rn=20.0;
            Raster[n]=rn; OldRaster[n]=rn;
            avgR += rn;
        }
        coronaBuf[y] = avgR / 50.0;
    }
}

/* ── Helper bouton X ──────────────────────────────────────────────────── */
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

/* ── Callback DrawPanel ───────────────────────────────────────────────── */
static void CTV_DrawPanel(
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
    if (count > MAX_B || count < 70) return;

    int priceMode = (param2 >= 0 && param2 <= 10) ? param2 : 4;

    float oriX       = ctx->oriX;
    float stepX      = ctx->stepX;
    float lenX       = ctx->lenX;
    int   mainChartH = ctx->mainChartH;
    int   panelInnerH = panelH - 20;
    int   rTop    = mainChartH + panelIndex * (panelH + panelGap);
    int   rBottom = rTop + panelInnerH;
    int   vs      = ctx->viewStart;
    int   li      = ctx->lastIdx;

    double vMin = -12.0, vMax = 12.0;
    if (outVMin) *outVMin = vMin;
    if (outVMax) *outVMax = vMax;

    /* ── Calcul ───────────────────────────────────────────────────────── */
    static double tvBuf    [MAX_B];
    static double coronaBuf[MAX_B];
    CalcCTV(closes, highs, lows, opens, count, priceMode, tvBuf, coronaBuf);

    /* ── Cadre ────────────────────────────────────────────────────────── */
    GpPen* pG=nullptr; GdipCreatePen1(0xFFCCCCCC,1.0f,UnitPixel,&pG);
    GdipDrawRectangleI(g,pG,(int)oriX,rTop,(int)lenX,panelInnerH);

    /* Niveaux ±2 et 0 */
    auto yLevel = [&](double val) -> float {
        return (float)rBottom - (float)((val-vMin)/(vMax-vMin))*panelInnerH;
    };
    float yZero = yLevel(0.0);
    float yP2   = yLevel(2.0);
    float yM2   = yLevel(-2.0);
    GdipSetPenDashStyle(pG,(GpDashStyle)1);
    GdipDrawLine(g,pG,oriX,yZero,oriX+lenX,yZero);
    GdipDrawLine(g,pG,oriX,yP2, oriX+lenX,yP2);
    GdipDrawLine(g,pG,oriX,yM2, oriX+lenX,yM2);
    GdipDeletePen(pG);

    /* Labels niveaux */
    SetBkMode(hDC,TRANSPARENT); SetTextColor(hDC,0x888888);
    TextOutA(hDC,(int)oriX-20,(int)yP2-7," +2",3);
    TextOutA(hDC,(int)oriX-20,(int)yM2-7," -2",3);
    TextOutA(hDC,(int)oriX-20,(int)yZero-7,"  0",3);

    /* ── Corona (histogramme coloré) ──────────────────────────────────── */
    for (int i=vs;i<=li;++i) {
        if (i<0||i>=count||std::isnan(coronaBuf[i])) continue;
        double avg = coronaBuf[i];
        /* Couleur selon intensité (bleu→cyan→fuzz) */
        int r,g2,b;
        if (avg<=10.0) {
            r  = (int)(0   + avg*( 0  -0  )/10.0);
            g2 = (int)(0   + avg*( 0  -0  )/10.0);
            b  = (int)(255 + avg*(255-255)/10.0);
        } else {
            r  = (int)(0   * (2.0-avg/10.0));
            g2 = (int)(0   * (2.0-avg/10.0));
            b  = (int)(255 * (2.0-avg/10.0));
        }
        if (r<0)r=0; if (r>255)r=255;
        if (g2<0)g2=0; if (g2>255)g2=255;
        if (b<0)b=0; if (b>255)b=255;
        unsigned int col = 0x80000000u|((unsigned)r<<16)|((unsigned)g2<<8)|(unsigned)b;

        float x  = oriX+(i-vs)*stepX;
        float bw = stepX>1?stepX-0.5f:stepX;
        /* Colonne de yZero vers le bas (à 0) */
        GpSolidFill* brC=nullptr; GdipCreateSolidFill(col,&brC);
        GdipFillRectangle(g,(GpBrush*)brC,x,yZero,bw,3.0f);
        GdipDeleteBrush(brC);
    }

    /* ── Ligne TV ─────────────────────────────────────────────────────── */
    GpPen* pTV=nullptr; GdipCreatePen1(0xFF0000FF,2.0f,UnitPixel,&pTV);
    float ox=0,oy=0; bool fst=true;
    for (int i=vs;i<=li;++i){
        if (i<0||i>=count||std::isnan(tvBuf[i])){fst=true;continue;}
        float x=oriX+(i-vs)*stepX+stepX*0.5f;
        float y=yLevel(tvBuf[i]);
        if (y<(float)rTop)y=(float)rTop;
        if (y>(float)rBottom)y=(float)rBottom;
        if (!fst) GdipDrawLine(g,pTV,ox,oy,x,y);
        ox=x;oy=y;fst=false;
    }
    GdipDeletePen(pTV);

    /* ── Label + bouton X ────────────────────────────────────────────── */
    char lbl[48];
    const char* pmNames[]={"C","O","H","L","HL2","HLC3","WC","HAC","HAO","HAH","HAL"};
    const char* pm = (priceMode>=0&&priceMode<=10)?pmNames[priceMode]:"HL2";
    if (panelCount>1) std::snprintf(lbl,sizeof(lbl),"CTV(%s) #%d",pm,panelIndex+1);
    else              std::snprintf(lbl,sizeof(lbl),"CTV(%s)",pm);
    SetTextColor(hDC,0x0000FF);
    TextOutA(hDC,(int)oriX-55,rTop+2,lbl,(int)std::strlen(lbl));
    SetTextColor(hDC,0);
    float bxBtn=oriX+lenX-(float)closeBtnSz-2.0f;
    DrawCloseBtn(g,bxBtn,(float)rTop+2.0f,(float)closeBtnSz);
}

/* ── Enregistrement ───────────────────────────────────────────────────── */
//QCHART_REGISTER: Register_CoronaTrendVigor
extern "C" void Register_CoronaTrendVigor(IndicatorRegistry* reg) {
    if (reg->count>=MAX_INDICATORS) return;
    IndicatorDef* d=&reg->defs[reg->count++];
    std::strncpy(d->name,       "Corona Trend Vigor", sizeof(d->name)-1);
    std::strncpy(d->labelPrefix,"CTV",               sizeof(d->labelPrefix)-1);
    std::strncpy(d->param2Label,"PriceMode(0-6)",    sizeof(d->param2Label)-1);
    d->defaultPeriod = 30;
    d->defaultParam2 = 4;   /* Median = (H+L)/2 */
    d->isPanel       = 1;
    d->drawOverlay   = nullptr;
    d->drawPanel     = CTV_DrawPanel;
}
