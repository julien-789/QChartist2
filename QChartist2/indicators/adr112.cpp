/*
 * indicators/adr112.cpp
 * ADR 112 — Average Daily/Weekly/Monthly Range, fidèle à l'algo original.
 *
 * Algorithme :
 *   Pour chaque barre courante iadr (timestamp curTimestamps[iadr]) :
 *     1. iBarShift mappe ce timestamp vers la barre correspondante
 *        dans le TF de référence (refTimestamps[]).
 *     2. On cumule (H-L) sur adrperiod barres successives du TF ref.
 *     3. ADR = cumul / adrperiod
 *     4. open2 = open de la barre ref correspondant à iadr
 *     5. 5 niveaux : open2 ± ADR, open2 ± ADR/2, open2
 *
 * param2 = 0 → Daily (1440 min)
 * param2 = 1 → Weekly (10080 min)
 * param2 = 2 → Monthly (43200 min)
 *
 * Le .bas remplit ctx->refHighs/refLows/refOpens/refTimestamps
 * (données brutes du QChartXXXX, non mappées) et ctx->curTimestamps
 * (timestamps du TF courant).
 *
 * iBarShift interne : bisection sur refTimestamps pour trouver
 * la barre ref dont le timestamp ≤ curTimestamps[iadr].
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

static const int MAX_B    = 8192;
static const int MAX_REF  = 4096;

/* ── iBarShift : recherche par bisection ──────────────────────────────── */
/*
 * Retourne l'index dans refTimestamps[] de la barre dont le timestamp
 * est le plus proche ≤ targetUnix. Les timestamps sont supposés croissants.
 * limit : index maximum à chercher (évite de sortir du tableau).
 * Retourne 0 si targetUnix < refTimestamps[0].
 */
static int IBarShift(
    const double* refTs, int refCount,
    double targetUnix, int limit)
{
    if (!refTs || refCount <= 0) return 0;
    if (limit >= refCount) limit = refCount - 1;
    if (targetUnix <= refTs[0]) return 0;
    if (targetUnix >= refTs[limit]) return limit;

    /* Bisection */
    int lo = 0, hi = limit;
    while (hi - lo > 1) {
        int mid = (lo + hi) / 2;
        if (refTs[mid] <= targetUnix) lo = mid;
        else                           hi = mid;
    }
    return lo;
}

/* ── Helper dessin d'une courbe ──────────────────────────────────────── */
static void DrawBuf(GpGraphics* g, GpPen* pen, const double* buf, int count,
    int vs, int li, float oriX, float oriY, float stepX,
    double vMin, double scaleY)
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

