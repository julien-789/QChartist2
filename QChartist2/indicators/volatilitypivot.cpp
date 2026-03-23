/*
 * indicators/volatilitypivot.cpp
 * Volatility Pivot — indicateur overlay (trailing stop adaptatif).
 *
 * Algorithme (fidèle à Volatility_Pivot_cpp.cpp, traduit en convention QChart) :
 *
 *   ATR[i]      = ATR(atr_range, i)
 *   DeltaStop[i]= EMA(ATR, ima_range)[i] * atr_factor
 *
 *   Itération du plus RÉCENT vers le plus ANCIEN dans MQL4
 *   → dans QChart (0=ancien) : itérer du plus ancien (i=0) vers le plus récent.
 *   "i+1" MQL4 (plus récent) = "i-1" QChart (moins récent = plus ancien traité avant)
 *   Donc on itère i=1..count-1, buf[i-1] est déjà calculé.
 *
 *   Logique trailing stop :
 *   if close[i] == buf[i-1] :
 *       buf[i] = buf[i-1]
 *   elif close[i-1] < buf[i-1] && close[i] < buf[i-1] :
 *       buf[i] = min(buf[i-1], close[i] + DeltaStop)   ← tendance baissière
 *   elif close[i-1] > buf[i-1] && close[i] > buf[i-1] :
 *       buf[i] = max(buf[i-1], close[i] - DeltaStop)   ← tendance haussière
 *   else :
 *       if close[i] > buf[i-1] : buf[i] = close[i] - DeltaStop
 *       else                    : buf[i] = close[i] + DeltaStop
 *
 * period   = atr_range (défaut 100)
 * param2   = atr_factor * 10 (défaut 30 = 3.0)
 * ima_range = 10 (codé)
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

static const int MAX_B    = 4096;
static const int IMA_RANGE = 10;   /* période EMA sur ATR */

/* ── ATR ─────────────────────────────────────────────────────────────── */
static double CalcATR1(const double* c, const double* h, const double* l,
                       int i, int count)
{
    double tr = h[i]-l[i];
    if (i>0){
        double a=fabs(h[i]-c[i-1]), b=fabs(l[i]-c[i-1]);
        if (a>tr) tr=a;
        if (b>tr) tr=b;
    }
    return tr;
}

/* ── Bouton X ────────────────────────────────────────────────────────── */
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

