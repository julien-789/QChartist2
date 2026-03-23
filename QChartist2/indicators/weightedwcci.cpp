/*
 * indicators/weightedwcci.cpp
 * Weighted WCCI — panel séparé.
 *
 * Algorithme (fidèle au Pine Script) :
 *   TCCI  = CCI(hlc3, TCCIp)
 *   CCI   = CCI(hlc3, CCIp)
 *   Kw    = weight * (ATR(7) / ATR(49))
 *   TCCI *= Kw,  CCI *= Kw
 *   Clamp à ±(overbslevel+50)
 *
 * Niveaux fixes : ±overbslevel, ±triglevel, 0
 *
 * period = CCIp (défaut 13)
 * param2 = TCCIp (défaut 7)
 * overbslevel = 200, triglevel = 50, weight = 1.0 (codés)
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

/* ── CCI sur hlc3 ────────────────────────────────────────────────────── */
static double CalcCCI(const double* hlc3, int i, int n, int count)
{
    if (i < n-1 || i >= count) return 0.0;
    /* SMA du typical price */
    double sum=0;
    for (int k=0;k<n;++k) sum+=hlc3[i-k];
    double ma=sum/n;
    /* Mean Deviation */
    double md=0;
    for (int k=0;k<n;++k) md+=fabs(hlc3[i-k]-ma);
    md/=n;
    return (md>0) ? (hlc3[i]-ma)/(0.015*md) : 0.0;
}

/* ── ATR ─────────────────────────────────────────────────────────────── */
static double CalcATR(const double* closes, const double* highs,
                      const double* lows, int i, int n, int count)
{
    if (i < n || i >= count) return 1.0;
    double sum=0;
    for (int k=0;k<n;++k){
        int j=i-k;
        double tr=highs[j]-lows[j];
        if (j>0){
            double h=fabs(highs[j]-closes[j-1]);
            double l=fabs(lows[j] -closes[j-1]);
            if (h>tr) tr=h;
            if (l>tr) tr=l;
        }
        sum+=tr;
    }
    return sum/n;
}

/* ── Helper bouton X ─────────────────────────────────────────────────── */
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

