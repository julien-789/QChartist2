/*
 * indicators/monthlypivot.cpp
 * Yearly Pivot Point — overlay.
 *
 * Algo MQL4 original traduit exactement en convention QChart (0=ancien) :
 *
 * MQL4 itère i=limit→0 (récent→ancien). "i+1" = plus ancien.
 * QChart itère i=0→count-1 (ancien→récent). "i-1" = plus ancien.
 *
 * À chaque barre i :
 *   1. Accumuler lastH/lastL avec highs[i]/lows[i]
 *   2. SI nouveau janvier (month[i]==1 && month[i-1]!=1) :
 *        last_close = closes[i-1]  (barre précédente = MQL4 "i+1")
 *        this_open  = opens[i]
 *        Calculer Pm,R1,S1,R2,S2,R3,S3 sur lastH/lastL accumulés
 *        Réinitialiser lastH=highs[i], lastL=lows[i]
 *   3. Affecter buf[i] = niveaux courants
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

/* ── Extraire mois depuis timestamp Unix ─────────────────────────────── */
static int MonthFromUnix(double ts)
{
    long long t  = (long long)ts;
    long long z  = t/86400 + 719468;
    long long era= (z>=0?z:z-146096)/146097;
    long long doe= z - era*146097;
    long long yoe= (doe - doe/1460 + doe/36524 - doe/146096)/365;
    long long doy= doe - (365*yoe + yoe/4 - yoe/100);
    long long mp = (5*doy+2)/153;
    int month    = (int)(mp<10 ? mp+3 : mp-9);
    return month;
}

/* ── Helper dessin courbe ────────────────────────────────────────────── */
static void DrawLine(GpGraphics* g, GpPen* pen,
    const double* buf, int count, int vs, int li,
    float oriX, float oriY, float stepX, double vMin, double scaleY)
{
    float ox=0,oy=0; bool fst=true;
    for (int i=vs;i<=li;++i){
        if (i<0||i>=count||buf[i]==0.0){fst=true;continue;}
        float x=oriX+(i-vs)*stepX+stepX*0.5f;
        float y=oriY-(float)((buf[i]-vMin)*scaleY);
        if (!fst) GdipDrawLine(g,pen,ox,oy,x,y);
        ox=x;oy=y;fst=false;
    }
}