/* ── Callback DrawOverlay ────────────────────────────────────────────── */
static void VP_DrawOverlay(
    GpGraphics*         g,
    HDC                 hDC,
    const double*       closes,
    const double*       opens,
    const double*       highs,
    const double*       lows,
    const double*       /*volumes*/,
    const int*          /*weekdays*/,
    int                 count,
    int                 period,
    int                 param2,
    int                 panelIndex,
    const ChartCtx*     ctx,
    int                 closeBtnSz,
    const unsigned int* /*colors*/)
{
    if (count>MAX_B||count<2) return;

    int    atr_range  = (period>0) ? period : 100;
    double atr_factor = (param2>0) ? param2/10.0 : 3.0;

    float  oriX=ctx->oriX, oriY=ctx->oriY;
    float  stepX=ctx->stepX, lenX=ctx->lenX;
    double vMin=ctx->vMin, scaleY=ctx->scaleY;
    int    vs=ctx->viewStart, li=ctx->lastIdx;

    /* ── Passe 1 : ATR simple par barre ──────────────────────────────── */
    static double atrRaw[MAX_B];
    for (int i=0;i<count;++i)
        atrRaw[i]=CalcATR1(closes,highs,lows,i,count);

    /* ── Passe 2 : EMA(ATR, ima_range) ──────────────────────────────── */
    static double atrEma[MAX_B];
    {
        double k=2.0/(IMA_RANGE+1.0);
        atrEma[0]=atrRaw[0];
        for (int i=1;i<count;++i)
            atrEma[i]=atrRaw[i]*k + atrEma[i-1]*(1.0-k);
    }

    /* ── Passe 3 : ATR(atr_range) = SMA(atrRaw, atr_range) ──────────── */
    /* L'original utilise iatr() = vraie ATR sur atr_range barres.
     * On calcule ATR(n) = SMA des True Ranges sur n barres. */
    static double atrN[MAX_B];
    {
        double sum=0;
        for (int i=0;i<count;++i){
            sum+=atrRaw[i];
            if (i>=atr_range-1){
                atrN[i]=sum/atr_range;
                sum-=atrRaw[i-atr_range+1];
            } else {
                atrN[i]=sum/(i+1);
            }
        }
    }

    /* ── Passe 4 : EMA(atrN, ima_range) → DeltaStop ─────────────────── */
    static double deltaBuf[MAX_B];
    {
        double k=2.0/(IMA_RANGE+1.0);
        deltaBuf[0]=atrN[0]*atr_factor;
        for (int i=1;i<count;++i)
            deltaBuf[i]=(atrN[i]*k + atrN[i-1]*(1.0-k)) * atr_factor;
    }

    /* ── Passe 5 : trailing stop ─────────────────────────────────────── */
    static double buf[MAX_B];
    for (int i=0;i<count;++i) buf[i]=NAN;

    /* Initialisation première barre */
    buf[0] = closes[0] - deltaBuf[0];

    for (int i=1;i<count;++i){
        double ds  = deltaBuf[i];
        double c   = closes[i];
        double cp  = closes[i-1];  /* close précédent (plus ancien) */
        double bp  = buf[i-1];     /* pivot précédent               */

        if (c == bp){
            buf[i] = bp;
        } else if (cp < bp && c < bp){
            /* Tendance baissière : trailing stop descend */
            buf[i] = (bp < c+ds) ? bp : c+ds;
        } else if (cp > bp && c > bp){
            /* Tendance haussière : trailing stop monte */
            buf[i] = (bp > c-ds) ? bp : c-ds;
        } else {
            /* Changement de direction */
            buf[i] = (c > bp) ? c-ds : c+ds;
        }
    }

    /* ── Rendu : ligne colorée selon position du close ───────────────── */
    /* Au-dessus du close = résistance (rouge), en-dessous = support (vert) */
    float ox=0,oy=0; bool fst=true;
    unsigned int prevCol=0;
    for (int i=vs;i<=li;++i){
        if (i<0||i>=count||std::isnan(buf[i])){fst=true;continue;}
        float x=oriX+(i-vs)*stepX+stepX*0.5f;
        float y=oriY-(float)((buf[i]-vMin)*scaleY);
        unsigned int col=(buf[i]>closes[i]) ? 0xFFCC4444 : 0xFF44AAAA;
        if (!fst){
            GpPen* p=nullptr; GdipCreatePen1(col,1.5f,UnitPixel,&p);
            GdipDrawLine(g,p,ox,oy,x,y);
            GdipDeletePen(p);
        }
        ox=x; oy=y; fst=false; prevCol=col;
    }

    /* ── Label + bouton X ────────────────────────────────────────────── */
    char lbl[32];
    std::snprintf(lbl,sizeof(lbl),"VPivot(%d,%.1f)",atr_range,atr_factor);
    int lblX=(int)oriX+4, lblY=28+14+panelIndex*(closeBtnSz+4);
    SetBkMode(hDC,TRANSPARENT);
    SetTextColor(hDC,0x008888);
    TextOutA(hDC,lblX,lblY,lbl,(int)std::strlen(lbl));
    SetTextColor(hDC,0);
    float btnX=(float)(lblX+(int)std::strlen(lbl)*7+3);
    DrawCloseBtn(g,btnX,(float)(lblY-1),(float)closeBtnSz);
}

/* ── Enregistrement ──────────────────────────────────────────────────── */
//QCHART_REGISTER: Register_VolatilityPivot
extern "C" void Register_VolatilityPivot(IndicatorRegistry* reg) {
    if (reg->count>=MAX_INDICATORS) return;
    IndicatorDef* d=&reg->defs[reg->count++];
    std::strncpy(d->name,       "Volatility Pivot", sizeof(d->name)-1);
    std::strncpy(d->labelPrefix,"VPivot",           sizeof(d->labelPrefix)-1);
    std::strncpy(d->param2Label,"Factor x10",       sizeof(d->param2Label)-1);
    d->defaultPeriod = 100;   /* atr_range  */
    d->defaultParam2 = 30;    /* atr_factor*10 = 3.0 */
    d->isPanel       = 0;
    d->drawOverlay   = VP_DrawOverlay;
    d->drawPanel     = nullptr;
}