/* ── Callback DrawPanel ──────────────────────────────────────────────── */
static void WCCI_DrawPanel(
    GpGraphics*     g,
    HDC             hDC,
    const double*   closes,
    const double*   opens,
    const double*   highs,
    const double*   lows,
    const double*   /*volumes*/,
    const int*      /*weekdays*/,
    int             count,
    int             period,   /* CCIp  */
    int             param2,   /* TCCIp */
    int             panelIndex,
    int             panelCount,
    const ChartCtx* ctx,
    int             panelH,
    int             panelGap,
    int             closeBtnSz,
    double*         outVMin,
    double*         outVMax)
{
    int CCIp  = (period>0) ? period : 13;
    int TCCIp = (param2>0) ? param2 : 7;

    const double overbslevel = 200.0;
    const double triglevel   =  50.0;
    const double weight      =   1.0;
    const double clamp       = overbslevel + 50.0;

    double vMin = -(overbslevel+60), vMax = overbslevel+60;
    if (outVMin) *outVMin = vMin;
    if (outVMax) *outVMax = vMax;

    float oriX        = ctx->oriX;
    float stepX       = ctx->stepX;
    float lenX        = ctx->lenX;
    int   mainChartH  = ctx->mainChartH;
    int   panelInnerH = panelH - 20;
    int   rTop        = mainChartH + panelIndex*(panelH+panelGap);
    int   rBottom     = rTop + panelInnerH;
    int   vs          = ctx->viewStart;
    int   li          = ctx->lastIdx;

    if (count>MAX_B||count<CCIp) return;

    /* ── hlc3 ────────────────────────────────────────────────────────── */
    static double hlc3[MAX_B];
    for (int i=0;i<count;++i)
        hlc3[i]=(highs[i]+lows[i]+closes[i])/3.0;

    /* ── Calcul CCI, TCCI, ATR ───────────────────────────────────────── */
    static double cciBuf [MAX_B];
    static double tcciBuf[MAX_B];

    for (int i=0;i<count;++i){
        double cci  = CalcCCI(hlc3,i,CCIp, count);
        double tcci = CalcCCI(hlc3,i,TCCIp,count);
        double atr7 = CalcATR(closes,highs,lows,i, 7,count);
        double atr49= CalcATR(closes,highs,lows,i,49,count);
        double kw   = (atr49>0) ? weight*(atr7/atr49) : 0.0;
        cci  *= kw;
        tcci *= kw;
        if (cci  >  clamp) cci  =  clamp;
        if (cci  < -clamp) cci  = -clamp;
        if (tcci >  clamp) tcci =  clamp;
        if (tcci < -clamp) tcci = -clamp;
        cciBuf [i] = cci;
        tcciBuf[i] = tcci;
    }

    /* ── Conversion valeur → pixel Y ────────────────────────────────── */
    auto yPx = [&](double v) -> float {
        return (float)rBottom - (float)((v-vMin)/(vMax-vMin))*panelInnerH;
    };

    /* ── Cadre ───────────────────────────────────────────────────────── */
    GpPen* pG=nullptr; GdipCreatePen1(0xFFCCCCCC,1.0f,UnitPixel,&pG);
    GdipDrawRectangleI(g,pG,(int)oriX,rTop,(int)lenX,panelInnerH);
    GdipDeletePen(pG);

    /* ── Niveaux horizontaux ─────────────────────────────────────────── */
    struct { double v; unsigned int col; GpDashStyle dash; } levels[]={
        { overbslevel, 0xFFFF0000, DashStyleDash },   /* rouge */
        {-overbslevel, 0xFFFF0000, DashStyleDash },
        { triglevel,   0xFF4169E1, DashStyleDash },   /* RoyalBlue */
        {-triglevel,   0xFF4169E1, DashStyleDash },
        { 0.0,         0xFF98FB98, DashStyleSolid},   /* PaleGreen */
    };
    for (auto& lv : levels){
        float y=yPx(lv.v);
        GpPen* p=nullptr; GdipCreatePen1(lv.col,1.0f,UnitPixel,&p);
        GdipSetPenDashStyle(p,lv.dash);
        GdipDrawLine(g,p,oriX,y,oriX+lenX,y);
        GdipDeletePen(p);
    }
    /* Labels niveaux */
    SetBkMode(hDC,TRANSPARENT); SetTextColor(hDC,0x888888);
    char lvlTxt[8];
    std::snprintf(lvlTxt,sizeof(lvlTxt),"%.0f",overbslevel);
    TextOutA(hDC,(int)oriX-28,(int)yPx( overbslevel)-7,lvlTxt,(int)strlen(lvlTxt));
    TextOutA(hDC,(int)oriX-28,(int)yPx(-overbslevel)-7,lvlTxt,(int)strlen(lvlTxt));

    /* ── Histogramme CCI (CadetBlue, style colonnes) ─────────────────── */
    float yZero = yPx(0.0);
    for (int i=vs;i<=li;++i){
        if (i<0||i>=count) continue;
        float x  = oriX+(i-vs)*stepX;
        float bw = stepX>1?stepX-0.5f:stepX;
        float y  = yPx(cciBuf[i]);
        float top,bot;
        if (cciBuf[i]>=0){top=y;    bot=yZero;}
        else             {top=yZero;bot=y;}
        float h=bot-top; if(h<0.5f)h=0.5f;
        unsigned int col=(cciBuf[i]>=0)?0x605F9EA0:0x40CC4444; /* CadetBlue/rouge clair */
        GpSolidFill* br=nullptr; GdipCreateSolidFill(col,&br);
        GdipFillRectangle(g,(GpBrush*)br,x,top,bw,h);
        GdipDeleteBrush(br);
    }

    /* ── Ligne CCI (DodgerBlue, épaisse) ────────────────────────────── */
    {
        GpPen* p=nullptr; GdipCreatePen1(0xFF1E90FF,2.5f,UnitPixel,&p);
        float ox=0,oy=0; bool fst=true;
        for (int i=vs;i<=li;++i){
            if (i<0||i>=count){fst=true;continue;}
            float x=oriX+(i-vs)*stepX+stepX*0.5f;
            float y=yPx(cciBuf[i]);
            if (!fst) GdipDrawLine(g,p,ox,oy,x,y);
            ox=x;oy=y;fst=false;
        }
        GdipDeletePen(p);
    }

    /* ── Ligne Turbo CCI (rouge, fine) ──────────────────────────────── */
    {
        GpPen* p=nullptr; GdipCreatePen1(0xFFFF0000,1.2f,UnitPixel,&p);
        float ox=0,oy=0; bool fst=true;
        for (int i=vs;i<=li;++i){
            if (i<0||i>=count){fst=true;continue;}
            float x=oriX+(i-vs)*stepX+stepX*0.5f;
            float y=yPx(tcciBuf[i]);
            if (!fst) GdipDrawLine(g,p,ox,oy,x,y);
            ox=x;oy=y;fst=false;
        }
        GdipDeletePen(p);
    }

    /* ── Label + bouton X ────────────────────────────────────────────── */
    char lbl[48];
    if (panelCount>1) std::snprintf(lbl,sizeof(lbl),"WCCI(%d,%d) #%d",CCIp,TCCIp,panelIndex+1);
    else              std::snprintf(lbl,sizeof(lbl),"WCCI(%d,%d)",CCIp,TCCIp);
    SetTextColor(hDC,0x1E90FF);
    TextOutA(hDC,(int)oriX-55,rTop+2,lbl,(int)std::strlen(lbl));
    SetTextColor(hDC,0);
    float bxBtn=oriX+lenX-(float)closeBtnSz-2.0f;
    DrawCloseBtn(g,bxBtn,(float)rTop+2.0f,(float)closeBtnSz);
}

/* ── Enregistrement ──────────────────────────────────────────────────── */
//QCHART_REGISTER: Register_WeightedWCCI
extern "C" void Register_WeightedWCCI(IndicatorRegistry* reg) {
    if (reg->count>=MAX_INDICATORS) return;
    IndicatorDef* d=&reg->defs[reg->count++];
    std::strncpy(d->name,       "Weighted WCCI", sizeof(d->name)-1);
    std::strncpy(d->labelPrefix,"WCCI",          sizeof(d->labelPrefix)-1);
    std::strncpy(d->param2Label,"Turbo Period",  sizeof(d->param2Label)-1);
    d->defaultPeriod = 13;   /* CCIp  */
    d->defaultParam2 = 7;    /* TCCIp */
    d->isPanel       = 1;
    d->drawOverlay   = nullptr;
    d->drawPanel     = WCCI_DrawPanel;
}