/* ── Label droit ─────────────────────────────────────────────────────── */
static void DrawRightLabel(HDC hDC, GpGraphics* g,
    float xRight, float y, const char* lbl, unsigned int col)
{
    int lw=(int)strlen(lbl)*7+6;
    GpSolidFill* br=nullptr;
    GdipCreateSolidFill((col&0x00FFFFFF)|0xCC000000,&br);
    GdipFillRectangle(g,(GpBrush*)br,xRight+2,y-8.0f,(float)lw,14.0f);
    GdipDeleteBrush(br);
    SetBkMode(hDC,TRANSPARENT);
    SetTextColor(hDC,0xFFFFFF);
    TextOutA(hDC,(int)xRight+4,(int)y-8,lbl,(int)strlen(lbl));
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

/* ── Callback DrawOverlay ─────────────────────────────────────────────── */
static void YPivot_DrawOverlay(
    GpGraphics*         g,
    HDC                 hDC,
    const double*       closes,
    const double*       opens,
    const double*       highs,
    const double*       lows,
    const double*       /*volumes*/,
    const int*          /*weekdays*/,
    int                 count,
    int                 /*period*/,
    int                 /*param2*/,
    int                 panelIndex,
    const ChartCtx*     ctx,
    int                 closeBtnSz,
    const unsigned int* /*colors*/)
{
    if (count>MAX_B||count<2||!ctx->curTimestamps) return;

    float  oriX=ctx->oriX, oriY=ctx->oriY;
    float  stepX=ctx->stepX, lenX=ctx->lenX;
    double vMin=ctx->vMin, scaleY=ctx->scaleY;
    int    vs=ctx->viewStart, li=ctx->lastIdx;
    const double* ts = ctx->curTimestamps;

    /* ── Calcul des 7 buffers ─────────────────────────────────────────── */
    static double pmBuf[MAX_B], r1Buf[MAX_B], s1Buf[MAX_B];
    static double r2Buf[MAX_B], s2Buf[MAX_B], r3Buf[MAX_B], s3Buf[MAX_B];

    for (int i=0;i<count;++i)
        pmBuf[i]=r1Buf[i]=s1Buf[i]=r2Buf[i]=s2Buf[i]=r3Buf[i]=s3Buf[i]=0.0;

    double Pm=0,R1=0,S1=0,R2=0,S2=0,R3=0,S3=0;
    double lastH = highs[0];
    double lastL = lows[0];
    int    prevMonth = MonthFromUnix(ts[0]);

    for (int i=0; i<count; ++i){
        int curMonth = MonthFromUnix(ts[i]);

        /* 1. Accumuler H/L de l'année en cours */
        if (highs[i] > lastH) lastH = highs[i];
        if (lows[i]  < lastL) lastL = lows[i];

        /* 2. Détection début janvier = début d'une nouvelle année */
        if (curMonth == 1 && prevMonth != 1 && i > 0){
            /* H/L accumulé = toute l'année précédente
             * close précédent = dernière barre de déc = closes[i-1]
             * open courant = première barre de jan = opens[i]  */
            double prevC = closes[i-1];
            double thisO = opens[i];

            Pm = (lastH + lastL + thisO + prevC) / 4.0;
            R1 = 2.0*Pm - lastL;
            S1 = 2.0*Pm - lastH;
            R2 = Pm + (lastH - lastL);
            S2 = Pm - (lastH - lastL);
            R3 = 2.0*Pm + (lastH - 2.0*lastL);
            S3 = 2.0*Pm - (2.0*lastH - lastL);

            /* Réinitialiser H/L pour la nouvelle année */
            lastH = highs[i];
            lastL = lows[i];
        }

        prevMonth = curMonth;

        /* 3. Remplir les buffers */
        pmBuf[i]=Pm; r1Buf[i]=R1; s1Buf[i]=S1;
        r2Buf[i]=R2; s2Buf[i]=S2; r3Buf[i]=R3; s3Buf[i]=S3;
    }

    /* ── Rendu ────────────────────────────────────────────────────────── */
    float xRight = oriX + lenX;

    struct {
        const double* buf; unsigned int col;
        float w; GpDashStyle dash; const char* lbl;
    } levels[]={
        {r3Buf, 0xFF2E8B57, 1.0f, DashStyleDash,  "R3"},
        {r2Buf, 0xFFDC143C, 1.2f, DashStyleDash,  "R2"},
        {r1Buf, 0xFFDC143C, 1.8f, DashStyleSolid, "R1"},
        {pmBuf, 0xFFFF00FF, 2.0f, DashStyleSolid, "P" },
        {s1Buf, 0xFF4169E1, 1.8f, DashStyleSolid, "S1"},
        {s2Buf, 0xFF4169E1, 1.2f, DashStyleDash,  "S2"},
        {s3Buf, 0xFF2E8B57, 1.0f, DashStyleDash,  "S3"},
    };

    for (auto& lv : levels){
        GpPen* p=nullptr; GdipCreatePen1(lv.col,lv.w,UnitPixel,&p);
        if (lv.dash!=DashStyleSolid) GdipSetPenDashStyle(p,lv.dash);
        DrawLine(g,p,lv.buf,count,vs,li,oriX,oriY,stepX,vMin,scaleY);
        GdipDeletePen(p);
        /* Label à la dernière valeur visible non nulle */
        for (int i=li;i>=vs;--i){
            if (i>=0&&i<count&&lv.buf[i]!=0.0){
                float y=oriY-(float)((lv.buf[i]-vMin)*scaleY);
                DrawRightLabel(hDC,g,xRight,y,lv.lbl,lv.col);
                break;
            }
        }
    }

    SetTextColor(hDC,0);

    /* Label + bouton X */
    const char* lbl="YearlyPivot";
    int lblX=(int)oriX+4, lblY=28+14+panelIndex*(closeBtnSz+4);
    SetBkMode(hDC,TRANSPARENT);
    SetTextColor(hDC,0xFF00FF);
    TextOutA(hDC,lblX,lblY,lbl,(int)strlen(lbl));
    SetTextColor(hDC,0);
    float btnX=(float)(lblX+(int)strlen(lbl)*7+3);
    DrawCloseBtn(g,btnX,(float)(lblY-1),(float)closeBtnSz);
}

/* ── Enregistrement ──────────────────────────────────────────────────── */
//QCHART_REGISTER: Register_YearlyPivot
extern "C" void Register_YearlyPivot(IndicatorRegistry* reg) {
    if (reg->count>=MAX_INDICATORS) return;
    IndicatorDef* d=&reg->defs[reg->count++];
    std::strncpy(d->name,       "Yearly Pivot", sizeof(d->name)-1);
    std::strncpy(d->labelPrefix,"YPivot",       sizeof(d->labelPrefix)-1);
    d->defaultPeriod = 777;
    d->defaultParam2 = 0;
    d->isPanel       = 0;
    d->drawOverlay   = YPivot_DrawOverlay;
    d->drawPanel     = nullptr;
}