static void DrawRightLabel(HDC hDC, GpGraphics* g, float xRight, float y,
    const char* lbl, unsigned int col)
{
    int lw=(int)std::strlen(lbl)*7+6;
    GpSolidFill* br=nullptr;
    GdipCreateSolidFill((col&0x00FFFFFF)|0xCC000000,&br);
    GdipFillRectangle(g,(GpBrush*)br,xRight+2,y-8.0f,(float)lw,14.0f);
    GdipDeleteBrush(br);
    SetBkMode(hDC,TRANSPARENT);
    SetTextColor(hDC,0xFFFFFF);
    TextOutA(hDC,(int)xRight+4,(int)y-8,lbl,(int)std::strlen(lbl));
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

/* ── Callback DrawOverlay ─────────────────────────────────────────────── */
static void ADR_DrawOverlay(
    GpGraphics* g, HDC hDC,
    const double* /*closes*/, const double* /*opens*/,
    const double* /*highs*/,  const double* /*lows*/,
    const double* /*volumes*/, const int* /*weekdays*/,
    int count, int period, int param2, int panelIndex,
    const ChartCtx* ctx, int closeBtnSz, const unsigned int* /*colors*/)
{
    if (count > MAX_B) count = MAX_B;

    float  oriX=ctx->oriX, oriY=ctx->oriY;
    float  stepX=ctx->stepX, lenX=ctx->lenX;
    double vMin=ctx->vMin, scaleY=ctx->scaleY;
    int    vs=ctx->viewStart, li=ctx->lastIdx;

    /* Vérifier que les données de référence sont disponibles */
    const double* refH  = ctx->refHighs;
    const double* refL  = ctx->refLows;
    const double* refO  = ctx->refOpens;
    const double* refTs = ctx->refTimestamps;
    int           refN  = ctx->refCount;
    const double* curTs = ctx->curTimestamps;

    if (!refH || !refL || !refO || !refTs || !curTs || refN <= 0) return;
    if (period < 1) return;

    const char* tfLabel = (param2==1)?"W":(param2==2)?"M":"D";

    /* ── Calcul des 5 buffers (logique fidèle à l'algo original) ──────── */
    static double b1[MAX_B], b2[MAX_B], b3[MAX_B], b4[MAX_B], b5[MAX_B];
    for (int i=0;i<count;++i)
        b1[i]=b2[i]=b3[i]=b4[i]=b5[i]=NAN;

    int limit = (count < MAX_B) ? count : MAX_B;

    for (int iadr = 0; iadr < limit; ++iadr) {
        double targetTs = curTs[iadr];

        /* Barre de base dans le TF de référence */
        int baseIdx = IBarShift(refTs, refN, targetTs, refN - 1);

        /* Cumul ADR sur `period` barres précédentes du TF ref (plus anciennes)
         * Dans l'original MT4 : high1440[kadr + ibarshift(...)]
         * où index MT4 croissant = plus ancien → ici baseIdx - kadr */
        double adr = 0.0;
        for (int kadr = 1; kadr <= period; ++kadr) {
            int idx = baseIdx - kadr;   /* barres plus anciennes */
            if (idx < 0 || idx >= refN) break;
            adr += refH[idx] - refL[idx];
        }
        adr /= period;

        double open2 = (baseIdx >= 0 && baseIdx < refN) ? refO[baseIdx] : NAN;

        if (std::isnan(open2) || adr == 0.0) continue;

        b1[iadr] = open2 + adr;
        b2[iadr] = open2 + adr * 0.5;
        b3[iadr] = open2;
        b4[iadr] = open2 - adr * 0.5;
        b5[iadr] = open2 - adr;
    }

    const unsigned int COL1=0xFFCC0000, COL2=0xFFFF6600, COL3=0xFF888888,
                       COL4=0xFF4488FF, COL5=0xFF0022CC;
    float xRight = oriX + lenX;

    /* Remplissage zone entre les bandes extrêmes */
    for (int i=vs;i<=li;++i){
        if (i<0||i>=count||std::isnan(b1[i])||std::isnan(b5[i])) continue;
        float x=oriX+(i-vs)*stepX;
        float yTop=oriY-(float)((b1[i]-vMin)*scaleY);
        float yBot=oriY-(float)((b5[i]-vMin)*scaleY);
        float h=yBot-yTop; if (h<=0) continue;
        GpSolidFill* brF=nullptr; GdipCreateSolidFill(0x08884400,&brF);
        GdipFillRectangle(g,(GpBrush*)brF,x,yTop,stepX,h); GdipDeleteBrush(brF);
    }

    /* Labels des niveaux */
    char lbl1[8],lbl2[8],lbl3[8],lbl4[8],lbl5[8];
    std::snprintf(lbl1,sizeof(lbl1),"+%s",  tfLabel);
    std::snprintf(lbl2,sizeof(lbl2),"+%s/2",tfLabel);
    std::snprintf(lbl3,sizeof(lbl3),"%s",   tfLabel);
    std::snprintf(lbl4,sizeof(lbl4),"-%s/2",tfLabel);
    std::snprintf(lbl5,sizeof(lbl5),"-%s",  tfLabel);

    struct { const double* buf; unsigned int col; float w; bool dash; const char* lbl; }
    levels[5]={
        {b1,COL1,1.5f,false,lbl1},{b2,COL2,1.2f,true, lbl2},
        {b3,COL3,1.5f,false,lbl3},{b4,COL4,1.2f,true, lbl4},
        {b5,COL5,1.5f,false,lbl5}
    };

    for (int lvl=0;lvl<5;++lvl){
        GpPen* pen=nullptr;
        GdipCreatePen1(levels[lvl].col,levels[lvl].w,UnitPixel,&pen);
        if (levels[lvl].dash) GdipSetPenDashStyle(pen,(GpDashStyle)1);
        DrawBuf(g,pen,levels[lvl].buf,count,vs,li,oriX,oriY,stepX,vMin,scaleY);
        GdipDeletePen(pen);
        float lastY=-1.0f;
        for (int i=li;i>=vs;--i){
            if (i>=0&&i<count&&!std::isnan(levels[lvl].buf[i])){
                lastY=oriY-(float)((levels[lvl].buf[i]-vMin)*scaleY); break;
            }
        }
        if (lastY>=0.0f) DrawRightLabel(hDC,g,xRight,lastY,levels[lvl].lbl,levels[lvl].col);
    }

    SetTextColor(hDC,0);
    char lbl[32];
    std::snprintf(lbl,sizeof(lbl),"ADR%s(%d)",tfLabel,period);
    int lblX=(int)oriX+4, lblY=28+14+panelIndex*(closeBtnSz+4);
    SetBkMode(hDC,TRANSPARENT); SetTextColor(hDC,0x884400);
    TextOutA(hDC,lblX,lblY,lbl,(int)std::strlen(lbl));
    SetTextColor(hDC,0);
    float btnX=(float)(lblX+(int)std::strlen(lbl)*7+3);
    DrawCloseBtn(g,btnX,(float)(lblY-1),(float)closeBtnSz);
}

/* ── Enregistrement ───────────────────────────────────────────────────── */
//QCHART_REGISTER: Register_ADR112
extern "C" void Register_ADR112(IndicatorRegistry* reg) {
    if (reg->count>=MAX_INDICATORS) return;
    IndicatorDef* d=&reg->defs[reg->count++];
    std::strncpy(d->name,       "ADR 112",          sizeof(d->name)-1);
    std::strncpy(d->labelPrefix,"ADR",              sizeof(d->labelPrefix)-1);
    std::strncpy(d->param2Label,"TF(0=D 1=W 2=M)", sizeof(d->param2Label)-1);
    d->defaultPeriod=14;
    d->defaultParam2=0;
    d->isPanel      =0;
    d->drawOverlay  =ADR_DrawOverlay;
    d->drawPanel    =nullptr;
}
