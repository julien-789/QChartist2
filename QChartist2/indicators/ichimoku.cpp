/*
 * indicators/ichimoku.cpp
 * Ichimoku Kinko Hyo — overlay.
 *
 * Algorithme fidèle au Pine Script de référence :
 *   Tenkan  = (Highest(9) + Lowest(9)) / 2
 *   Kijun   = (Highest(26) + Lowest(26)) / 2
 *   Chikou  = close affiché 26 barres en arrière  → chikouBuf[i-26] = close[i]
 *   SenkouA = (Highest(52) + Lowest(52)) / 2  affiché 26 barres en avant → spanABuf[i+26]
 *   SenkouB = (Tenkan[i-26] + Kijun[i-26]) / 2  affiché sur la barre i courante
 *
 * period = tenkan (défaut 9), param2 = kijun/displacement (défaut 26)
 * senkou = kijun * 2 (défaut 52)
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

static double HH(const double* h, int i, int n, int count)
{
    double mx=-1e30;
    for (int k=0;k<n;++k){ int j=i-k; if(j<0||j>=count)continue; if(h[j]>mx)mx=h[j]; }
    return mx;
}
static double LL(const double* l, int i, int n, int count)
{
    double mn=1e30;
    for (int k=0;k<n;++k){ int j=i-k; if(j<0||j>=count)continue; if(l[j]<mn)mn=l[j]; }
    return mn;
}
static double Donchian(const double* h, const double* l, int i, int n, int count)
{
    if (i<n-1) return NAN;
    return (HH(h,i,n,count) + LL(l,i,n,count)) * 0.5;
}

static void DrawLine(GpGraphics* g, GpPen* pen,
    const double* buf, int count, int vs, int li,
    float oriX, float oriY, float stepX, double vMin, double scaleY)
{
    float ox=0,oy=0; bool fst=true;
    for (int i=vs;i<=li;++i){
        if (i<0||i>=count||std::isnan(buf[i])){fst=true;continue;}
        float x=oriX+(i-vs)*stepX+stepX*0.5f;
        float y=oriY-(float)((buf[i]-vMin)*scaleY);
        if (!fst) GdipDrawLine(g,pen,ox,oy,x,y);
        ox=x;oy=y;fst=false;
    }
}

static void FillKumo(GpGraphics* g,
    const double* a, const double* b, int count, int vs, int li,
    float oriX, float oriY, float stepX, double vMin, double scaleY)
{
    for (int i=vs;i<=li;++i){
        if (i<0||i>=count||std::isnan(a[i])||std::isnan(b[i])) continue;
        float x  = oriX+(i-vs)*stepX;
        float yA = oriY-(float)((a[i]-vMin)*scaleY);
        float yB = oriY-(float)((b[i]-vMin)*scaleY);
        float top=(yA<yB)?yA:yB, bot=(yA>yB)?yA:yB;
        float h=bot-top; if(h<0.5f)h=0.5f;
        unsigned int col=(a[i]>=b[i])?0x2000AA00:0x20CC0000;
        GpSolidFill* br=nullptr; GdipCreateSolidFill(col,&br);
        GdipFillRectangle(g,(GpBrush*)br,x,top,stepX,h);
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

static void Ichi_DrawOverlay(
    GpGraphics* g, HDC hDC,
    const double* closes, const double* opens,
    const double* highs,  const double* lows,
    const double* /*vol*/, const int* /*wd*/,
    int count, int period, int param2, int panelIndex,
    const ChartCtx* ctx, int closeBtnSz, const unsigned int* /*col*/)
{
    if (count>MAX_B) return;

    int tenkan = (period>0) ? period : 9;
    int kijun  = (param2>0) ? param2 : 26;
    int disp   = kijun;          /* displacement = kijun */
    int senkou = kijun * 2;      /* laggingSpan2Periods  */

    float  oriX=ctx->oriX, oriY=ctx->oriY, stepX=ctx->stepX, lenX=ctx->lenX;
    double vMin=ctx->vMin, scaleY=ctx->scaleY;
    int    vs=ctx->viewStart, li=ctx->lastIdx;

    static double tenkanBuf[MAX_B];
    static double kijunBuf [MAX_B];
    static double chikouBuf[MAX_B];  /* close décalé -disp */
    static double spanABuf [MAX_B];  /* Donchian(senkou) décalé +disp */
    static double spanBBuf [MAX_B];  /* (Tenkan[i-disp]+Kijun[i-disp])/2 */

    for (int i=0;i<count;++i)
        tenkanBuf[i]=kijunBuf[i]=chikouBuf[i]=spanABuf[i]=spanBBuf[i]=NAN;

    for (int i=0;i<count;++i){

        /* Tenkan-sen */
        tenkanBuf[i] = Donchian(highs,lows,i,tenkan,count);

        /* Kijun-sen */
        kijunBuf[i]  = Donchian(highs,lows,i,kijun,count);

        /* Chikou Span : close[i] affiché à i-disp */
        if (i-disp >= 0)
            chikouBuf[i-disp] = closes[i];

        /* Senkou Span A : Donchian(senkou) affiché à i+disp
         * Pine: SenkouA = middleDonchian(52), plot with offset=+displacement */
        double sA = Donchian(highs,lows,i,senkou,count);
        if (!std::isnan(sA) && i+disp < count)
            spanABuf[i+disp] = sA;

        /* Senkou Span B : (Tenkan[i-disp] + Kijun[i-disp]) / 2
         * Pine: SenkouB = (Tenkan[basePeriods] + Kijun[basePeriods]) / 2
         * = valeurs de Tenkan/Kijun d'il y a `disp` barres, sur la barre i */
        int past = i - disp;
        if (past >= 0 && !std::isnan(tenkanBuf[past]) && !std::isnan(kijunBuf[past]))
            spanBBuf[i] = (tenkanBuf[past] + kijunBuf[past]) * 0.5;
    }

    /* ── Rendu ───────────────────────────────────────────────────────── */

    /* Kumo (rempli entre SpanA et SpanB) */
    FillKumo(g,spanABuf,spanBBuf,count,vs,li,oriX,oriY,stepX,vMin,scaleY);

    /* SpanA : purple */
    GpPen* pA=nullptr; GdipCreatePen1(0xFF9900CC,1.2f,UnitPixel,&pA);
    DrawLine(g,pA,spanABuf,count,vs,li,oriX,oriY,stepX,vMin,scaleY);
    GdipDeletePen(pA);

    /* SpanB : vert */
    GpPen* pB=nullptr; GdipCreatePen1(0xFF00AA00,1.2f,UnitPixel,&pB);
    DrawLine(g,pB,spanBBuf,count,vs,li,oriX,oriY,stepX,vMin,scaleY);
    GdipDeletePen(pB);

    /* Kijun-sen : bleu */
    GpPen* pK=nullptr; GdipCreatePen1(0xFF0044CC,1.5f,UnitPixel,&pK);
    DrawLine(g,pK,kijunBuf,count,vs,li,oriX,oriY,stepX,vMin,scaleY);
    GdipDeletePen(pK);

    /* Tenkan-sen : rouge */
    GpPen* pT=nullptr; GdipCreatePen1(0xFFCC0000,1.5f,UnitPixel,&pT);
    DrawLine(g,pT,tenkanBuf,count,vs,li,oriX,oriY,stepX,vMin,scaleY);
    GdipDeletePen(pT);

    /* Chikou Span : teal */
    GpPen* pC=nullptr; GdipCreatePen1(0xFF008888,1.2f,UnitPixel,&pC);
    DrawLine(g,pC,chikouBuf,count,vs,li,oriX,oriY,stepX,vMin,scaleY);
    GdipDeletePen(pC);

    /* Label + bouton X */
    char lbl[32];
    std::snprintf(lbl,sizeof(lbl),"Ichi(%d,%d,%d)",tenkan,kijun,senkou);
    int lblX=(int)oriX+4, lblY=28+14+panelIndex*(closeBtnSz+4);
    SetBkMode(hDC,TRANSPARENT); SetTextColor(hDC,0xCC4400);
    TextOutA(hDC,lblX,lblY,lbl,(int)std::strlen(lbl));
    SetTextColor(hDC,0);
    float btnX=(float)(lblX+(int)std::strlen(lbl)*7+3);
    DrawCloseBtn(g,btnX,(float)(lblY-1),(float)closeBtnSz);
}

//QCHART_REGISTER: Register_Ichimoku
extern "C" void Register_Ichimoku(IndicatorRegistry* reg) {
    if (reg->count>=MAX_INDICATORS) return;
    IndicatorDef* d=&reg->defs[reg->count++];
    std::strncpy(d->name,       "Ichimoku",  sizeof(d->name)-1);
    std::strncpy(d->labelPrefix,"Ichi",      sizeof(d->labelPrefix)-1);
    std::strncpy(d->param2Label,"Kijun",     sizeof(d->param2Label)-1);
    d->defaultPeriod = 9;
    d->defaultParam2 = 26;
    d->isPanel       = 0;
    d->drawOverlay   = Ichi_DrawOverlay;
    d->drawPanel     = nullptr;
}
