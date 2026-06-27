#define WIN_INCLUDEALL
#include once "windows.bi"
#include once "win/commdlg.bi"
#include once "win/commctrl.bi"
#include once "vbcompat.bi"
#include once "win/gdiplus.bi"

#inclib "gdiplus"
#inclib "comctl32"
#inclib "shell32"

Using GDIPLUS

' --- Constantes ---
Const SCROLL_H = 40
#define ID_MENU_OPEN      1001
#define ID_MENU_DATASOURCE 1002
#define ID_DS_SYMBOL      4001
#define ID_DS_STARTDATE   4002
#define ID_DS_ENDDATE     4003
#define ID_DS_TF          4004
#define ID_DS_APIKEY      4005
#define ID_DS_GETCHART    4006
#define ID_DS_STATUS      4007
#define ID_DS_TIMER       4008
#define ID_DS_APIKEYS_BTN 4009
#define ID_DS_SOURCE      4010   ' combobox source de données
' Champs de la fenêtre API Keys
#define ID_AK_TIINGO      4101
#define ID_AK_FINNHUB     4102
#define ID_AK_ALPHAVANTAGE 4103
#define ID_AK_TWELVEDATA  4104
#define ID_AK_SAVE        4105
#define ID_TOOL_SELECT    2001
#define ID_TOOL_LINE      2002
#define ID_TOOL_ERASER    2003
#define ID_TOOL_CROSSHAIR 2004
#define ID_TOOL_CIRCLE    2005
#define ID_TOOL_FIBOFAN   2006
#define ID_TOOL_GANNFAN   2007
#define ID_TOOL_FIBORET   2008
#define ID_TOOL_GANNGRID  2009
#define ID_TOOL_PENTAGRAM 2010
#define ID_TOOL_PARALINES 2011
#define ID_BTN_INDICATORS 3001
#define ID_LST_INDICATORS 3002
#define ID_BTN_APPLY      3003
#define ID_LBL_PERIOD     3010
#define ID_EDT_PERIOD     3011
#define ID_LBL_PERIOD2    3012
#define ID_EDT_PERIOD2    3013
#define ID_LBL_PARAMS     3014
#define ID_BTN_ZOOM_IN    3020
#define ID_BTN_ZOOM_OUT   3021
#define ID_POPUP_PARAMS   3030   ' menu item "Paramètres" du popup clic droit overlay
#define ID_CHART_LOADCSV    5010   ' menu contextuel graphe : charger CSV
#define ID_CHART_TECHNICALS 5011   ' menu contextuel graphe : indicateurs techniques

Const ZOOM_BAR_H    = 28   ' hauteur de la barre de zoom
Const ZOOM_MIN_BARS = 10   ' nombre minimum de bougies visibles
Const ZOOM_MAX_BARS = 500  ' nombre maximum de bougies visibles
Const ZOOM_STEP     = 10   ' pas de zoom (bougies)

Const RSI_PANEL_H      = 100
Const RSI_PANEL_GAP    = 4
Const RSI_PANEL_MARGIN = 36   ' marge entre axe X (labels date) et premier panel RSI
Const RSI_CLOSE_BTN    = 14
Const MAX_INDICATORS = 32

' --- Structures ---
Type TrendLine
    As Double  price1, price2   ' valeur dans l'espace du canvas (prix ou 0-100)
    As Integer bar1, bar2
    As Integer canvasType       ' 0 = graphe principal, 1..N = index panel séparé (1-based)
End Type

' Cercle défini par 3 points — stocké en coordonnées bar/price comme les trendlines
Type Circle3P
    As Integer bar1, bar2, bar3
    As Double  price1, price2, price3
End Type
Dim Shared Circles(Any) As Circle3P
' État du tracé cercle 3 points
Dim Shared circleClickNb As Integer = 0
Dim Shared circleX(1 To 3) As Single
Dim Shared circleY(1 To 3) As Single
' Stockage intermédiaire bar/price pour les 3 points en cours
Dim Shared circleBar(1 To 3) As Integer
Dim Shared circlePrice(1 To 3) As Double

' Fibonacci Fan : 2 points (pivot + fin), stockés en bar/price
' Les 5 rayons sont dessinés aux ratios : 23.6, 38.2, 50, 61.8, 78.6
Type FiboFan
    As Integer bar1, bar2     ' pivot (P1) et fin de ligne de base (P2)
    As Double  price1, price2
End Type
Dim Shared FiboFans(Any) As FiboFan
Dim Shared fiboFanClickNb As Integer = 0
Dim Shared fiboFanBar1    As Integer
Dim Shared fiboFanPrice1  As Double

' Gann Fan : même structure que FiboFan (2 points)
Type GannFan
    As Integer bar1, bar2
    As Double  price1, price2
End Type
Dim Shared GannFans(Any) As GannFan
Dim Shared gannFanClickNb As Integer = 0
Dim Shared gannFanBar1    As Integer
Dim Shared gannFanPrice1  As Double

' Fibonacci Retracements : 2 points (haut + bas), stockés en bar/price
Type FiboRet
    As Integer bar1, bar2
    As Double  price1, price2   ' price1=haut (100%), price2=bas (0%)
End Type
Dim Shared FiboRets(Any) As FiboRet
Dim Shared fiboRetClickNb As Integer = 0
Dim Shared fiboRetBar1    As Integer
Dim Shared fiboRetPrice1  As Double

' Gann Grid : 2 points définissant la cellule de base
Type GannGrid
    As Integer bar1, bar2
    As Double  price1, price2
End Type
Dim Shared GannGrids(Any) As GannGrid
Dim Shared gannGridClickNb As Integer = 0
Dim Shared gannGridBar1    As Integer
Dim Shared gannGridPrice1  As Double

' Pentagramme : centre (P1) + rayon vers P2
Type Pentagram
    As Integer bar1, bar2
    As Double  price1, price2
End Type
Dim Shared Pentagrams(Any) As Pentagram
Dim Shared pentaClickNb As Integer = 0
Dim Shared pentaBar1    As Integer
Dim Shared pentaPrice1  As Double

' Parallel Lines : 3 points — P1+P2 = ligne de base, P3 = point de la parallèle
' La parallèle va de P3 vers P3+(P2-P1)
Type ParaLines
    As Integer bar1, bar2, bar3
    As Double  price1, price2, price3
End Type
Dim Shared ParaLinesArr(Any) As ParaLines
Dim Shared paraClickNb  As Integer = 0
Dim Shared paraBar1     As Integer
Dim Shared paraPrice1   As Double
Dim Shared paraBar2     As Integer
Dim Shared paraPrice2   As Double

' Géométrie des panneaux séparés (remplie à chaque rendu, utilisée pour le hit-test)
Type PanelGeom
    rTop           As Integer
    rBottom        As Integer
    innerH         As Integer
    vMin           As Double
    vMax           As Double
    activePanelIdx As Integer   ' index dans ActivePanels() correspondant à ce panel
End Type
Dim Shared PanelGeoms(MAX_INDICATORS - 1) As PanelGeom
Dim Shared PanelGeomCount As Integer = 0
Dim Shared As Integer mainChartH_cached = 0   ' bas du graphe principal (pixels)

Type PriceData
    Dt   As String * 10
    Tm   As String * 5
    O    As Double
    H    As Double
    L    As Double
    C    As Double
    V    As Long
    Unix As Double   ' timestamp Unix en secondes (calculé au chargement)
End Type

Type QChartType
    History(Any) As PriceData
    IsLoaded    As Integer = 0
    ViewStart   As Integer = 0
    ViewCount   As Integer = 60
    TimeFrame   As Long    = 0   ' timeframe en minutes (détecté automatiquement)
End Type

' Structure contexte graphique (miroir de chartctx.h)
Type ChartCtx
    oriX       As Single
    oriY       As Single
    stepX      As Single
    lenX       As Single
    vMin       As Double
    scaleY     As Double
    mainChartH As Long
    viewStart  As Long
    lastIdx    As Long
    ' TF de référence (brut, non mappé) — rempli par le .bas avant l'appel overlay
    refHighs      As Double Ptr    ' Highs du TF de référence
    refLows       As Double Ptr    ' Lows  du TF de référence
    refOpens      As Double Ptr    ' Opens du TF de référence
    refTimestamps As Double Ptr    ' Timestamps Unix du TF de référence
    refCount      As Long          ' Nombre de barres dans le TF de référence
    refTFMinutes  As Long          ' Durée d'une barre en minutes
    curTimestamps As Double Ptr    ' Timestamps Unix du TF courant
End Type

' Callbacks C++ (pointeurs de fonctions)
Type DrawOverlayFn As Sub(g As Any Ptr, hDC As HDC, closes As Double Ptr, opens As Double Ptr, highs As Double Ptr, lows As Double Ptr, volumes As Double Ptr, weekdays As Long Ptr, count As Long, period As Long, param2 As Long, panelIndex As Long, ctx As ChartCtx Ptr, closeBtnSz As Long, colors As Any Ptr)
Type DrawPanelFn   As Sub(g As Any Ptr, hDC As HDC, closes As Double Ptr, opens As Double Ptr, highs As Double Ptr, lows As Double Ptr, volumes As Double Ptr, weekdays As Long Ptr, count As Long, period As Long, param2 As Long, panelIndex As Long, panelCount As Long, ctx As ChartCtx Ptr, panelH As Long, panelGap As Long, closeBtnSz As Long, outVMin As Double Ptr, outVMax As Double Ptr)

' Descripteur d'un indicateur (miroir de IndicatorDef dans indicator_api.h)
' ATTENTION : l'ordre et les tailles des champs doivent correspondre exactement
' à la struct C++ pour que le layout mémoire soit identique.
Type IndicatorDef
    name          As ZString * 64
    labelPrefix   As ZString * 16
    defaultPeriod As Long           ' période 1 par défaut
    defaultParam2 As Long           ' valeur par défaut du 2ème paramètre (0=absent)
    param2Label   As ZString * 32   ' label du 2ème paramètre ("" = caché)
    isPanel       As Long
    drawOverlay   As DrawOverlayFn
    drawPanel     As DrawPanelFn
End Type

' Registre global des indicateurs
Type IndicatorRegistry
    defs(MAX_INDICATORS - 1) As IndicatorDef
    count As Long
End Type

Dim Shared indRegistry As IndicatorRegistry

' Un panneau actif (une instance appliquée d'un indicateur)
Type ActivePanel
    defIndex As Long   ' index dans indRegistry.defs
    period   As Long   ' paramètre 1 (période)
    param2   As Long   ' paramètre 2 optionnel (ex: timeframe pour ADR112)
End Type
Dim Shared ActivePanels(Any) As ActivePanel
Dim Shared ActiveCount As Integer = 0

' ── Multi-graphe ─────────────────────────────────────────────────────────────
Const MAX_CHARTS = 4

' Données propres à chaque fenêtre graphe enfant
' Chaque graphe a son propre ViewStart/ViewCount et ses propres objets dessinés.
' La source de données (QChart global) est partagée dans cette première version ;
' les ActivePanels et drawables sont par-graphe.
Type ChartWinData
    hwnd        As HWND
    chartIdx    As Integer      ' 0-based index dans hCharts()

    ' Source de données propre à ce graphe
    Chart       As QChartType   ' données OHLCV + ViewStart/ViewCount/IsLoaded/TimeFrame

    ' Objets dessinés propres à ce graphe
    Lines(Any)       As TrendLine
    Circles(Any)     As Circle3P
    FiboFans(Any)    As FiboFan
    GannFans(Any)    As GannFan
    FiboRets(Any)    As FiboRet
    GannGrids(Any)   As GannGrid
    Pentagrams(Any)  As Pentagram
    ParaLinesArr(Any) As ParaLines

    ' Indicateurs actifs
    ActivePanels(Any) As ActivePanel
    ActiveCount      As Integer

    ' État outils
    currentTool      As Integer
    isDrawing        As Integer
    crosshairX       As Integer
    crosshairY       As Integer
    tmpBar           As Integer
    tmpPrice         As Double
    tmpCanvasType    As Integer
    circleClickNb    As Integer
    circleBar(1 To 3) As Integer
    circlePrice(1 To 3) As Double
    fiboFanClickNb   As Integer
    fiboFanBar1      As Integer
    fiboFanPrice1    As Double
    gannFanClickNb   As Integer
    gannFanBar1      As Integer
    gannFanPrice1    As Double
    fiboRetClickNb   As Integer
    fiboRetBar1      As Integer
    fiboRetPrice1    As Double
    gannGridClickNb  As Integer
    gannGridBar1     As Integer
    gannGridPrice1   As Double
    pentaClickNb     As Integer
    pentaBar1        As Integer
    pentaPrice1      As Double
    paraClickNb      As Integer
    paraBar1         As Integer
    paraPrice1       As Double
    paraBar2         As Integer
    paraPrice2       As Double
    rightClickedOverlayIdx As Integer

    ' Cache rendu (rempli par RenderChartGDIPlus, utilisé par hit-test)
    vMin            As Double
    vMax            As Double
    scaleY          As Double
    oriX            As Single
    oriY            As Single
    stepX           As Single
    lenY            As Single
    snapX           As Single
    snapY           As Single
    snapPrice       As Double
    snapBar         As Integer
    mainChartH_cached As Integer
    PanelGeoms(MAX_INDICATORS - 1) As PanelGeom
    PanelGeomCount  As Integer
End Type

' Handles des fenêtres enfant graphe
Dim Shared hCharts(MAX_CHARTS - 1) As HWND
Dim Shared chartCount As Integer = 0     ' nombre de graphes actifs (1, 2 ou 4)
Dim Shared activeChartIdx As Integer = 0 ' index du graphe qui a le focus

#define ID_MENU_VIEW1   5001
#define ID_MENU_VIEW2   5002
#define ID_MENU_VIEW4   5004

' --- Globales ---
Dim Shared QChart     As QChartType   ' TF courant (fichier chargé)
Dim Shared QChart1    As QChartType   ' 1 min
Dim Shared QChart5    As QChartType   ' 5 min
Dim Shared QChart15   As QChartType   ' 15 min
Dim Shared QChart30   As QChartType   ' 30 min
Dim Shared QChart60   As QChartType   ' 60 min (1h)
Dim Shared QChart240  As QChartType   ' 240 min (4h)
Dim Shared QChart1440 As QChartType   ' 1440 min (Daily)
Dim Shared QChart10080 As QChartType  ' 10080 min (Weekly)
Dim Shared QChart43200 As QChartType  ' 43200 min (Monthly)
Dim Shared hScroll As HWND
Dim Shared hToolbar As HWND

' ── Data Source (Tiingo) ──────────────────────────────────────────────────────
Dim Shared hDSWin       As HWND   ' fenêtre Data Source
Dim Shared hDSSource    As HWND   ' combobox source de données
Dim Shared hWndMain     As HWND   ' handle fenêtre principale (pour SetTimer depuis DataSourceProc)
' ── Fenêtre API Keys ─────────────────────────────────────────────────────────
Dim Shared hAKWin       As HWND
Dim Shared hAKTiingo    As HWND
Dim Shared hAKFinnhub   As HWND
Dim Shared hAKAlpha     As HWND
Dim Shared hAKTwelve    As HWND
' Clés API stockées en mémoire
Dim Shared gKeyTiingo      As String
Dim Shared gKeyFinnhub     As String
Dim Shared gKeyAlpha       As String
Dim Shared gKeyTwelvedata  As String
Dim Shared hDSSymbol    As HWND
Dim Shared hDSStartDate As HWND
Dim Shared hDSEndDate   As HWND
Dim Shared hDSTF        As HWND   ' combobox timeframe
Dim Shared hDSApiKey    As HWND
Dim Shared hDSGetChart  As HWND
Dim Shared hDSStatus    As HWND   ' label statut
Dim Shared hDSTimer     As HWND   ' timer de polling
Dim Shared dsTimerActive As Integer = 0
Dim Shared dsTimerCount  As Integer = 0
Dim Shared dsActiveSource As Integer = 0  ' 0=Tiingo, 1=Yahoo, ...
Dim Shared dsPendingCSV  As String
Dim Shared dsBusyFile    As String
Dim Shared hBtnIndicators As HWND
Dim Shared hZoomBar As HWND   ' barre de zoom horizontale en haut du graphique
Dim Shared As Integer winW, winH
Dim Shared gdiplusToken As ULONG_PTR
Dim Shared toolbarW As Integer = 55

' Palette de couleurs ARGB pour les overlays
Dim Shared MA_Colors(7) As ULong
MA_Colors(0) = &HFF0000FF
MA_Colors(1) = &HFFFF6600
MA_Colors(2) = &HFF009900
MA_Colors(3) = &HFFCC00CC
MA_Colors(4) = &HFF00AAAA
MA_Colors(5) = &HFFAA0000
MA_Colors(6) = &HFF886600
MA_Colors(7) = &HFF004488

Dim Shared Lines(Any) As TrendLine
Dim Shared As Integer isDrawing = 0, currentTool = ID_TOOL_SELECT
Dim Shared tmpPrice As Double
Dim Shared tmpBar As Integer
Dim Shared tmpCanvasType As Integer

' Position courante du crosshair en coordonnées client
Dim Shared crosshairX As Integer = -1
Dim Shared crosshairY As Integer = -1

' Index de l'overlay sur lequel l'utilisateur a fait clic droit (-1 = aucun)
Dim Shared rightClickedOverlayIdx As Integer = -1

Dim Shared As Double g_vMin, g_vMax, g_scaleY
Dim Shared As Single g_oriX, g_oriY, g_stepX, g_lenY
Dim Shared As Single g_snapX, g_snapY
Dim Shared As Double g_snapPrice
Dim Shared As Integer g_snapBar

' --- Prototypes ---
Declare Function WndProc(hWnd As HWND, uMsg As UINT, wParam As WPARAM, lParam As LPARAM) As LRESULT
Declare Function ChartWndProc(hWnd As HWND, uMsg As UINT, wParam As WPARAM, lParam As LPARAM) As LRESULT
Declare Sub ArrangeChartWindows(hParent As HWND)
Declare Sub SetChartCount(hParent As HWND, n As Integer)
Declare Function GetChartData(hWnd As HWND) As ChartWinData Ptr
Declare Sub OpenTechnicalsForChart(hParent As HWND, chartIdx As Integer)
Declare Function IndicatorsDlgProc(hWnd As HWND, uMsg As UINT, wParam As WPARAM, lParam As LPARAM) As LRESULT
Declare Function ParamsDlgProc(hWnd As HWND, uMsg As UINT, wParam As WPARAM, lParam As LPARAM) As LRESULT
Declare Sub RenderChartGDIPlus(hWnd As HWND, hDC As HDC, w As Integer, h As Integer, pCD As ChartWinData Ptr)
Declare Sub ForceRedraw(hWnd As HWND)
Declare Sub LoadCSV(ByVal filename As String, hWnd As HWND)
Declare Function File_GetName(ByVal hWndParent As HWND) As String
Declare Function DistToSegment(px As Single, py As Single, x1 As Single, y1 As Single, x2 As Single, y2 As Single) As Single
Declare Sub OpenDataSourceWindow(hWndParent As HWND)
Declare Function DataSourceProc(hWnd As HWND, uMsg As UINT, wParam As WPARAM, lParam As LPARAM) As LRESULT
Declare Sub OpenApiKeysWindow(hWndParent As HWND)
Declare Function ApiKeysProc(hWnd As HWND, uMsg As UINT, wParam As WPARAM, lParam As LPARAM) As LRESULT
Declare Sub LoadIniFile()
Declare Sub SaveIniFile()
Declare Sub TiingoGetChart(hWndParent As HWND)
Declare Sub YahooFinanceGetChart(hWndParent As HWND)
Declare Sub YahooFinanceParseAndLoad(ByVal jsonPath As String, hWnd As HWND)
Declare Function YFNextToken(ByVal arr As String, ByRef scanPos As Integer) As String
Declare Function UnixToCSVDate(ByVal ts As Double) As String
Declare Sub TiingoCheckDone(hWnd As HWND)
Declare Sub TiingoParseAndLoad(ByVal jsonPath As String, hWnd As HWND)
Declare Function TiingoFreq(tfIdx As Integer) As String
Declare Function TiingoTFMin(tfIdx As Integer) As Integer
Declare Function ExtractJsonStr(ByVal obj As String, ByVal key As String) As String
Declare Function ExtractJsonNum(ByVal obj As String, ByVal key As String) As String
Declare Sub SnapToCandle(mx As Integer, my As Integer)
Declare Function RSIPanelTop(rsiIdx As Integer, mainChartH As Integer) As Integer
Declare Function HitTestCanvas(mx As Integer, my As Integer) As Integer
Declare Function ScreenYToValue(my As Integer, canvasType As Integer) As Double
Declare Function ValueToScreenY(value As Double, canvasType As Integer) As Single
Declare Function HitTestOverlayLabel(mx As Integer, my As Integer) As Integer
Declare Function HitTestPanelArea(mx As Integer, my As Integer) As Integer
Declare Function CountPanels(defIdx As Long) As Long
Declare Function PanelIndexOf(activeIdx As Long) As Long
Declare Function DateToUnix(dtStr As String, tmStr As String) As Double
Declare Sub FillTFBuffer(ByRef dest As QChartType, ByRef src As QChartType, startBar As Integer, endBar As Integer)
Declare Sub DetectTimeframe()
Declare Sub WriteTF(dispFile As Integer, tfToWrite As Long)

' Fonctions d'enregistrement des indicateurs (générées par build.bat)
#include once "indicators_registry.bas"

' ── Helper : calcul du timestamp Unix depuis une date/heure ───────────────────
' Même logique que dans DetectTimeframe — VB epoch = 25569 jours avant Unix epoch
Function DateToUnix(dtStr As String, tmStr As String) As Double
    If Len(dtStr) < 10 Then Return 0.0
    Dim yr As Integer = CInt(Mid(dtStr, 1, 4))
    Dim mo As Integer = CInt(Mid(dtStr, 6, 2))
    Dim dy As Integer = CInt(Mid(dtStr, 9, 2))
    Dim hr As Integer = 0
    Dim mn As Integer = 0
    If Len(tmStr) >= 5 Then
        hr = CInt(Mid(tmStr, 1, 2))
        mn = CInt(Mid(tmStr, 4, 2))
    End If
    Dim vbDate As Double = CDbl(DateSerial(yr, mo, dy)) _
                         + (hr * 3600.0 + mn * 60.0) / 86400.0
    Return (vbDate - 25569.0) * 86400.0
End Function

' ── Helper interne : remplit un QChartType cible depuis QChart (source) ───────
Sub FillTFBuffer(ByRef dest As QChartType, _
                         ByRef src  As QChartType, _
                         startBar As Integer, _
                         endBar   As Integer)
    ' startBar = barre de départ (index le plus élevé dans l'original)
    ' endBar   = barre de fin    (index le plus bas,  >= 1)
    ' On itère du plus récent (startBar) au plus ancien (endBar) comme l'original,
    ' mais on stocke dans dest.History en ordre croissant (0 = plus ancien).

    Dim barCount As Integer = startBar - endBar + 1
    If barCount <= 0 Then Exit Sub

    ReDim dest.History(barCount - 1)
    dest.IsLoaded = 1

    Dim o As Integer = 0
    For i As Integer = startBar To endBar Step -1
        If i > UBound(src.History) Then Continue For
        dest.History(o).Dt = src.History(i).Dt
        dest.History(o).Tm = src.History(i).Tm
        dest.History(o).O  = src.History(i).O
        dest.History(o).H  = src.History(i).H
        dest.History(o).L  = src.History(i).L
        dest.History(o).C  = src.History(i).C
        dest.History(o).V  = src.History(i).V
        ' Timestamp Unix (équivalent de datetimeserialXXX dans l'original)
        dest.History(o).Unix = DateToUnix(dest.History(o).Dt, dest.History(o).Tm)
        o += 1
    Next i

    ' Ajuster au nombre réellement copié
    If o < barCount Then ReDim Preserve dest.History(o - 1)
End Sub

' ── Sub principale ─────────────────────────────────────────────────────────────
Sub WriteTF(dispFile As Integer, tfToWrite As Long)
    'If openedFilesNb = 0 Then Exit Sub

    Dim totalBars As Integer = UBound(QChart.History)   ' index max (0-based)
    'Dim cntBars   As Integer = CInt(Val(cntBarsEdit.Text))
    Dim ii        As Integer = totalBars '- cntBars
    If ii < 1 Then ii = 1

    ' startBar = barre la plus récente (index le plus élevé)
    ' endBar   = barre de fin (ii dans l'original)
    Dim startBar As Integer = totalBars
    Dim endBar   As Integer = ii

    Select Case tfToWrite
        Case 1     : FillTFBuffer(QChart1,     QChart, startBar, endBar)
        Case 5     : FillTFBuffer(QChart5,     QChart, startBar, endBar)
        Case 15    : FillTFBuffer(QChart15,    QChart, startBar, endBar)
        Case 30    : FillTFBuffer(QChart30,    QChart, startBar, endBar)
        Case 60    : FillTFBuffer(QChart60,    QChart, startBar, endBar)
        Case 240   : FillTFBuffer(QChart240,   QChart, startBar, endBar)
        Case 1440  : FillTFBuffer(QChart1440,  QChart, startBar, endBar)
        Case 10080 : FillTFBuffer(QChart10080, QChart, startBar, endBar)
        Case 43200 : FillTFBuffer(QChart43200, QChart, startBar, endBar)
        Case Else
            Print "WriteTF: timeframe " & tfToWrite & " non supporté"
    End Select
End Sub

' ── Détection automatique du timeframe à partir des données chargées ──────────
' Analyse les intervalles entre les N premières barres pour déterminer
' le timeframe réel (en minutes). Utilise le mode statistique pour robustesse.

Sub DetectTimeframe()
    Const N As Integer = 5   ' nombre d'intervalles successifs à analyser

    If UBound(QChart.History) < N Then Exit Sub

    ' ── Calcul des timestamps Unix pour N+1 barres consécutives ──────────────
    Dim unix(N) As Double

    For i As Integer = 0 To N
        Dim dtStr As String = Trim(QChart.History(i).Dt)
        Dim tmStr As String = Trim(QChart.History(i).Tm)

        If Len(dtStr) < 10 Then Exit Sub

        Dim yr  As Integer = CInt(Mid(dtStr, 1, 4))
        Dim mo  As Integer = CInt(Mid(dtStr, 6, 2))
        Dim dy  As Integer = CInt(Mid(dtStr, 9, 2))
        Dim hr  As Integer = 0
        Dim mn  As Integer = 0

        If Len(tmStr) >= 5 Then
            hr = CInt(Mid(tmStr, 1, 2))
            mn = CInt(Mid(tmStr, 4, 2))
        End If

        ' Calcul du timestamp Unix via DateSerial + conversion en secondes
        ' DateSerial retourne un nombre de jours depuis le 30/12/1899 (epoch VB)
        ' Epoch Unix = 01/01/1970 = jour 25569 en calendrier VB
        Dim vbDate As Double = CDbl(DateSerial(yr, mo, dy)) + (hr * 3600.0 + mn * 60.0) / 86400.0
        unix(i) = (vbDate - 25569.0) * 86400.0
    Next i

    ' ── Calcul des différences en minutes entre barres consécutives ──────────
    Dim unixDiffMin(N - 1) As Double

    For i As Integer = 0 To N - 1
        unixDiffMin(i) = (unix(i + 1) - unix(i)) / 60.0
        ' Prendre la valeur absolue (ordre croissant dans QChart)
        If unixDiffMin(i) < 0 Then unixDiffMin(i) = -unixDiffMin(i)
    Next i

    ' ── Mode statistique : trouver l'intervalle le plus fréquent ─────────────
    Dim howOften(N - 1) As Integer
    Dim maxHowOften    As Integer = 0
    Dim realTF         As Double  = 0.0

    For j As Integer = 0 To N - 1
        howOften(j) = 1
        For i As Integer = 0 To N - 1
            If i <> j AndAlso unixDiffMin(j) = unixDiffMin(i) Then
                howOften(j) += 1
            End If
        Next i
        If howOften(j) > maxHowOften Then
            maxHowOften = howOften(j)
            realTF      = unixDiffMin(j)
        End If
    Next j

    If realTF <= 0 Then Exit Sub

    ' ── Normalisation du timeframe mensuel (28-31 jours → 43200 min) ─────────
    If realTF >= 40320.0 AndAlso realTF <= 44640.0 Then realTF = 43200.0

    ' ── Stocker le résultat ───────────────────────────────────────────────────
    QChart.TimeFrame = CLng(realTF)

    ' ── Remplir les buffers multi-TF depuis les données chargées ─────────────
    Dim totalBarsLoaded As Long = UBound(QChart.History) + 1

    ' Copie directe vers le buffer du TF correspondant au fichier chargé
    ' (1, 5, 15, 30, 60, 240 min)
    Select Case QChart.TimeFrame
        Case 1
            ReDim QChart1.History(totalBarsLoaded - 1)
            For bi As Long = 0 To totalBarsLoaded - 1
                QChart1.History(bi) = QChart.History(bi)
            Next bi
            QChart1.IsLoaded = 1 : QChart1.TimeFrame = 1
        Case 5
            ReDim QChart5.History(totalBarsLoaded - 1)
            For bi As Long = 0 To totalBarsLoaded - 1
                QChart5.History(bi) = QChart.History(bi)
            Next bi
            QChart5.IsLoaded = 1 : QChart5.TimeFrame = 5
        Case 15
            ReDim QChart15.History(totalBarsLoaded - 1)
            For bi As Long = 0 To totalBarsLoaded - 1
                QChart15.History(bi) = QChart.History(bi)
            Next bi
            QChart15.IsLoaded = 1 : QChart15.TimeFrame = 15
        Case 30
            ReDim QChart30.History(totalBarsLoaded - 1)
            For bi As Long = 0 To totalBarsLoaded - 1
                QChart30.History(bi) = QChart.History(bi)
            Next bi
            QChart30.IsLoaded = 1 : QChart30.TimeFrame = 30
        Case 60
            ReDim QChart60.History(totalBarsLoaded - 1)
            For bi As Long = 0 To totalBarsLoaded - 1
                QChart60.History(bi) = QChart.History(bi)
            Next bi
            QChart60.IsLoaded = 1 : QChart60.TimeFrame = 60
        Case 240
            ReDim QChart240.History(totalBarsLoaded - 1)
            For bi As Long = 0 To totalBarsLoaded - 1
                QChart240.History(bi) = QChart.History(bi)
            Next bi
            QChart240.IsLoaded = 1 : QChart240.TimeFrame = 240
        Case 1440
            ReDim QChart1440.History(totalBarsLoaded - 1)
            For bi As Long = 0 To totalBarsLoaded - 1
                QChart1440.History(bi) = QChart.History(bi)
            Next bi
            QChart1440.IsLoaded = 1 : QChart1440.TimeFrame = 1440
        Case 10080
            ReDim QChart10080.History(totalBarsLoaded - 1)
            For bi As Long = 0 To totalBarsLoaded - 1
                QChart10080.History(bi) = QChart.History(bi)
            Next bi
            QChart10080.IsLoaded = 1 : QChart10080.TimeFrame = 10080
        Case 43200
            ReDim QChart43200.History(totalBarsLoaded - 1)
            For bi As Long = 0 To totalBarsLoaded - 1
                QChart43200.History(bi) = QChart.History(bi)
            Next bi
            QChart43200.IsLoaded = 1 : QChart43200.TimeFrame = 43200
    End Select

    ' QChart1440 / QChart10080 / QChart43200 via agrégation :
    ' Remplir UNIQUEMENT si le fichier chargé est exactement Daily (1440)
    ' → agrège weekly et monthly depuis les barres daily
    ' Si on charge directement du 10080 ou 43200, la copie directe ci-dessus suffit
    ' Si on charge du H1 ou moins, on ne touche pas à ces buffers
    If QChart.TimeFrame = 1440 Then
    ' QChart1440 déjà rempli par Case 1440 ci-dessus — on agrège weekly et monthly
    ' seulement si ces buffers n'ont pas déjà été chargés depuis un fichier dédié

    ' QChart10080 (Weekly) : agréger depuis le daily SAUF si déjà chargé directement
    If Not QChart10080.IsLoaded Then
    Dim wkH As Double = -1e30, wkL As Double = 1e30
    Dim wkO As Double = 0, wkC As Double = 0, wkV As Long = 0
    Dim wkDt As String = "", wkTm As String = "", wkUnix As Double = 0
    Dim wkCount As Integer = 0
    ReDim QChart10080.History(totalBarsLoaded - 1)   ' taille max, sera réduit
    Dim wkIdx As Integer = 0
    Dim prevWeekDay As Integer = -1

    For bi As Long = 0 To totalBarsLoaded - 1
        Dim dtB As String = Trim(QChart.History(bi).Dt)
        Dim yrB As Integer = CInt(Mid(dtB, 1, 4))
        Dim moB As Integer = CInt(Mid(dtB, 6, 2))
        Dim dyB As Integer = CInt(Mid(dtB, 9, 2))
        Dim wd As Integer = Weekday(DateSerial(yrB, moB, dyB)) - 1  ' 0=Dim,1=Lun,...,6=Sam

        ' Nouvelle semaine si lundi après non-lundi, ou si c'est la première barre
        Dim newWeek As Boolean = (wd = 1 And prevWeekDay <> 1 And wkCount > 0)
        If bi = totalBarsLoaded - 1 Then  ' dernière barre : forcer la sauvegarde
            If QChart.History(bi).H > wkH Then wkH = QChart.History(bi).H
            If QChart.History(bi).L < wkL Then wkL = QChart.History(bi).L
            wkC = QChart.History(bi).C
            wkV += QChart.History(bi).V
            wkCount += 1
            newWeek = True
        End If

        If newWeek And wkCount > 0 Then
            QChart10080.History(wkIdx).Dt   = wkDt
            QChart10080.History(wkIdx).Tm   = wkTm
            QChart10080.History(wkIdx).O    = wkO
            QChart10080.History(wkIdx).H    = wkH
            QChart10080.History(wkIdx).L    = wkL
            QChart10080.History(wkIdx).C    = wkC
            QChart10080.History(wkIdx).V    = wkV
            QChart10080.History(wkIdx).Unix = wkUnix
            wkIdx += 1
            wkH = -1e30 : wkL = 1e30 : wkO = 0 : wkC = 0 : wkV = 0 : wkCount = 0
        End If

        If Not newWeek Or wkCount = 0 Then
            If wkCount = 0 Then
                wkO    = QChart.History(bi).O
                wkDt   = QChart.History(bi).Dt
                wkTm   = QChart.History(bi).Tm
                wkUnix = QChart.History(bi).Unix
            End If
            If QChart.History(bi).H > wkH Then wkH = QChart.History(bi).H
            If QChart.History(bi).L < wkL Then wkL = QChart.History(bi).L
            wkC = QChart.History(bi).C
            wkV += QChart.History(bi).V
            wkCount += 1
        End If
        prevWeekDay = wd
    Next bi

    If wkIdx > 0 Then
        ReDim Preserve QChart10080.History(wkIdx - 1)
        QChart10080.IsLoaded = 1
    End If
    End If ' Not QChart10080.IsLoaded

    ' QChart43200 (Monthly) : agréger depuis le daily SAUF si déjà chargé directement
    If Not QChart43200.IsLoaded Then
    Dim mnH As Double = -1e30, mnL As Double = 1e30
    Dim mnO As Double = 0, mnC As Double = 0, mnV As Long = 0
    Dim mnDt As String = "", mnTm As String = "", mnUnix As Double = 0
    Dim mnCount As Integer = 0
    ReDim QChart43200.History(totalBarsLoaded - 1)
    Dim mnIdx As Integer = 0
    Dim prevMo As Integer = -1, prevYr As Integer = -1

    For bi As Long = 0 To totalBarsLoaded - 1
        Dim dtM As String = Trim(QChart.History(bi).Dt)
        Dim yrM As Integer = CInt(Mid(dtM, 1, 4))
        Dim moM As Integer = CInt(Mid(dtM, 6, 2))

        Dim newMonth As Boolean = ((moM <> prevMo Or yrM <> prevYr) And mnCount > 0)
        If bi = totalBarsLoaded - 1 Then
            If QChart.History(bi).H > mnH Then mnH = QChart.History(bi).H
            If QChart.History(bi).L < mnL Then mnL = QChart.History(bi).L
            mnC = QChart.History(bi).C
            mnV += QChart.History(bi).V
            mnCount += 1
            newMonth = True
        End If

        If newMonth And mnCount > 0 Then
            QChart43200.History(mnIdx).Dt   = mnDt
            QChart43200.History(mnIdx).Tm   = mnTm
            QChart43200.History(mnIdx).O    = mnO
            QChart43200.History(mnIdx).H    = mnH
            QChart43200.History(mnIdx).L    = mnL
            QChart43200.History(mnIdx).C    = mnC
            QChart43200.History(mnIdx).V    = mnV
            QChart43200.History(mnIdx).Unix = mnUnix
            mnIdx += 1
            mnH = -1e30 : mnL = 1e30 : mnO = 0 : mnC = 0 : mnV = 0 : mnCount = 0
        End If

        If Not newMonth Or mnCount = 0 Then
            If mnCount = 0 Then
                mnO    = QChart.History(bi).O
                mnDt   = QChart.History(bi).Dt
                mnTm   = QChart.History(bi).Tm
                mnUnix = QChart.History(bi).Unix
            End If
            If QChart.History(bi).H > mnH Then mnH = QChart.History(bi).H
            If QChart.History(bi).L < mnL Then mnL = QChart.History(bi).L
            mnC = QChart.History(bi).C
            mnV += QChart.History(bi).V
            mnCount += 1
        End If
        prevMo = moM : prevYr = yrM
    Next bi

    If mnIdx > 0 Then
        ReDim Preserve QChart43200.History(mnIdx - 1)
        QChart43200.IsLoaded = 1
    End If
    End If ' Not QChart43200.IsLoaded

    End If ' QChart.TimeFrame = 1440
    Select Case QChart.TimeFrame
        Case 1, 5, 15, 30, 60, 240, 1440, 10080, 43200
            ' Timeframe standard — OK
        Case Else
            Print "Warning: uncommon timeframe detected (" & QChart.TimeFrame & _
                  " min) — indicators may not work correctly"
    End Select
    'MessageBox(0, Str(QChart.TimeFrame), "Titre", MB_OK)
End Sub

' --- Fonctions utilitaires indicateurs ---
Function CountPanels(defIdx As Long) As Long
    Dim n As Long = 0
    For i As Integer = 0 To ActiveCount - 1
        If ActivePanels(i).defIndex = defIdx Then n += 1
    Next
    Return n
End Function

Function PanelIndexOf(activeIdx As Long) As Long
    ' Index de ce panneau parmi les panneaux du même type
    Dim defIdx As Long = ActivePanels(activeIdx).defIndex
    Dim n As Long = 0
    For i As Integer = 0 To activeIdx - 1
        If ActivePanels(i).defIndex = defIdx Then n += 1
    Next
    Return n
End Function

' --- Fonctions ---
Function File_GetName(ByVal hWndParent As HWND) As String
    Dim ofn As OPENFILENAME
    Dim szFile As ZString * (MAX_PATH + 1) = ""
    ofn.lStructSize = SizeOf(OPENFILENAME)
    ofn.hwndOwner = hWndParent
    ofn.lpstrFilter = StrPtr(!"CSV Files\0*.csv\0All\0*.*\0\0")
    ofn.lpstrFile = @szFile
    ofn.nMaxFile = SizeOf(szFile)
    ofn.Flags = OFN_EXPLORER Or OFN_FILEMUSTEXIST
    If GetOpenFileName(@ofn) Then Return szFile Else Return ""
End Function

Function DistToSegment(px As Single, py As Single, x1 As Single, y1 As Single, x2 As Single, y2 As Single) As Single
    Dim dx As Single = x2 - x1
    Dim dy As Single = y2 - y1
    If dx = 0 And dy = 0 Then Return Sqr((px-x1)^2 + (py-y1)^2)
    Dim t As Single = ((px - x1) * dx + (py - y1) * dy) / (dx * dx + dy * dy)
    If t < 0 Then
        Return Sqr((px-x1)^2 + (py-y1)^2)
    ElseIf t > 1 Then
        Return Sqr((px-x2)^2 + (py-y2)^2)
    End If
    Return Sqr((px - (x1 + t * dx))^2 + (py - (y1 + t * dy))^2)
End Function

Const SNAP_RADIUS = 18

Sub SnapToCandle(mx As Integer, my As Integer)
    If QChart.IsLoaded = 0 Or g_stepX = 0 Then
        g_snapX = mx : g_snapY = my
        g_snapPrice = g_vMin + (g_oriY - my) / g_scaleY
        g_snapBar   = QChart.ViewStart + CInt((mx - g_oriX) / g_stepX)
        Exit Sub
    End If
    Dim barIdx As Integer = QChart.ViewStart + CInt((mx - g_oriX - g_stepX/2) / g_stepX)
    If barIdx < QChart.ViewStart Then barIdx = QChart.ViewStart
    Dim lastIdx As Integer = QChart.ViewStart + QChart.ViewCount - 1
    If lastIdx > UBound(QChart.History) Then lastIdx = UBound(QChart.History)
    If barIdx > lastIdx Then barIdx = lastIdx
    Dim As Double bestDist = 1e30, bestPrice = 0
    Dim As Single bestX = mx, bestY = my
    Dim As Integer bestBar = barIdx
    For b As Integer = barIdx - 1 To barIdx + 1
        If b < QChart.ViewStart Or b > lastIdx Then Continue For
        Dim P As PriceData = QChart.History(b)
        Dim cx As Single = g_oriX + (b - QChart.ViewStart) * g_stepX + (g_stepX/2)
        Dim prices(3) As Double
        prices(0) = P.O : prices(1) = P.H : prices(2) = P.L : prices(3) = P.C
        For k As Integer = 0 To 3
            Dim cy As Single = g_oriY - (prices(k) - g_vMin) * g_scaleY
            Dim dist As Double = Sqr((mx - cx)^2 + (my - cy)^2)
            If dist < bestDist Then
                bestDist = dist : bestPrice = prices(k)
                bestX = cx : bestY = cy : bestBar = b
            End If
        Next
    Next
    If bestDist <= SNAP_RADIUS Then
        g_snapX = bestX : g_snapY = bestY
        g_snapPrice = bestPrice : g_snapBar = bestBar
    Else
        g_snapX = mx : g_snapY = my
        g_snapPrice = g_vMin + (g_oriY - my) / g_scaleY
        g_snapBar   = QChart.ViewStart + CInt((mx - g_oriX) / g_stepX)
    End If
End Sub

Function RSIPanelTop(rsiIdx As Integer, mainChartH As Integer) As Integer
    Return mainChartH + RSI_PANEL_MARGIN + rsiIdx * (RSI_PANEL_H + RSI_PANEL_GAP)
End Function

' ── Charge un CSV dans un graphe spécifique (ChartWinData Ptr) ───────────────
Sub LoadCSVToChart(ByVal filename As String, pCD As ChartWinData Ptr, hWndParent As HWND)
    If pCD = NULL Then Exit Sub
    Dim As Integer f = FreeFile, count = 0
    Dim As String lineStr
    If Open(filename For Input As #f) <> 0 Then Exit Sub
    Do While Not Eof(f)
        Line Input #f, lineStr
        If Len(Trim(lineStr)) > 10 Then count += 1
    Loop
    Close #f
    If count = 0 Then Exit Sub
    ReDim pCD->Chart.History(count - 1)
    Open filename For Input As #f
    For i As Integer = 0 To count - 1
        Input #f, pCD->Chart.History(i).Dt, pCD->Chart.History(i).Tm, _
                  pCD->Chart.History(i).O,  pCD->Chart.History(i).H, _
                  pCD->Chart.History(i).L,  pCD->Chart.History(i).C, _
                  pCD->Chart.History(i).V
        pCD->Chart.History(i).Unix = DateToUnix(pCD->Chart.History(i).Dt, pCD->Chart.History(i).Tm)
    Next
    Close #f
    pCD->Chart.IsLoaded  = 1
    pCD->Chart.ViewCount = 60
    Dim As Integer maxStart = count - pCD->Chart.ViewCount
    If maxStart < 0 Then maxStart = 0
    pCD->Chart.ViewStart = maxStart
    ' Mettre à jour le global QChart si c'est le graphe actif (pour compatibilité scrollbar)
    If pCD->chartIdx = activeChartIdx Then
        SetScrollRange(hScroll, SB_CTL, 0, maxStart, TRUE)
        SetScrollPos(hScroll, SB_CTL, maxStart, TRUE)
        ' Synchro globale QChart pour les sous-systèmes qui en ont encore besoin
        QChart = pCD->Chart
    End If
    InvalidateRect(pCD->hwnd, NULL, FALSE)
End Sub

' ── Wrapper : charge dans le graphe actif (appelé depuis File > Ouvrir) ───────
Sub LoadCSV(ByVal filename As String, hWnd As HWND)
    Dim pCDA As ChartWinData Ptr = GetChartData(hCharts(activeChartIdx))
    LoadCSVToChart(filename, pCDA, hWnd)
End Sub

Sub ForceRedraw(hWnd As HWND)
    ' Invalider toutes les fenêtres graphe visibles
    Dim ci4 As Integer
    For ci4 = 0 To MAX_CHARTS - 1
        If hCharts(ci4) <> 0 Then InvalidateRect(hCharts(ci4), NULL, FALSE)
    Next
    If hCharts(0) = 0 Then InvalidateRect(hWnd, NULL, FALSE)
End Sub

' ── Ouvre la fenêtre Technicals pour un graphe donné (une seule instance) ────
Sub OpenTechnicalsForChart(hParent As HWND, chartIdx As Integer)
    ' Enregistrer la classe une seule fois (échec silencieux si déjà enregistrée)
    Dim wcI As WNDCLASS
    wcI.lpfnWndProc   = @IndicatorsDlgProc
    wcI.hInstance     = GetModuleHandle(NULL)
    wcI.hCursor       = LoadCursor(NULL, IDC_ARROW)
    wcI.hbrBackground = GetStockObject(WHITE_BRUSH)
    wcI.lpszClassName = StrPtr("IndWin")
    RegisterClass(@wcI)

    ' Vérifier qu'une fenêtre Technicals n'est pas déjà ouverte pour ce graphe
    ' (chercher une fenêtre enfant de hParent de classe "IndWin" avec le même USERDATA)
    Dim hExisting As HWND = GetWindow(hParent, GW_CHILD)
    Do While hExisting <> 0
        Dim clsName As ZString * 32
        GetClassName(hExisting, @clsName, 32)
        If clsName = "IndWin" Then
            Dim existIdx As Long = GetWindowLongPtr(hExisting, GWLP_USERDATA)
            If existIdx = chartIdx Then
                ' Déjà ouverte — mettre au premier plan
                SetForegroundWindow(hExisting)
                BringWindowToTop(hExisting)
                Return
            End If
        End If
        hExisting = GetWindow(hExisting, GW_HWNDNEXT)
    Loop

    ' Créer la fenêtre
    Dim hInd As HWND = CreateWindowEx(0, "IndWin", "Technicals", _
        WS_OVERLAPPED Or WS_CAPTION Or WS_SYSMENU Or WS_VISIBLE, _
        CW_USEDEFAULT, CW_USEDEFAULT, 260, 320, _
        hParent, NULL, GetModuleHandle(NULL), Cast(Any Ptr, CInt(chartIdx)))
End Sub

' ── Helpers de coordonnées canvas ─────────────────────────────────────────────

' Détermine dans quel canvas se trouve le point (mx, my)
'   0 = graphe principal,  1..N = index panel séparé (1-based),  -1 = hors canvas
Function HitTestCanvas(mx As Integer, my As Integer) As Integer
    If my >= ZOOM_BAR_H And my <= mainChartH_cached + ZOOM_BAR_H Then Return 0
    For i As Integer = 0 To PanelGeomCount - 1
        If my >= PanelGeoms(i).rTop And my <= PanelGeoms(i).rBottom Then Return i + 1
    Next
    Return -1
End Function

' Y écran → valeur dans l'espace réel du canvas
Function ScreenYToValue(my As Integer, canvasType As Integer) As Double
    If canvasType = 0 Then
        Return g_vMin + (g_oriY - my) / g_scaleY
    Else
        Dim idx As Integer = canvasType - 1
        If idx < 0 Or idx >= PanelGeomCount Then Return 0
        Dim rBottom As Integer = PanelGeoms(idx).rBottom
        Dim innerH  As Integer = PanelGeoms(idx).innerH
        Dim vMin    As Double  = PanelGeoms(idx).vMin
        Dim vMax    As Double  = PanelGeoms(idx).vMax
        If innerH = 0 Or vMax = vMin Then Return vMin
        Return vMin + (rBottom - my) * (vMax - vMin) / innerH
    End If
End Function

' Valeur dans l'espace réel du canvas → Y écran
Function ValueToScreenY(value As Double, canvasType As Integer) As Single
    If canvasType = 0 Then
        Return g_oriY - CSng((value - g_vMin) * g_scaleY)
    Else
        Dim idx As Integer = canvasType - 1
        If idx < 0 Or idx >= PanelGeomCount Then Return 0
        Dim rBottom As Integer = PanelGeoms(idx).rBottom
        Dim innerH  As Integer = PanelGeoms(idx).innerH
        Dim vMin    As Double  = PanelGeoms(idx).vMin
        Dim vMax    As Double  = PanelGeoms(idx).vMax
        If vMax = vMin Then Return rBottom
        Return rBottom - CSng((value - vMin) / (vMax - vMin)) * innerH
    End If
End Function

' Retourne l'index dans ActivePanels de l'overlay dont le label est sous (mx,my), ou -1.
Function HitTestOverlayLabel(mx As Integer, my As Integer) As Integer
    Dim globalIdx As Long = 0
    For i As Integer = 0 To ActiveCount - 1
        Dim def As IndicatorDef = indRegistry.defs(ActivePanels(i).defIndex)
        If def.isPanel = 0 Then
            Dim maPer2 As Long   = ActivePanels(i).period
            Dim maLbl2 As String = def.labelPrefix & "(" & maPer2 & ")"
            Dim lblX2 As Long    = g_oriX + 4
            Dim lblY2 As Long    = ZOOM_BAR_H + 14 + globalIdx * (RSI_CLOSE_BTN + 4)
            Dim zoneW As Long    = Len(maLbl2) * 7 + 3 + RSI_CLOSE_BTN + 2
            Dim zoneH As Long    = RSI_CLOSE_BTN + 2
            If mx >= lblX2 And mx <= lblX2 + zoneW And _
               my >= lblY2 - 1 And my <= lblY2 - 1 + zoneH Then
                Return i
            End If
            globalIdx += 1
        End If
    Next
    Return -1
End Function

' Retourne l'index dans ActivePanels du panel séparé dont la zone est sous (mx,my), ou -1.
Function HitTestPanelArea(mx As Integer, my As Integer) As Integer
    For i As Integer = 0 To PanelGeomCount - 1
        If my >= PanelGeoms(i).rTop And my <= PanelGeoms(i).rBottom Then
            Return PanelGeoms(i).activePanelIdx
        End If
    Next
    Return -1
End Function

Sub RenderChartGDIPlus(hWnd As HWND, hDC As HDC, w As Integer, h As Integer, pCD As ChartWinData Ptr)
    ' Alias locaux vers les champs du graphe courant
    ' Utilisation directe de pCD-> dans tout le corps de la fonction

    Dim rc As RECT
    rc.Left = 0 : rc.Top = 0 : rc.Right = w : rc.Bottom = h
    FillRect(hDC, @rc, GetStockObject(WHITE_BRUSH))

    Dim g As GpGraphics Ptr
    If GdipCreateFromHDC(hDC, @g) <> 0 Then Exit Sub
    GdipSetSmoothingMode(g, SmoothingModeAntiAlias)

    If pCD->Chart.IsLoaded = 0 Then
        Dim msgText As String = "Fichier > Ouvrir pour charger les donnees"
        TextOut(hDC, (w + toolbarW)\2 - 150, h\2, msgText, Len(msgText))
        GdipDeleteGraphics(g) : Exit Sub
    End If

    ' Compter les panneaux séparés (isPanel=1) pour la hauteur
    Dim panelCount As Long = 0
    For i As Integer = 0 To pCD->ActiveCount - 1
        If indRegistry.defs(pCD->ActivePanels(i).defIndex).isPanel = 1 Then panelCount += 1
    Next
    Dim As Integer rsiAreaH = panelCount * (RSI_PANEL_H + RSI_PANEL_GAP)
    Dim As Integer mainChartH = h - rsiAreaH - 40 - ZOOM_BAR_H

    ' 1. Echelle
    pCD->vMin = 1e30 : pCD->vMax = -1e30
    Dim As Integer lastIdx = pCD->Chart.ViewStart + pCD->Chart.ViewCount - 1
    If lastIdx > UBound(pCD->Chart.History) Then lastIdx = UBound(pCD->Chart.History)
    For i As Integer = pCD->Chart.ViewStart To lastIdx
        If pCD->Chart.History(i).L < pCD->vMin Then pCD->vMin = pCD->Chart.History(i).L
        If pCD->Chart.History(i).H > pCD->vMax Then pCD->vMax = pCD->Chart.History(i).H
    Next
    pCD->vMin *= 0.999 : pCD->vMax *= 1.001

    pCD->oriX = 65 + toolbarW : pCD->oriY = mainChartH + ZOOM_BAR_H
    Dim As Single lenX = w - 120 - toolbarW
    pCD->lenY = mainChartH - 40
    pCD->scaleY = IIf(pCD->vMax - pCD->vMin <> 0, pCD->lenY / (pCD->vMax - pCD->vMin), 1)
    pCD->stepX = lenX / pCD->Chart.ViewCount

    ' Mettre à jour les globales pour compatibilité avec les helpers (SnapToCandle, etc.)
    g_vMin   = pCD->vMin   : g_vMax   = pCD->vMax
    g_oriX   = pCD->oriX   : g_oriY   = pCD->oriY
    g_lenY   = pCD->lenY   : g_scaleY = pCD->scaleY
    g_stepX  = pCD->stepX

    ' 1a. Grille + labels axe Y
    Dim nYTicks As Integer = 6
    Dim yRange As Double = pCD->vMax - pCD->vMin
    Dim rawStep As Double = yRange / nYTicks
    Dim mag As Double = 10 ^ Int(Log(rawStep) / Log(10))
    Dim niceStep As Double
    Dim rr As Double = rawStep / mag
    If rr < 1.5 Then
        niceStep = 1 * mag
    ElseIf rr < 3.5 Then
        niceStep = 2 * mag
    ElseIf rr < 7.5 Then
        niceStep = 5 * mag
    Else
        niceStep = 10 * mag
    End If
    Dim firstTick As Double = Int(pCD->vMin / niceStep + 1) * niceStep
    Dim pGrid As GpPen Ptr : GdipCreatePen1(&HFFEEEEEE, 1.0, UnitPixel, @pGrid)
    Dim pAxis As GpPen Ptr : GdipCreatePen1(&HFFAAAAAA, 1.0, UnitPixel, @pAxis)
    SetBkMode(hDC, TRANSPARENT)
    SetTextColor(hDC, &H444444)
    Dim tick As Double = firstTick
    Do While tick <= pCD->vMax
        Dim yTick As Single = pCD->oriY - CSng((tick - pCD->vMin) * pCD->scaleY)
        If yTick >= ZOOM_BAR_H + 40 And yTick <= pCD->oriY Then
            GdipDrawLine(g, pGrid, pCD->oriX, yTick, pCD->oriX + lenX, yTick)
            GdipDrawLine(g, pAxis, pCD->oriX - 4, yTick, pCD->oriX, yTick)
            Dim priceStr As String
            If niceStep >= 1 Then
                priceStr = Str(CLng(tick))
            ElseIf niceStep >= 0.1 Then
                priceStr = Format(tick, "0.0")
            ElseIf niceStep >= 0.01 Then
                priceStr = Format(tick, "0.00")
            Else
                priceStr = Format(tick, "0.000")
            End If
            Dim txtW As Integer = Len(priceStr) * 6
            TextOut(hDC, CInt(pCD->oriX) - txtW - 6, CInt(yTick) - 7, priceStr, Len(priceStr))
        End If
        tick += niceStep
    Loop
    GdipDrawLine(g, pAxis, pCD->oriX, ZOOM_BAR_H + 40, pCD->oriX, pCD->oriY)
    GdipDeletePen(pGrid) : GdipDeletePen(pAxis)

    ' 1b. Labels axe X
    Dim minSpacePx As Single = 70.0
    Dim xStep As Integer = CInt(minSpacePx / pCD->stepX)
    If xStep < 1 Then xStep = 1
    Dim pAxisX As GpPen Ptr : GdipCreatePen1(&HFFAAAAAA, 1.0, UnitPixel, @pAxisX)
    GdipDrawLine(g, pAxisX, pCD->oriX, pCD->oriY, pCD->oriX + lenX, pCD->oriY)
    SetTextColor(hDC, &H444444)
    Dim xi As Integer = pCD->Chart.ViewStart
    Do While xi <= lastIdx
        Dim P As PriceData = pCD->Chart.History(xi)
        Dim xPos As Single = pCD->oriX + (xi - pCD->Chart.ViewStart) * pCD->stepX + (pCD->stepX / 2)
        GdipDrawLine(g, pAxisX, xPos, pCD->oriY, xPos, pCD->oriY + 4)
        Dim xLbl As String
        Dim dtStr As String = Trim(P.Dt)
        Dim tmStr As String = Trim(P.Tm)
        If Len(tmStr) >= 4 And tmStr <> "00:00" Then
            xLbl = tmStr
        Else
            If Len(dtStr) >= 10 Then
                xLbl = Mid(dtStr, 9, 2) & "/" & Mid(dtStr, 6, 2)
            Else
                xLbl = dtStr
            End If
        End If
        Dim lw As Integer = Len(xLbl) * 6
        TextOut(hDC, CInt(xPos) - lw \ 2, pCD->oriY + 6, xLbl, Len(xLbl))
        xi += xStep
    Loop
    GdipDeletePen(pAxisX)
    SetTextColor(hDC, 0)

    ' 2. Bougies
    For i As Integer = pCD->Chart.ViewStart To lastIdx
        Dim Pb As PriceData = pCD->Chart.History(i)
        Dim As Single x = pCD->oriX + (i - pCD->Chart.ViewStart) * pCD->stepX + (pCD->stepX/2)
        Dim As Single yO = pCD->oriY - (Pb.O - pCD->vMin) * pCD->scaleY
        Dim As Single yC = pCD->oriY - (Pb.C - pCD->vMin) * pCD->scaleY
        Dim As Single yH = pCD->oriY - (Pb.H - pCD->vMin) * pCD->scaleY
        Dim As Single yL = pCD->oriY - (Pb.L - pCD->vMin) * pCD->scaleY
        Dim col As UInteger
        If Pb.C >= Pb.O Then col = &HFF00C800 Else col = &HFFFF0000
        Dim penC As GpPen Ptr
        GdipCreatePen1(col, 1.0, UnitPixel, @penC)
        GdipDrawLineI(g, penC, CInt(x), CInt(yH), CInt(x), CInt(yL))
        Dim tY As Single, bY As Single
        If yO < yC Then : tY = yO : bY = yC : Else : tY = yC : bY = yO : End If
        Dim brBody As GpBrush Ptr : GdipCreateSolidFill(col, @brBody)
        GdipFillRectangleI(g, brBody, CInt(x - (g_stepX*0.35)), CInt(tY), CInt(g_stepX*0.7), CInt(bY-tY+1))
        GdipDeleteBrush(brBody) : GdipDeletePen(penC)
    Next

    ' 3. Rendu des indicateurs via le registre
    Dim totalBars As Long = UBound(pCD->Chart.History) + 1
    Dim Closes     (totalBars - 1) As Double
    Dim Opens      (totalBars - 1) As Double
    Dim Highs      (totalBars - 1) As Double
    Dim Lows       (totalBars - 1) As Double
    Dim Volumes    (totalBars - 1) As Double
    Dim Weekdays   (totalBars - 1) As Long
    Dim CurUnixTs  (totalBars - 1) As Double   ' timestamps Unix du TF courant
    For ci As Long = 0 To totalBars - 1
        Closes  (ci) = pCD->Chart.History(ci).C
        Opens   (ci) = pCD->Chart.History(ci).O
        Highs   (ci) = pCD->Chart.History(ci).H
        Lows    (ci) = pCD->Chart.History(ci).L
        Volumes (ci) = CDbl(pCD->Chart.History(ci).V)
        CurUnixTs(ci) = pCD->Chart.History(ci).Unix
        Dim dtStr2 As String = Trim(pCD->Chart.History(ci).Dt)
        If Len(dtStr2) >= 10 Then
            Dim yr As Integer = CInt(Mid(dtStr2, 1, 4))
            Dim mo As Integer = CInt(Mid(dtStr2, 6, 2))
            Dim dy As Integer = CInt(Mid(dtStr2, 9, 2))
            Weekdays(ci) = Weekday(DateSerial(yr, mo, dy)) - 1
        Else
            Weekdays(ci) = -1
        End If
    Next

    ' Mise en cache des géométries pour le hit-test des trendlines
    pCD->mainChartH_cached = mainChartH
    pCD->PanelGeomCount = 0

    ' Contexte graphique partagé
    Dim ctx As ChartCtx
    ctx.oriX       = pCD->oriX
    ctx.oriY       = pCD->oriY
    ctx.stepX      = pCD->stepX
    ctx.lenX       = lenX
    ctx.vMin       = pCD->vMin
    ctx.scaleY     = pCD->scaleY
    ctx.mainChartH = CLng(mainChartH)
    ctx.viewStart  = CLng(pCD->Chart.ViewStart)
    ctx.lastIdx    = CLng(lastIdx)
    ctx.refHighs      = NULL
    ctx.refLows       = NULL
    ctx.refOpens      = NULL
    ctx.refTimestamps = NULL
    ctx.refCount      = 0
    ctx.refTFMinutes  = 0
    ctx.curTimestamps = @CurUnixTs(0)   ' timestamps du TF courant pour IBarShift

    ' Tableaux pour les données du TF de référence (ADR112 et indicateurs multi-TF)
    ' Déclarés ici avec taille fixe max pour éviter les pointeurs invalides
    Const MAX_REF_BARS = 4096
    Dim refH_buf (MAX_REF_BARS - 1) As Double
    Dim refL_buf (MAX_REF_BARS - 1) As Double
    Dim refO_buf (MAX_REF_BARS - 1) As Double
    Dim refTS_buf(MAX_REF_BARS - 1) As Double

    ' Compteurs d'index
    Dim globalOverlayIdx As Long = 0  ' index global parmi TOUS les overlays (position label)
    Dim panelIdx         As Long = 0  ' index global parmi TOUS les panels séparés

    ' Première passe : overlays (dessinés sur les bougies)
    For i As Integer = 0 To pCD->ActiveCount - 1
        Dim defIdx As Long = pCD->ActivePanels(i).defIndex
        Dim def As IndicatorDef = indRegistry.defs(defIdx)
        If def.isPanel = 0 And def.drawOverlay <> 0 Then

            ctx.refHighs      = NULL : ctx.refLows    = NULL : ctx.refOpens      = NULL
            ctx.refTimestamps = NULL : ctx.refCount   = 0    : ctx.refTFMinutes  = 0

            If Len(Trim(def.param2Label)) > 0 Then
                Dim refTF As Long = 0
                Select Case pCD->ActivePanels(i).param2
                    Case 0 : refTF = 1440
                    Case 1 : refTF = 10080
                    Case 2 : refTF = 43200
                End Select

                If refTF > 0 Then
                    Dim refHistCount As Long = 0
                    Select Case refTF
                        Case 1440
                            If QChart1440.IsLoaded Then refHistCount = UBound(QChart1440.History) + 1
                        Case 10080
                            If QChart10080.IsLoaded Then refHistCount = UBound(QChart10080.History) + 1
                        Case 43200
                            If QChart43200.IsLoaded Then refHistCount = UBound(QChart43200.History) + 1
                    End Select

                    If refHistCount > 0 And refHistCount <= MAX_REF_BARS Then
                        ' Copier dans les tableaux pré-alloués (portée garantie)
                        For rj As Long = 0 To refHistCount - 1
                            Select Case refTF
                                Case 1440
                                    refH_buf (rj) = QChart1440.History(rj).H
                                    refL_buf (rj) = QChart1440.History(rj).L
                                    refO_buf (rj) = QChart1440.History(rj).O
                                    refTS_buf(rj) = QChart1440.History(rj).Unix
                                Case 10080
                                    refH_buf (rj) = QChart10080.History(rj).H
                                    refL_buf (rj) = QChart10080.History(rj).L
                                    refO_buf (rj) = QChart10080.History(rj).O
                                    refTS_buf(rj) = QChart10080.History(rj).Unix
                                Case 43200
                                    refH_buf (rj) = QChart43200.History(rj).H
                                    refL_buf (rj) = QChart43200.History(rj).L
                                    refO_buf (rj) = QChart43200.History(rj).O
                                    refTS_buf(rj) = QChart43200.History(rj).Unix
                            End Select
                        Next rj

                        ctx.refHighs      = @refH_buf(0)
                        ctx.refLows       = @refL_buf(0)
                        ctx.refOpens      = @refO_buf(0)
                        ctx.refTimestamps = @refTS_buf(0)
                        ctx.refCount      = refHistCount
                        ctx.refTFMinutes  = refTF

                        def.drawOverlay(g, hDC, @Closes(0), @Opens(0), @Highs(0), @Lows(0), @Volumes(0), @Weekdays(0), totalBars, _
                            pCD->ActivePanels(i).period, pCD->ActivePanels(i).param2, globalOverlayIdx, @ctx, CLng(RSI_CLOSE_BTN), @MA_Colors(0))
                        globalOverlayIdx += 1
                        ctx.refHighs = NULL : ctx.refLows = NULL : ctx.refOpens = NULL
                        ctx.refTimestamps = NULL : ctx.refCount = 0 : ctx.refTFMinutes = 0
                        Continue For
                    End If
                End If
            End If

            ' Indicateur sans TF de référence — appel direct
            def.drawOverlay(g, hDC, @Closes(0), @Opens(0), @Highs(0), @Lows(0), @Volumes(0), @Weekdays(0), totalBars, _
                pCD->ActivePanels(i).period, pCD->ActivePanels(i).param2, globalOverlayIdx, @ctx, CLng(RSI_CLOSE_BTN), @MA_Colors(0))
            globalOverlayIdx += 1
        End If
    Next

    ' Réinitialiser les champs ref après la boucle overlay
    ctx.refHighs = NULL : ctx.refLows = NULL : ctx.refOpens = NULL : ctx.refCount = 0

    ' Deuxième passe : panels séparés (sous le graphe principal)
    ' ctx.mainChartH inclut RSI_PANEL_MARGIN pour que le cpp n'ait pas à connaître cette constante.
    ' Le cpp calcule : rTop = ctx.mainChartH + panelIndex * (panelH + panelGap)
    ctx.mainChartH = CLng(mainChartH) + RSI_PANEL_MARGIN

    ' Buffers pré-alloués pour passer QChart1 au CVD (sub-TF volumes)
    Static cvdVol1 (MAX_REF_BARS - 1) As Double
    Static cvdCls1 (MAX_REF_BARS - 1) As Double
    Static cvdOpn1 (MAX_REF_BARS - 1) As Double
    Static cvdTS1  (MAX_REF_BARS - 1) As Double

    For i As Integer = 0 To pCD->ActiveCount - 1
        Dim defIdx As Long = pCD->ActivePanels(i).defIndex
        Dim def As IndicatorDef = indRegistry.defs(defIdx)
        If def.isPanel = 1 And def.drawPanel <> 0 Then
            Dim totalPanelCount As Long = CountPanels(defIdx)
            Dim pVMin As Double = 0.0, pVMax As Double = 100.0

            ' ── CVD : injecter QChart1 comme sub-TF via ctx.ref* ─────────────
            ctx.refHighs      = NULL : ctx.refLows    = NULL
            ctx.refOpens      = NULL : ctx.refTimestamps = NULL
            ctx.refCount      = 0   : ctx.refTFMinutes  = 0

            If Trim(def.name) = "CVD" And QChart1.IsLoaded Then
                Dim cvdN As Long = UBound(QChart1.History) + 1
                If cvdN > MAX_REF_BARS Then cvdN = MAX_REF_BARS
                For rj As Long = 0 To cvdN - 1
                    cvdVol1(rj) = QChart1.History(rj).V
                    cvdCls1(rj) = QChart1.History(rj).C
                    cvdOpn1(rj) = QChart1.History(rj).O
                    cvdTS1 (rj) = QChart1.History(rj).Unix
                Next rj
                ctx.refHighs      = @cvdVol1(0)
                ctx.refLows       = @cvdCls1(0)
                ctx.refOpens      = @cvdOpn1(0)
                ctx.refTimestamps = @cvdTS1(0)
                ctx.refCount      = cvdN
                ctx.refTFMinutes  = 1
            End If

            def.drawPanel(g, hDC, @Closes(0), @Opens(0), @Highs(0), @Lows(0), @Volumes(0), @Weekdays(0), totalBars, _
                pCD->ActivePanels(i).period, pCD->ActivePanels(i).param2, panelIdx, totalPanelCount, _
                @ctx, CLng(RSI_PANEL_H), CLng(RSI_PANEL_GAP), CLng(RSI_CLOSE_BTN), _
                @pVMin, @pVMax)

            ctx.refHighs = NULL : ctx.refLows = NULL : ctx.refOpens = NULL
            ctx.refTimestamps = NULL : ctx.refCount = 0 : ctx.refTFMinutes = 0

            ' Mémoriser la géométrie pour le hit-test
            Dim pInnerH As Integer = RSI_PANEL_H - 20
            pCD->PanelGeoms(pCD->PanelGeomCount).rTop           = mainChartH + RSI_PANEL_MARGIN + panelIdx * (RSI_PANEL_H + RSI_PANEL_GAP)
            pCD->PanelGeoms(pCD->PanelGeomCount).rBottom        = pCD->PanelGeoms(pCD->PanelGeomCount).rTop + pInnerH
            pCD->PanelGeoms(pCD->PanelGeomCount).innerH         = pInnerH
            pCD->PanelGeoms(pCD->PanelGeomCount).vMin           = pVMin
            pCD->PanelGeoms(pCD->PanelGeomCount).vMax           = pVMax
            pCD->PanelGeoms(pCD->PanelGeomCount).activePanelIdx = i
            pCD->PanelGeomCount += 1
            panelIdx += 1
        End If
    Next

    ' 4. Trendlines — rendu dans le bon canvas selon canvasType
    Dim pL As GpPen Ptr : GdipCreatePen1(&HFF444444, 2.0, UnitPixel, @pL)
    For i As Integer = 0 To UBound(pCD->Lines)
        Dim x1 As Single = pCD->oriX + (pCD->Lines(i).bar1 - pCD->Chart.ViewStart) * pCD->stepX + (pCD->stepX/2)
        Dim y1 As Single = ValueToScreenY(pCD->Lines(i).price1, pCD->Lines(i).canvasType)
        Dim x2 As Single = pCD->oriX + (pCD->Lines(i).bar2 - pCD->Chart.ViewStart) * pCD->stepX + (pCD->stepX/2)
        Dim y2 As Single = ValueToScreenY(pCD->Lines(i).price2, pCD->Lines(i).canvasType)
        GdipDrawLine(g, pL, x1, y1, x2, y2)
    Next
    If pCD->isDrawing = 1 Then
        Dim mP As POINT : GetCursorPos(@mP) : ScreenToClient(hWnd, @mP)
        If pCD->tmpCanvasType = 0 Then
            SnapToCandle(mP.x, mP.y)
        Else
            g_snapX = mP.x : g_snapY = mP.y
        End If
        Dim x1snap As Single = pCD->oriX + (pCD->tmpBar - pCD->Chart.ViewStart) * pCD->stepX + (pCD->stepX/2)
        Dim y1snap As Single = ValueToScreenY(pCD->tmpPrice, pCD->tmpCanvasType)
        GdipDrawLine(g, pL, x1snap, y1snap, g_snapX, g_snapY)
        Dim pSnap As GpPen Ptr : GdipCreatePen1(&HFF0088FF, 1.5, UnitPixel, @pSnap)
        GdipDrawEllipse(g, pSnap, g_snapX - 5, g_snapY - 5, 10, 10)
        GdipDeletePen(pSnap)
    End If
    GdipDeletePen(pL)

    ' Dessiner les cercles sauvegardés
    If UBound(pCD->Circles) >= 0 Then
        Dim pC As GpPen Ptr : GdipCreatePen1(&HFF444444, 2.0, UnitPixel, @pC)
        For i As Integer = 0 To UBound(pCD->Circles)
            Dim px1 As Single = pCD->oriX + (pCD->Circles(i).bar1 - pCD->Chart.ViewStart) * pCD->stepX + pCD->stepX * 0.5
            Dim py1 As Single = ValueToScreenY(pCD->Circles(i).price1, 0)
            Dim px2 As Single = pCD->oriX + (pCD->Circles(i).bar2 - pCD->Chart.ViewStart) * pCD->stepX + pCD->stepX * 0.5
            Dim py2 As Single = ValueToScreenY(pCD->Circles(i).price2, 0)
            Dim px3 As Single = pCD->oriX + (pCD->Circles(i).bar3 - pCD->Chart.ViewStart) * pCD->stepX + pCD->stepX * 0.5
            Dim py3 As Single = ValueToScreenY(pCD->Circles(i).price3, 0)
            Dim yda As Double = py2 - py1
            Dim xda As Double = px2 - px1
            Dim ydb As Double = py3 - py2
            Dim xdb As Double = px3 - px2
            If Abs(xda) > 0.001 And Abs(xdb) > 0.001 Then
                Dim aSlp As Double = yda / xda
                Dim bSlp As Double = ydb / xdb
                If Abs(bSlp - aSlp) > 0.001 Then
                    Dim ccx As Single = CSng((aSlp * bSlp * (py1 - py3) + _
                                   bSlp * (px1 + px2) - _
                                   aSlp * (px2 + px3)) / (2.0 * (bSlp - aSlp)))
                    Dim ccy As Single = CSng(-1.0 * (ccx - (px1 + px2) / 2.0) / aSlp + (py1 + py2) / 2.0)
                    Dim aax As Double = px1 - ccx
                    Dim bby As Double = py1 - ccy
                    Dim cirR As Single = CSng(Sqr(aax*aax + bby*bby))
                    If cirR > 1.0 Then
                        GdipDrawEllipse(g, pC, ccx - cirR, ccy - cirR, cirR * 2, cirR * 2)
                    End If
                End If
            End If
        Next
        GdipDeletePen(pC)
    End If

    ' Aperçu cercle en cours
    If pCD->currentTool = ID_TOOL_CIRCLE And pCD->circleClickNb > 0 Then
        Dim pDot As GpPen Ptr : GdipCreatePen1(&HFF0088FF, 1.5, UnitPixel, @pDot)
        For i As Integer = 1 To circleClickNb
            ' Recalculer position pixel depuis bar/price stockés
            Dim dotX As Single = pCD->oriX + (pCD->circleBar(i) - pCD->Chart.ViewStart) * pCD->stepX + pCD->stepX * 0.5
            Dim dotY As Single = ValueToScreenY(pCD->circlePrice(i), 0)
            GdipDrawEllipse(g, pDot, dotX - 4, dotY - 4, 8, 8)
        Next
        GdipDeletePen(pDot)
    End If

    ' ── Fibonacci Fans ────────────────────────────────────────────────────
    Dim fiboRatios(4) As Double
    fiboRatios(0) = 0.309   ' 23.6%
    fiboRatios(1) = 0.618   ' 38.2%
    fiboRatios(2) = 1.0     ' 50%
    fiboRatios(3) = 1.618   ' 61.8%
    fiboRatios(4) = 3.618   ' 78.6%
    Dim fiboLbls(4) As String
    fiboLbls(0) = "23.6%" : fiboLbls(1) = "38.2%" : fiboLbls(2) = "50%"
    fiboLbls(3) = "61.8%" : fiboLbls(4) = "78.6%"
    Dim fiboCols(4) As ULong
    fiboCols(0) = &HFF00AA88 : fiboCols(1) = &HFF0088CC : fiboCols(2) = &HFFCC8800
    fiboCols(3) = &HFFCC4400 : fiboCols(4) = &HFFCC0000

    Dim chartRightX As Single = pCD->oriX + (winW - 120 - toolbarW)

    If UBound(pCD->FiboFans) >= 0 Then
        For i As Integer = 0 To UBound(pCD->FiboFans)
            Dim ffx1 As Single = pCD->oriX + (pCD->FiboFans(i).bar1 - pCD->Chart.ViewStart) * pCD->stepX + pCD->stepX * 0.5
            Dim ffy1 As Single = ValueToScreenY(pCD->FiboFans(i).price1, 0)
            Dim ffx2 As Single = pCD->oriX + (pCD->FiboFans(i).bar2 - pCD->Chart.ViewStart) * pCD->stepX + pCD->stepX * 0.5
            Dim ffy2 As Single = ValueToScreenY(pCD->FiboFans(i).price2, 0)
            Dim ffdx As Single = ffx2 - ffx1

            ' Ligne de base P1→P2 en tirets gris
            Dim pBase As GpPen Ptr : GdipCreatePen1(&HFF888888, 1.0, UnitPixel, @pBase)
            GdipSetPenDashStyle(pBase, DashStyleDash)
            GdipDrawLine(g, pBase, ffx1, ffy1, ffx2, ffy2)
            GdipDeletePen(pBase)

            ' 5 rayons Fibonacci
            For j As Integer = 0 To 4
                ' Point cible sur la verticale prolongée de P2
                Dim ffx4 As Single = ffx2 + ffdx * CSng(fiboRatios(j))
                Dim ffRdx As Single = ffx4 - ffx1
                Dim ffRdy As Single = ffy2  - ffy1
                ' Prolonger jusqu'au bord droit du graphe
                Dim ffEndX As Single = chartRightX
                Dim ffEndY As Single = ffy1
                If Abs(ffRdx) > 0.001 Then
                    Dim ffT As Single = (chartRightX - ffx1) / ffRdx
                    ffEndY = ffy1 + ffRdy * ffT
                End If
                Dim pFib As GpPen Ptr : GdipCreatePen1(fiboCols(j), 1.5, UnitPixel, @pFib)
                GdipDrawLine(g, pFib, ffx1, ffy1, ffEndX, ffEndY)
                GdipDeletePen(pFib)
                ' Label au croisement avec la verticale de P2
                SetBkMode(hDC, TRANSPARENT)
                SetTextColor(hDC, fiboCols(j) And &HFFFFFF)
                TextOutA(hDC, CInt(ffx4) - 25, CInt(ffy2) - 8, StrPtr(fiboLbls(j)), Len(fiboLbls(j)))
            Next j
        Next i
        SetTextColor(hDC, 0)
    End If

    ' Aperçu FiboFan : 1er point posé, fan complet vers la souris en temps réel
    If pCD->currentTool = ID_TOOL_FIBOFAN And pCD->fiboFanClickNb = 1 Then
        Dim mPF As POINT : GetCursorPos(@mPF) : ScreenToClient(hWnd, @mPF)
        Dim fpx1 As Single = pCD->oriX + (pCD->fiboFanBar1 - pCD->Chart.ViewStart) * pCD->stepX + pCD->stepX * 0.5
        Dim fpy1 As Single = ValueToScreenY(pCD->fiboFanPrice1, 0)
        Dim fpx2 As Single = CSng(mPF.x)
        Dim fpy2 As Single = CSng(mPF.y)
        Dim fpdx As Single = fpx2 - fpx1
        Dim fpchartRight As Single = g_oriX + (winW - 120 - toolbarW)

        ' Ligne de base en tirets
        Dim pPrev As GpPen Ptr : GdipCreatePen1(&HFF888888, 1.0, UnitPixel, @pPrev)
        GdipSetPenDashStyle(pPrev, DashStyleDash)
        GdipDrawLine(g, pPrev, fpx1, fpy1, fpx2, fpy2)
        GdipDeletePen(pPrev)

        ' 5 rayons en temps réel
        Dim fpRatios(4) As Double
        fpRatios(0) = 0.309 : fpRatios(1) = 0.618 : fpRatios(2) = 1.0
        fpRatios(3) = 1.618 : fpRatios(4) = 3.618
        Dim fpLbls(4) As String
        fpLbls(0) = "23.6%" : fpLbls(1) = "38.2%" : fpLbls(2) = "50%"
        fpLbls(3) = "61.8%" : fpLbls(4) = "78.6%"
        Dim fpCols(4) As ULong
        fpCols(0) = &HFF00AA88 : fpCols(1) = &HFF0088CC : fpCols(2) = &HFFCC8800
        fpCols(3) = &HFFCC4400 : fpCols(4) = &HFFCC0000

        For j As Integer = 0 To 4
            Dim fpx4 As Single = fpx2 + fpdx * CSng(fpRatios(j))
            Dim fpRdx As Single = fpx4 - fpx1
            Dim fpRdy As Single = fpy2  - fpy1
            Dim fpEndX As Single = fpchartRight
            Dim fpEndY As Single = fpy1
            If Abs(fpRdx) > 0.001 Then
                Dim fpTmp As Single = (fpchartRight - fpx1) / fpRdx
                fpEndY = fpy1 + fpRdy * fpTmp
            End If
            Dim pFp As GpPen Ptr : GdipCreatePen1(fpCols(j) And &HAAFFFFFF, 1.2, UnitPixel, @pFp)
            GdipDrawLine(g, pFp, fpx1, fpy1, fpEndX, fpEndY)
            GdipDeletePen(pFp)
            SetBkMode(hDC, TRANSPARENT)
            SetTextColor(hDC, fpCols(j) And &HFFFFFF)
            TextOutA(hDC, CInt(fpx4) - 25, CInt(fpy2) - 8, StrPtr(fpLbls(j)), Len(fpLbls(j)))
        Next j
        SetTextColor(hDC, 0)

        ' Point pivot
        Dim pPiv As GpPen Ptr : GdipCreatePen1(&HFF0088FF, 1.5, UnitPixel, @pPiv)
        GdipDrawEllipse(g, pPiv, fpx1 - 4, fpy1 - 4, 8, 8)
        GdipDeletePen(pPiv)
    End If

    ' ── Gann Fans ─────────────────────────────────────────────────────────
    Dim gannChartRight As Single = pCD->oriX + (winW - 120 - toolbarW)
    Dim gannCols(8) As ULong
    gannCols(0)=&HFFCC8800:gannCols(1)=&HFFCC6600:gannCols(2)=&HFFCC4400:gannCols(3)=&HFFCC2200
    gannCols(4)=&HFF888888:gannCols(5)=&HFF0066CC:gannCols(6)=&HFF0044CC:gannCols(7)=&HFF0022CC:gannCols(8)=&HFF0000CC
    Dim gannLbls(8) As String
    gannLbls(0)="1:8":gannLbls(1)="1:4":gannLbls(2)="1:3":gannLbls(3)="1:2"
    gannLbls(4)="1:1":gannLbls(5)="2:1":gannLbls(6)="3:1":gannLbls(7)="4:1":gannLbls(8)="8:1"
    Dim gannXM(3) As Double : gannXM(0)=2:gannXM(1)=3:gannXM(2)=4:gannXM(3)=8
    Dim gannYM(3) As Double : gannYM(0)=2:gannYM(1)=3:gannYM(2)=4:gannYM(3)=8

    ' Rendu d'un Gann Fan depuis (gx1,gy1)→(gx2,gy2), alpha=255 définitif, 170 aperçu
    Dim As Single gfRenderX1, gfRenderY1, gfRenderX2, gfRenderY2
    Dim gfRenderAlpha As Integer
    Dim gfPass As Integer

    For gfPass = 0 To (UBound(pCD->GannFans) + 1) + 1
        ' gfPass 0..UBound = fans définitifs, dernier pass = aperçu si actif
        If gfPass <= UBound(pCD->GannFans) Then
            gfRenderX1 = pCD->oriX + (pCD->GannFans(gfPass).bar1 - pCD->Chart.ViewStart) * pCD->stepX + pCD->stepX * 0.5
            gfRenderY1 = ValueToScreenY(pCD->GannFans(gfPass).price1, 0)
            gfRenderX2 = pCD->oriX + (pCD->GannFans(gfPass).bar2 - pCD->Chart.ViewStart) * pCD->stepX + pCD->stepX * 0.5
            gfRenderY2 = ValueToScreenY(pCD->GannFans(gfPass).price2, 0)
            gfRenderAlpha = 255
        ElseIf pCD->currentTool = ID_TOOL_GANNFAN And pCD->gannFanClickNb = 1 Then
            Dim mPG As POINT : GetCursorPos(@mPG) : ScreenToClient(hWnd, @mPG)
            gfRenderX1 = pCD->oriX + (pCD->gannFanBar1 - pCD->Chart.ViewStart) * pCD->stepX + pCD->stepX * 0.5
            gfRenderY1 = ValueToScreenY(pCD->gannFanPrice1, 0)
            gfRenderX2 = mPG.x
            gfRenderY2 = mPG.y
            gfRenderAlpha = 170
        Else
            Exit For
        End If

        Dim _gdx As Single = gfRenderX2 - gfRenderX1
        Dim _gdy As Single = gfRenderY2 - gfRenderY1
        SetBkMode(hDC, TRANSPARENT)

        ' 1:1
        Dim _pG As GpPen Ptr
        Dim _alphaCol As ULong = (CLng(gfRenderAlpha) Shl 24) Or (gannCols(4) And &HFFFFFF)
        GdipCreatePen1(_alphaCol, 1.8, UnitPixel, @_pG)
        If Abs(_gdx) > 0.001 Then
            GdipDrawLine(g, _pG, gfRenderX1, gfRenderY1, gannChartRight, gfRenderY1 + _gdy * (gannChartRight - gfRenderX1) / _gdx)
        End If
        GdipDeletePen(_pG)
        SetTextColor(hDC, gannCols(4) And &HFFFFFF)
        TextOutA(hDC, CInt(gfRenderX2)-25, CInt(gfRenderY2)-8, StrPtr(gannLbls(4)), Len(gannLbls(4)))

        ' Rayons X étiré : x4 = x1 + dx*k, y reste y2
        Dim _j As Integer
        For _j = 0 To 3
            Dim _tx4 As Single = gfRenderX1 + _gdx * CSng(gannXM(_j))
            Dim _tRdx As Single = _tx4 - gfRenderX1
            Dim _tEndY As Single = gfRenderY1
            If Abs(_tRdx) > 0.001 Then _tEndY = gfRenderY1 + _gdy * (gannChartRight - gfRenderX1) / _tRdx
            _alphaCol = (CLng(gfRenderAlpha) Shl 24) Or (gannCols(5+_j) And &HFFFFFF)
            GdipCreatePen1(_alphaCol, 1.3, UnitPixel, @_pG)
            GdipDrawLine(g, _pG, gfRenderX1, gfRenderY1, gannChartRight, _tEndY)
            GdipDeletePen(_pG)
            SetTextColor(hDC, gannCols(5+_j) And &HFFFFFF)
            TextOutA(hDC, CInt(_tx4)-25, CInt(gfRenderY2)-8, StrPtr(gannLbls(5+_j)), Len(gannLbls(5+_j)))
        Next _j

        ' Rayons Y étiré : y4 = y2 - (y2-y1)*k/... , x reste x2
        ' y4 = y1 - (y1-y2)*k  = y1 + (y2-y1)*k = y1 + gdy*k
        For _j = 0 To 3
            Dim _ty4 As Single = gfRenderY1 + _gdy * CSng(gannYM(_j))
            Dim _tRdx2 As Single = gfRenderX2 - gfRenderX1
            Dim _tEndY2 As Single = _ty4
            If Abs(_tRdx2) > 0.001 Then _tEndY2 = gfRenderY1 + (_ty4 - gfRenderY1) * (gannChartRight - gfRenderX1) / _tRdx2
            _alphaCol = (CLng(gfRenderAlpha) Shl 24) Or (gannCols(3-_j) And &HFFFFFF)
            GdipCreatePen1(_alphaCol, 1.3, UnitPixel, @_pG)
            GdipDrawLine(g, _pG, gfRenderX1, gfRenderY1, gannChartRight, _tEndY2)
            GdipDeletePen(_pG)
            SetTextColor(hDC, gannCols(3-_j) And &HFFFFFF)
            TextOutA(hDC, CInt(gfRenderX2)-25, CInt(_ty4)-8, StrPtr(gannLbls(3-_j)), Len(gannLbls(3-_j)))
        Next _j
        SetTextColor(hDC, 0)

        ' Point pivot sur aperçu
        If gfRenderAlpha < 255 Then
            Dim pGPiv As GpPen Ptr : GdipCreatePen1(&HFF0088FF, 1.5, UnitPixel, @pGPiv)
            GdipDrawEllipse(g, pGPiv, gfRenderX1 - 4, gfRenderY1 - 4, 8, 8)
            GdipDeletePen(pGPiv)
        End If
    Next gfPass

    ' ── Fibonacci Retracements ────────────────────────────────────────────
    ' Lignes horizontales de x1 à x2 aux ratios 0%, 23.6%, 38.2%, 50%, 61.8%, 78.6%, 100%
    ' y4 = y2 - (y2-y1)*ratio  où y1=price1(haut/100%) y2=price2(bas/0%)
    Dim frLevels(6) As Double
    frLevels(0)=0.0:frLevels(1)=0.236:frLevels(2)=0.382:frLevels(3)=0.5
    frLevels(4)=0.618:frLevels(5)=0.786:frLevels(6)=1.0
    Dim frLabels(6) As String
    frLabels(0)="0%":frLabels(1)="23.6%":frLabels(2)="38.2%":frLabels(3)="50%"
    frLabels(4)="61.8%":frLabels(5)="78.6%":frLabels(6)="100%"
    Dim frCols(6) As ULong
    frCols(0)=&HFF888888:frCols(1)=&HFF00AA88:frCols(2)=&HFF0088CC
    frCols(3)=&HFFCC8800:frCols(4)=&HFFCC4400:frCols(5)=&HFFCC0000:frCols(6)=&HFF888888

    ' Rendu d'un FiboRet depuis (frX1,frY1)→(frX2,frY2), alpha=255 définitif, 170 aperçu
    Dim As Single frRX1, frRY1, frRX2, frRY2
    Dim frRAlpha As Integer
    Dim frPass   As Integer

    For frPass = 0 To (UBound(pCD->FiboRets) + 1) + 1
        If frPass <= UBound(pCD->FiboRets) Then
            frRX1    = pCD->oriX + (pCD->FiboRets(frPass).bar1 - pCD->Chart.ViewStart) * pCD->stepX + pCD->stepX * 0.5
            frRY1    = ValueToScreenY(pCD->FiboRets(frPass).price1, 0)
            frRX2    = pCD->oriX + (pCD->FiboRets(frPass).bar2 - pCD->Chart.ViewStart) * pCD->stepX + pCD->stepX * 0.5
            frRY2    = ValueToScreenY(pCD->FiboRets(frPass).price2, 0)
            frRAlpha = 255
        ElseIf pCD->currentTool = ID_TOOL_FIBORET And pCD->fiboRetClickNb = 1 Then
            Dim mPFR As POINT : GetCursorPos(@mPFR) : ScreenToClient(hWnd, @mPFR)
            frRX1    = pCD->oriX + (pCD->fiboRetBar1 - pCD->Chart.ViewStart) * pCD->stepX + pCD->stepX * 0.5
            frRY1    = ValueToScreenY(pCD->fiboRetPrice1, 0)
            frRX2    = CSng(mPFR.x)
            frRY2    = CSng(mPFR.y)
            frRAlpha = 170
        Else
            Exit For
        End If

        ' Ligne diagonale P1→P2 en tirets
        Dim _frPBase As GpPen Ptr
        GdipCreatePen1((CLng(frRAlpha) Shl 24) Or &H888888, 1.0, UnitPixel, @_frPBase)
        GdipSetPenDashStyle(_frPBase, DashStyleDash)
        GdipDrawLine(g, _frPBase, frRX1, frRY1, frRX2, frRY2)
        GdipDeletePen(_frPBase)

        ' 7 niveaux horizontaux
        Dim _frJ As Integer
        Dim _frXleft  As Single = IIf(frRX1 < frRX2, frRX1, frRX2)
        Dim _frXright As Single = IIf(frRX1 < frRX2, frRX2, frRX1)
        SetBkMode(hDC, TRANSPARENT)
        For _frJ = 0 To 6
            ' y4 = y2 - (y2-y1)*ratio  (y1=100%=haut, y2=0%=bas)
            Dim _frY4 As Single = frRY2 - (frRY2 - frRY1) * CSng(frLevels(_frJ))
            Dim _frCol As ULong = (CLng(frRAlpha) Shl 24) Or (frCols(_frJ) And &HFFFFFF)
            Dim _frPen As GpPen Ptr
            Dim _frPenW As Single : If _frJ = 0 Or _frJ = 6 Then _frPenW = 1.5 Else _frPenW = 1.2
            GdipCreatePen1(_frCol, _frPenW, UnitPixel, @_frPen)
            GdipDrawLine(g, _frPen, _frXleft, _frY4, _frXright, _frY4)
            GdipDeletePen(_frPen)
            ' Label à gauche
            SetTextColor(hDC, frCols(_frJ) And &HFFFFFF)
            TextOutA(hDC, CInt(_frXleft) - 38, CInt(_frY4) - 7, StrPtr(frLabels(_frJ)), Len(frLabels(_frJ)))
        Next _frJ
        SetTextColor(hDC, 0)

        ' Zone colorée entre les niveaux (très transparent)
        Dim _frJZ As Integer
        For _frJZ = 0 To 5
            Dim _frYtop As Single = frRY2 - (frRY2 - frRY1) * CSng(frLevels(_frJZ+1))
            Dim _frYbot As Single = frRY2 - (frRY2 - frRY1) * CSng(frLevels(_frJZ))
            If _frYtop > _frYbot Then Swap _frYtop, _frYbot
            Dim _frH As Single = _frYbot - _frYtop
            If _frH > 0.5 Then
                Dim _frBr As GpBrush Ptr
                GdipCreateSolidFill((CLng(frRAlpha \ 10) Shl 24) Or (frCols(_frJZ) And &HFFFFFF), @_frBr)
                GdipFillRectangle(g, _frBr, _frXleft, _frYtop, _frXright - _frXleft, _frH)
                GdipDeleteBrush(_frBr)
            End If
        Next _frJZ

        ' Point pivot sur aperçu
        If frRAlpha < 255 Then
            Dim _frPPiv As GpPen Ptr : GdipCreatePen1(&HFF0088FF, 1.5, UnitPixel, @_frPPiv)
            GdipDrawEllipse(g, _frPPiv, frRX1 - 4, frRY1 - 4, 8, 8)
            GdipDeletePen(_frPPiv)
        End If
    Next frPass

    ' ── Gann Grid ─────────────────────────────────────────────────────────
    ' Algorithme fidèle à drawgrid() :
    '   Vecteur de base : P1→P2 = (dx, dy), longueur c, angle ang_a
    '   Si dy > 0 (P2 sous P1) : ang_a = -ang_a
    '   Rotation +90° : COS(-ang_a)*c, -SIN(-ang_a)*c
    '   Rotation -90° : COS(+ang_a)*c, -SIN(+ang_a)*c
    '   Construction de la 1ère cellule puis propagation en boucle (20 itérations)
    '   dans 2 directions (depuis P2 et depuis le coin opposé)

    Dim As Single ggRX1, ggRY1, ggRX2, ggRY2
    Dim ggRAlpha As Integer
    Dim ggPass   As Integer
    Const GGRID_ITER = 12   ' nombre d'itérations (réduit de 20 pour perf)
    Const GGRID_PI   = 3.14159265358979

    For ggPass = 0 To (UBound(pCD->GannGrids) + 1) + 1
        If ggPass <= UBound(pCD->GannGrids) Then
            ggRX1    = pCD->oriX + (pCD->GannGrids(ggPass).bar1 - pCD->Chart.ViewStart) * pCD->stepX + pCD->stepX * 0.5
            ggRY1    = ValueToScreenY(pCD->GannGrids(ggPass).price1, 0)
            ggRX2    = pCD->oriX + (pCD->GannGrids(ggPass).bar2 - pCD->Chart.ViewStart) * pCD->stepX + pCD->stepX * 0.5
            ggRY2    = ValueToScreenY(pCD->GannGrids(ggPass).price2, 0)
            ggRAlpha = 255
        ElseIf pCD->currentTool = ID_TOOL_GANNGRID And pCD->gannGridClickNb = 1 Then
            Dim mPGG As POINT : GetCursorPos(@mPGG) : ScreenToClient(hWnd, @mPGG)
            ggRX1    = pCD->oriX + (pCD->gannGridBar1 - pCD->Chart.ViewStart) * pCD->stepX + pCD->stepX * 0.5
            ggRY1    = ValueToScreenY(pCD->gannGridPrice1, 0)
            ggRX2    = CSng(mPGG.x)
            ggRY2    = CSng(mPGG.y)
            ggRAlpha = 170
        Else
            Exit For
        End If

        ' Vecteur de base P1→P2
        Dim _gga As Double = ggRX2 - ggRX1
        Dim _ggb As Double = ggRY2 - ggRY1
        Dim _ggc As Double = Sqr(_gga*_gga + _ggb*_ggb)
        If _ggc < 1.0 Then Continue For

        ' Angle de base (en radians)
        Dim _ggAng As Double = Acos(_gga / _ggc)
        If ggRY2 > ggRY1 Then _ggAng = -_ggAng   ' si P2 sous P1

        Dim _ggPen As GpPen Ptr
        Dim _ggCol As ULong = (CLng(ggRAlpha) Shl 24) Or &H888888

        ' Helper interne : dessine un segment
        #Define GGLine(ax,ay,bx,by) GdipCreatePen1(_ggCol, 1.0, UnitPixel, @_ggPen) : GdipDrawLine(g, _ggPen, CSng(ax), CSng(ay), CSng(bx), CSng(by)) : GdipDeletePen(_ggPen)

        ' Cellule initiale (reproduction exacte du code original)
        Dim _ggX2 As Double = ggRX1, _ggY2 As Double = ggRY1
        Dim _ggX3 As Double = ggRX2, _ggY3 As Double = ggRY2
        Dim _ggX4 As Double, _ggY4 As Double
        Dim _ggX5 As Double, _ggY5 As Double
        Dim _ggX6 As Double, _ggY6 As Double
        Dim _ggX7 As Double, _ggY7 As Double

        GGLine(_ggX2, _ggY2, _ggX3, _ggY3)

        _ggX4 = Cos(-_ggAng) * _ggc + _ggX3
        _ggY4 = _ggY3 - Sin(-_ggAng) * _ggc
        GGLine(_ggX3, _ggY3, _ggX4, _ggY4)

        _ggX4 = Cos(-_ggAng) * _ggc + _ggX2
        _ggY4 = _ggY2 - Sin(-_ggAng) * _ggc
        GGLine(_ggX2, _ggY2, _ggX4, _ggY4)

        _ggX2 = Cos(_ggAng) * _ggc + _ggX4
        _ggY2 = _ggY4 - Sin(_ggAng) * _ggc
        GGLine(_ggX2, _ggY2, _ggX4, _ggY4)

        _ggX7 = _ggX4 : _ggY7 = _ggY4

        ' Boucle depuis P2 (x6,y6 = P2)
        _ggX6 = _ggX3 : _ggY6 = _ggY3
        Dim _ggI As Integer
        For _ggI = 1 To GGRID_ITER
            _ggX4 = Cos(_ggAng) * _ggc + _ggX6
            _ggY4 = _ggY6 - Sin(_ggAng) * _ggc
            GGLine(_ggX6, _ggY6, _ggX4, _ggY4)
            _ggX5 = _ggX4 : _ggY5 = _ggY4
            _ggX5 = Cos(-_ggAng) * _ggc + _ggX5
            _ggY5 = _ggY5 - Sin(-_ggAng) * _ggc
            GGLine(_ggX4, _ggY4, _ggX5, _ggY5)
            ' symétrie
            _ggX4 = Cos(-_ggAng) * _ggc + _ggX6
            _ggY4 = _ggY6 - Sin(-_ggAng) * _ggc
            GGLine(_ggX6, _ggY6, _ggX4, _ggY4)
            _ggX5 = _ggX4 : _ggY5 = _ggY4
            _ggX5 = Cos(_ggAng) * _ggc + _ggX5
            _ggY5 = _ggY5 - Sin(_ggAng) * _ggc
            GGLine(_ggX4, _ggY4, _ggX5, _ggY5)
            _ggX6 = _ggX5 : _ggY6 = _ggY5
        Next _ggI

        ' Boucle depuis le coin opposé (x7,y7)
        _ggX6 = _ggX7 : _ggY6 = _ggY7
        For _ggI = 1 To GGRID_ITER
            _ggX4 = Cos(_ggAng) * _ggc + _ggX6
            _ggY4 = _ggY6 - Sin(_ggAng) * _ggc
            GGLine(_ggX6, _ggY6, _ggX4, _ggY4)
            _ggX5 = _ggX4 : _ggY5 = _ggY4
            _ggX5 = Cos(-_ggAng) * _ggc + _ggX5
            _ggY5 = _ggY5 - Sin(-_ggAng) * _ggc
            GGLine(_ggX4, _ggY4, _ggX5, _ggY5)
            ' symétrie
            _ggX4 = Cos(-_ggAng) * _ggc + _ggX6
            _ggY4 = _ggY6 - Sin(-_ggAng) * _ggc
            GGLine(_ggX6, _ggY6, _ggX4, _ggY4)
            _ggX5 = _ggX4 : _ggY5 = _ggY4
            _ggX5 = Cos(_ggAng) * _ggc + _ggX5
            _ggY5 = _ggY5 - Sin(_ggAng) * _ggc
            GGLine(_ggX4, _ggY4, _ggX5, _ggY5)
            _ggX6 = _ggX5 : _ggY6 = _ggY5
        Next _ggI

        ' Point pivot sur aperçu
        If ggRAlpha < 255 Then
            Dim _ggPPiv As GpPen Ptr : GdipCreatePen1(&HFF0088FF, 1.5, UnitPixel, @_ggPPiv)
            GdipDrawEllipse(g, _ggPPiv, ggRX1 - 4, ggRY1 - 4, 8, 8)
            GdipDeletePen(_ggPPiv)
        End If
    Next ggPass

    ' ── Pentagramme ───────────────────────────────────────────────────────
    ' Centre = P1 (pixels), rayon c = distance P1→P2
    ' 5 sommets à ang_a + k*72° (k=0..4), P2 étant le sommet 0
    ' Étoile : relier les sommets dans l'ordre 0→2→4→1→3→0
    ' Cercle : dessiné avec GdipDrawEllipse
    Const PENTA_PI  = 3.14159265358979
    Const PENTA_RAD = PENTA_PI / 180.0

    Dim As Single ptRX1, ptRY1, ptRX2, ptRY2
    Dim ptRAlpha As Integer
    Dim ptPass   As Integer

    For ptPass = 0 To (UBound(pCD->Pentagrams) + 1) + 1
        If ptPass <= UBound(pCD->Pentagrams) Then
            ptRX1    = pCD->oriX + (pCD->Pentagrams(ptPass).bar1 - pCD->Chart.ViewStart) * pCD->stepX + pCD->stepX * 0.5
            ptRY1    = ValueToScreenY(pCD->Pentagrams(ptPass).price1, 0)
            ptRX2    = pCD->oriX + (pCD->Pentagrams(ptPass).bar2 - pCD->Chart.ViewStart) * pCD->stepX + pCD->stepX * 0.5
            ptRY2    = ValueToScreenY(pCD->Pentagrams(ptPass).price2, 0)
            ptRAlpha = 255
        ElseIf pCD->currentTool = ID_TOOL_PENTAGRAM And pCD->pentaClickNb = 1 Then
            Dim mPPT As POINT : GetCursorPos(@mPPT) : ScreenToClient(hWnd, @mPPT)
            ptRX1    = pCD->oriX + (pCD->pentaBar1 - pCD->Chart.ViewStart) * pCD->stepX + pCD->stepX * 0.5
            ptRY1    = ValueToScreenY(pCD->pentaPrice1, 0)
            ptRX2    = CSng(mPPT.x)
            ptRY2    = CSng(mPPT.y)
            ptRAlpha = 170
        Else
            Exit For
        End If

        Dim _pta As Double = ptRX2 - ptRX1
        Dim _ptb As Double = ptRY2 - ptRY1
        Dim _ptc As Double = Sqr(_pta*_pta + _ptb*_ptb)
        If _ptc < 1.0 Then Continue For

        ' Angle du rayon P1→P2
        Dim _ptAng As Double = Acos(_pta / _ptc) * 180.0 / PENTA_PI
        If ptRY2 > ptRY1 Then _ptAng = -_ptAng   ' si P2 sous P1

        Dim _ptCol As ULong = (CLng(ptRAlpha) Shl 24) Or &H888888
        Dim _ptColStar As ULong = (CLng(ptRAlpha) Shl 24) Or &HFFCC44  ' étoile dorée

        ' Cercle
        Dim _ptPenC As GpPen Ptr
        GdipCreatePen1(_ptCol, 1.0, UnitPixel, @_ptPenC)
        GdipDrawEllipse(g, _ptPenC, ptRX1 - CSng(_ptc), ptRY1 - CSng(_ptc), CSng(_ptc)*2, CSng(_ptc)*2)
        GdipDeletePen(_ptPenC)

        ' Calcul des 5 sommets
        Dim _ptSX(4) As Single, _ptSY(4) As Single
        Dim _ptK As Integer
        For _ptK = 0 To 4
            Dim _ptDeg As Double = (_ptAng + _ptK * 72.0) * PENTA_RAD
            _ptSX(_ptK) = ptRX1 + CSng(Cos(_ptDeg) * _ptc)
            _ptSY(_ptK) = ptRY1 - CSng(Sin(_ptDeg) * _ptc)
        Next _ptK

        ' Étoile : sommets dans l'ordre 0→2→4→1→3→0
        Dim _ptOrder(4) As Integer
        _ptOrder(0)=0 : _ptOrder(1)=2 : _ptOrder(2)=4 : _ptOrder(3)=1 : _ptOrder(4)=3
        Dim _ptPenS As GpPen Ptr
        GdipCreatePen1(_ptColStar, 1.5, UnitPixel, @_ptPenS)
        For _ptK = 0 To 4
            Dim _ptA As Integer = _ptOrder(_ptK)
            Dim _ptB As Integer = _ptOrder((_ptK+1) Mod 5)
            GdipDrawLine(g, _ptPenS, _ptSX(_ptA), _ptSY(_ptA), _ptSX(_ptB), _ptSY(_ptB))
        Next _ptK
        GdipDeletePen(_ptPenS)

        ' Petits cercles aux 5 sommets
        Dim _ptPenDot As GpPen Ptr
        GdipCreatePen1(_ptColStar, 1.2, UnitPixel, @_ptPenDot)
        For _ptK = 0 To 4
            GdipDrawEllipse(g, _ptPenDot, _ptSX(_ptK)-3, _ptSY(_ptK)-3, 6, 6)
        Next _ptK
        GdipDeletePen(_ptPenDot)

        ' Point centre sur aperçu
        If ptRAlpha < 255 Then
            Dim _ptPPiv As GpPen Ptr : GdipCreatePen1(&HFF0088FF, 1.5, UnitPixel, @_ptPPiv)
            GdipDrawEllipse(g, _ptPPiv, ptRX1 - 4, ptRY1 - 4, 8, 8)
            GdipDeletePen(_ptPPiv)
        End If
    Next ptPass

    ' ── Parallel Lines ────────────────────────────────────────────────────
    ' Ligne de base : P1→P2, prolongée jusqu'aux bords
    ' Parallèle     : P3 → P3+(P2-P1), prolongée jusqu'aux bords
    ' Les deux lignes sont prolongées infiniment (style canal de tendance)

    ' Helper : prolonger une ligne définie par (lx1,ly1)→(lx1+ldx,ly1+ldy) jusqu'aux bords
    ' Retourne les points d'intersection avec les bords du graphe

    Dim plChartRight As Single = pCD->oriX + (winW - 120 - toolbarW)
    Dim plChartLeft  As Single = pCD->oriX

    Dim As Single plRX1, plRY1, plRX2, plRY2, plRX3, plRY3
    Dim plRAlpha As Integer
    Dim plPass   As Integer

    For plPass = 0 To (UBound(pCD->ParaLinesArr) + 1) + 2
        If plPass <= UBound(pCD->ParaLinesArr) Then
            plRX1    = pCD->oriX + (pCD->ParaLinesArr(plPass).bar1 - pCD->Chart.ViewStart) * pCD->stepX + pCD->stepX * 0.5
            plRY1    = ValueToScreenY(pCD->ParaLinesArr(plPass).price1, 0)
            plRX2    = pCD->oriX + (pCD->ParaLinesArr(plPass).bar2 - pCD->Chart.ViewStart) * pCD->stepX + pCD->stepX * 0.5
            plRY2    = ValueToScreenY(pCD->ParaLinesArr(plPass).price2, 0)
            plRX3    = pCD->oriX + (pCD->ParaLinesArr(plPass).bar3 - pCD->Chart.ViewStart) * pCD->stepX + pCD->stepX * 0.5
            plRY3    = ValueToScreenY(pCD->ParaLinesArr(plPass).price3, 0)
            plRAlpha = 255
        ElseIf pCD->currentTool = ID_TOOL_PARALINES And pCD->paraClickNb >= 1 Then
            Dim mPPL As POINT : GetCursorPos(@mPPL) : ScreenToClient(hWnd, @mPPL)
            plRX1    = pCD->oriX + (pCD->paraBar1 - pCD->Chart.ViewStart) * pCD->stepX + pCD->stepX * 0.5
            plRY1    = ValueToScreenY(pCD->paraPrice1, 0)
            If pCD->paraClickNb >= 2 Then
                plRX2 = pCD->oriX + (pCD->paraBar2 - pCD->Chart.ViewStart) * pCD->stepX + pCD->stepX * 0.5
                plRY2 = ValueToScreenY(pCD->paraPrice2, 0)
            Else
                plRX2 = mPPL.x : plRY2 = mPPL.y
            End If
            plRX3    = CSng(mPPL.x)
            plRY3    = CSng(mPPL.y)
            plRAlpha = 170
        Else
            Exit For
        End If

        Dim _pldx As Single = plRX2 - plRX1
        Dim _pldy As Single = plRY2 - plRY1

        Dim _plCol As ULong = (CLng(plRAlpha) Shl 24) Or &H444444

        ' Fonction interne : calcule les extrémités prolongées d'une ligne
        Dim _plAX As Single, _plAY As Single, _plBX As Single, _plBY As Single

        ' Prolonger la ligne de base (P1→P2 direction)
        If Abs(_pldx) > 0.001 Then
            Dim _plT1 As Single = (plChartLeft  - plRX1) / _pldx
            Dim _plT2 As Single = (plChartRight - plRX1) / _pldx
            If _plT1 > _plT2 Then Swap _plT1, _plT2
            _plAX = plRX1 + _pldx * _plT1 : _plAY = plRY1 + _pldy * _plT1
            _plBX = plRX1 + _pldx * _plT2 : _plBY = plRY1 + _pldy * _plT2
        Else
            _plAX = plRX1 : _plAY = 0
            _plBX = plRX1 : _plBY = 10000
        End If

        ' Ligne de base
        Dim _plPen As GpPen Ptr
        GdipCreatePen1(_plCol, 1.5, UnitPixel, @_plPen)
        GdipDrawLine(g, _plPen, _plAX, _plAY, _plBX, _plBY)
        GdipDeletePen(_plPen)

        ' Parallèle (P3 + même vecteur) — seulement si on a P3
        If plRAlpha = 255 Or paraClickNb = 2 Or (paraClickNb >= 1 And plRAlpha < 255) Then
            If Abs(_pldx) > 0.001 Then
                Dim _plT3 As Single = (plChartLeft  - plRX3) / _pldx
                Dim _plT4 As Single = (plChartRight - plRX3) / _pldx
                If _plT3 > _plT4 Then Swap _plT3, _plT4
                Dim _plCX As Single = plRX3 + _pldx * _plT3 : Dim _plCY As Single = plRY3 + _pldy * _plT3
                Dim _plDX2 As Single = plRX3 + _pldx * _plT4 : Dim _plDY2 As Single = plRY3 + _pldy * _plT4
                GdipCreatePen1(_plCol, 1.5, UnitPixel, @_plPen)
                GdipDrawLine(g, _plPen, _plCX, _plCY, _plDX2, _plDY2)
                GdipDeletePen(_plPen)
                ' Zone entre les deux lignes (très légère)
                If plRAlpha = 255 Then
                    Dim _plBrP As GpBrush Ptr
                    GdipCreateSolidFill(&H08888888, @_plBrP)
                    ' GdipFillPolygon attend un tableau de PointF = paires de Singles
                    Dim _plPts(7) As Single   ' 4 points × 2 coordonnées (x,y)
                    _plPts(0) = _plAX  : _plPts(1) = _plAY
                    _plPts(2) = _plBX  : _plPts(3) = _plBY
                    _plPts(4) = _plDX2 : _plPts(5) = _plDY2
                    _plPts(6) = _plCX  : _plPts(7) = _plCY
                    GdipFillPolygon(g, _plBrP, Cast(Any Ptr, @_plPts(0)), 4, FillModeAlternate)
                    GdipDeleteBrush(_plBrP)
                End If
            End If
        End If

        ' Points cliqués en aperçu
        If plRAlpha < 255 Then
            Dim _plPDot As GpPen Ptr : GdipCreatePen1(&HFF0088FF, 1.5, UnitPixel, @_plPDot)
            GdipDrawEllipse(g, _plPDot, plRX1 - 4, plRY1 - 4, 8, 8)
            If paraClickNb >= 2 Then
                GdipDrawEllipse(g, _plPDot, plRX2 - 4, plRY2 - 4, 8, 8)
            End If
            GdipDeletePen(_plPDot)
        End If
    Next plPass

    If pCD->currentTool = ID_TOOL_CROSSHAIR And pCD->crosshairX >= 0 And pCD->Chart.IsLoaded Then
        Dim cx As Single = pCD->crosshairX
        Dim cy As Single = pCD->crosshairY

        Dim chartLeft  As Single = pCD->oriX
        Dim chartRight As Single = pCD->oriX + lenX
        Dim chartTop   As Single = ZOOM_BAR_H + 40
        Dim chartBot   As Single = pCD->oriY

        ' Barre pointée par X (commune à tous les canvas)
        Dim barUnder As Integer = pCD->Chart.ViewStart + CInt((cx - pCD->oriX) / pCD->stepX)
        If barUnder < pCD->Chart.ViewStart Then barUnder = pCD->Chart.ViewStart
        If barUnder > lastIdx Then barUnder = lastIdx

        If cx >= chartLeft And cx <= chartRight Then

            Dim pCross As GpPen Ptr
            GdipCreatePen1(&HFF555555, 1.0, UnitPixel, @pCross)
            GdipSetPenDashStyle(pCross, 2)

            SetBkMode(hDC, TRANSPARENT)

            ' ── Graphe principal ─────────────────────────────────────────────
            If cy >= chartTop And cy <= chartBot Then
                GdipDrawLine(g, pCross, chartLeft, cy, chartRight, cy)

                Dim crossPrice As Double = pCD->vMin + (pCD->oriY - cy) / pCD->scaleY
                Dim priceStr As String
                Dim priceRange As Double = pCD->vMax - pCD->vMin
                If priceRange >= 100 Then
                    priceStr = Str(CLng(crossPrice))
                ElseIf priceRange >= 1 Then
                    priceStr = Format(crossPrice, "0.00")
                Else
                    priceStr = Format(crossPrice, "0.0000")
                End If
                Dim priceLblW As Integer = Len(priceStr) * 7 + 8
                Dim priceLblH As Integer = 18
                Dim priceLblX As Single = chartRight + 2
                Dim priceLblY As Single = cy - priceLblH / 2
                Dim brPL As GpBrush Ptr : GdipCreateSolidFill(&HFF333333, @brPL)
                GdipFillRectangle(g, brPL, priceLblX, priceLblY, priceLblW, priceLblH)
                GdipDeleteBrush(brPL)
                SetTextColor(hDC, &HFFFFFF)
                TextOut(hDC, CInt(priceLblX) + 4, CInt(priceLblY) + 2, priceStr, Len(priceStr))
            End If

            GdipDrawLine(g, pCross, cx, chartTop, cx, chartBot)

            ' ── Panels séparés ───────────────────────────────────────────────
            For pi As Integer = 0 To pCD->PanelGeomCount - 1
                Dim pTop    As Single = pCD->PanelGeoms(pi).rTop
                Dim pBot    As Single = pCD->PanelGeoms(pi).rBottom
                Dim pInnerH2 As Integer = pCD->PanelGeoms(pi).innerH
                Dim pVMin2  As Double  = pCD->PanelGeoms(pi).vMin
                Dim pVMax2  As Double  = pCD->PanelGeoms(pi).vMax

                GdipDrawLine(g, pCross, cx, pTop, cx, pBot)

                Dim panelCy As Single
                If cy >= pTop And cy <= pBot Then
                    panelCy = cy
                Else
                    Continue For
                End If

                GdipDrawLine(g, pCross, chartLeft, panelCy, chartRight, panelCy)

                Dim panelVal As Double = 0
                If pInnerH2 > 0 And pVMax2 <> pVMin2 Then
                    panelVal = pVMin2 + (pBot - panelCy) * (pVMax2 - pVMin2) / pInnerH2
                End If

                Dim valStr As String
                Dim valRange As Double = pVMax2 - pVMin2
                If valRange >= 100 Then
                    valStr = Format(panelVal, "0.0")
                ElseIf valRange >= 1 Then
                    valStr = Format(panelVal, "0.00")
                Else
                    valStr = Format(panelVal, "0.0000")
                End If

                Dim vLblW As Integer = Len(valStr) * 7 + 8
                Dim vLblH As Integer = 18
                Dim vLblX As Single = chartRight + 2
                Dim vLblY As Single = panelCy - vLblH / 2
                Dim brVL As GpBrush Ptr : GdipCreateSolidFill(&HFF333333, @brVL)
                GdipFillRectangle(g, brVL, vLblX, vLblY, vLblW, vLblH)
                GdipDeleteBrush(brVL)
                SetTextColor(hDC, &HFFFFFF)
                TextOut(hDC, CInt(vLblX) + 4, CInt(vLblY) + 2, valStr, Len(valStr))
            Next

            GdipDeletePen(pCross)

            Dim dtLbl As String = ""
            If barUnder >= 0 And barUnder <= UBound(pCD->Chart.History) Then
                Dim dtS As String = Trim(pCD->Chart.History(barUnder).Dt)
                Dim tmS As String = Trim(pCD->Chart.History(barUnder).Tm)
                If Len(tmS) >= 4 And tmS <> "00:00" Then
                    dtLbl = dtS & " " & tmS
                Else
                    dtLbl = dtS
                End If
            End If

            If Len(dtLbl) > 0 Then
                Dim dtBaseY As Single = chartBot
                If pCD->PanelGeomCount > 0 Then
                    dtBaseY = pCD->PanelGeoms(pCD->PanelGeomCount - 1).rBottom
                End If

                Dim dtLblW As Integer = Len(dtLbl) * 7 + 8
                Dim dtLblH As Integer = 18
                Dim dtLblX As Single = cx - dtLblW / 2
                Dim dtLblY As Single = dtBaseY + 4

                If dtLblX < chartLeft Then dtLblX = chartLeft
                If dtLblX + dtLblW > chartRight Then dtLblX = chartRight - dtLblW

                Dim brDL As GpBrush Ptr : GdipCreateSolidFill(&HFF333333, @brDL)
                GdipFillRectangle(g, brDL, dtLblX, dtLblY, dtLblW, dtLblH)
                GdipDeleteBrush(brDL)
                SetTextColor(hDC, &HFFFFFF)
                TextOut(hDC, CInt(dtLblX) + 4, CInt(dtLblY) + 2, dtLbl, Len(dtLbl))
            End If

            SetTextColor(hDC, 0)
        End If
    End If

    GdipDeleteGraphics(g)
End Sub

' ── Dialogue "Paramètres" — modification de période d'un overlay ──────────────
' ════════════════════════════════════════════════════════════════════
' REMPLACEMENT DE ParamsDlgProc dans QChartist2.bas
'
' Chercher et remplacer toute la fonction ParamsDlgProc
' (de "Function ParamsDlgProc" jusqu'au "End Function" correspondant)
' par ce code.
'
' Changements :
'   - Ajout d'un label + editbox pour param2 (caché si param2Label="")
'   - La fenêtre s'agrandit automatiquement si param2 est visible
'   - OK / Entrée sauvegarde les deux valeurs
'   - Propagation de param2 au graphe actif comme pour period
' ════════════════════════════════════════════════════════════════════

Function ParamsDlgProc(hWnd As HWND, uMsg As UINT, wParam As WPARAM, lParam As LPARAM) As LRESULT
    Static hLbl   As HWND   ' label "Nouvelle periode :"
    Static hEdit  As HWND   ' editbox periode
    Static hLbl2  As HWND   ' label param2
    Static hEdit2 As HWND   ' editbox param2
    Static hOK    As HWND   ' bouton OK

    Select Case uMsg

        Case WM_CREATE
            ' ── Champ periode ────────────────────────────────────────
            hLbl = CreateWindowEx(0, "STATIC", "Nouvelle periode :", _
                WS_CHILD Or WS_VISIBLE, _
                10, 14, 120, 20, hWnd, NULL, GetModuleHandle(NULL), NULL)
            hEdit = CreateWindowEx(WS_EX_CLIENTEDGE, "EDIT", "", _
                WS_CHILD Or WS_VISIBLE Or ES_NUMBER, _
                135, 12, 60, 22, hWnd, Cast(HMENU, ID_EDT_PERIOD), _
                GetModuleHandle(NULL), NULL)
            SendMessage(hEdit, EM_SETLIMITTEXT, 4, 0)

            ' ── Champ param2 (créé mais caché par défaut) ────────────
            hLbl2 = CreateWindowEx(0, "STATIC", "", _
                WS_CHILD, _
                10, 44, 120, 20, hWnd, Cast(HMENU, ID_LBL_PERIOD2), _
                GetModuleHandle(NULL), NULL)
            hEdit2 = CreateWindowEx(WS_EX_CLIENTEDGE, "EDIT", "", _
                WS_CHILD Or ES_NUMBER, _
                135, 42, 60, 22, hWnd, Cast(HMENU, ID_EDT_PERIOD2), _
                GetModuleHandle(NULL), NULL)
            SendMessage(hEdit2, EM_SETLIMITTEXT, 5, 0)

            ' ── Bouton OK (position ajustée dynamiquement après) ─────
            hOK = CreateWindowEx(0, "BUTTON", "OK", _
                WS_CHILD Or WS_VISIBLE Or BS_DEFPUSHBUTTON, _
                75, 46, 70, 26, hWnd, Cast(HMENU, IDOK), _
                GetModuleHandle(NULL), NULL)

            ' ── Remplissage des valeurs courantes ────────────────────
            If rightClickedOverlayIdx >= 0 And rightClickedOverlayIdx < ActiveCount Then
                Dim ap As ActivePanel = ActivePanels(rightClickedOverlayIdx)
                Dim def As IndicatorDef = indRegistry.defs(ap.defIndex)

                ' Periode
                Dim curPer As ZString * 8 : curPer = Str(ap.period)
                SetWindowText(hEdit, @curPer)
                SendMessage(hEdit, EM_SETSEL, 0, -1)

                ' param2 : afficher seulement si param2Label non vide
                Dim p2lbl As String = Trim(def.param2Label)
                If Len(p2lbl) > 0 Then
                    ' Mettre à jour le label avec le nom du paramètre
                    Dim zp2lbl As ZString * 32 : zp2lbl = p2lbl & " :"
                    SetWindowText(hLbl2, @zp2lbl)
                    Dim curP2 As ZString * 8 : curP2 = Str(ap.param2)
                    SetWindowText(hEdit2, @curP2)

                    ' Rendre visibles
                    ShowWindow(hLbl2,  SW_SHOW)
                    ShowWindow(hEdit2, SW_SHOW)

                    ' Déplacer le bouton OK plus bas et agrandir la fenêtre
                    SetWindowPos(hOK, NULL, 75, 76, 70, 26, SWP_NOZORDER)
                    SetWindowPos(hWnd, NULL, 0, 0, 215, 140, SWP_NOMOVE Or SWP_NOZORDER)
                Else
                    ' Garder cachés, bouton OK à sa position normale
                    ShowWindow(hLbl2,  SW_HIDE)
                    ShowWindow(hEdit2, SW_HIDE)
                    SetWindowPos(hOK, NULL, 75, 46, 70, 26, SWP_NOZORDER)
                    SetWindowPos(hWnd, NULL, 0, 0, 215, 110, SWP_NOMOVE Or SWP_NOZORDER)
                End If
            End If

            SetFocus(hEdit)

        Case WM_COMMAND
            Dim cmdId  As Integer = Loword(wParam)
            Dim cmdEvt As Integer = Hiword(wParam)

            ' OK cliqué ou Entrée dans l'un des editbox
            Dim isConfirm As Integer = 0
            If cmdId = IDOK Then isConfirm = 1
            If cmdId = ID_EDT_PERIOD  And cmdEvt = 1 Then isConfirm = 1  ' EN_DEFAULT
            If cmdId = ID_EDT_PERIOD2 And cmdEvt = 1 Then isConfirm = 1

            If isConfirm Then
                ' Lire periode
                Dim eBuf As ZString * 8
                GetWindowText(hEdit, @eBuf, 8)
                Dim newPer As Long = Val(eBuf)
                If newPer < 2   Then newPer = 2
                If newPer > 9999 Then newPer = 9999

                ' Lire param2 (0 si champ caché)
                Dim newP2 As Long = 0
                If IsWindowVisible(hEdit2) Then
                    Dim eBuf2 As ZString * 8
                    GetWindowText(hEdit2, @eBuf2, 8)
                    newP2 = Val(eBuf2)
                    If newP2 < 0    Then newP2 = 0
                    If newP2 > 9999 Then newP2 = 9999
                End If

                If rightClickedOverlayIdx >= 0 And rightClickedOverlayIdx < ActiveCount Then
                    ' Mise à jour globale
                    ActivePanels(rightClickedOverlayIdx).period = newPer
                    ActivePanels(rightClickedOverlayIdx).param2 = newP2

                    ' Propagation au graphe actif
                    Dim pCDP As ChartWinData Ptr = GetChartData(hCharts(activeChartIdx))
                    If pCDP <> NULL And rightClickedOverlayIdx < pCDP->ActiveCount Then
                        pCDP->ActivePanels(rightClickedOverlayIdx).period = newPer
                        pCDP->ActivePanels(rightClickedOverlayIdx).param2 = newP2
                    End If

                    ForceRedraw(GetWindow(hWnd, GW_OWNER))
                End If
                DestroyWindow(hWnd)
            End If

        Case WM_CLOSE
            DestroyWindow(hWnd)

    End Select
    Return DefWindowProc(hWnd, uMsg, wParam, lParam)
End Function

Function IndicatorsDlgProc(hWnd As HWND, uMsg As UINT, wParam As WPARAM, lParam As LPARAM) As LRESULT

    Select Case uMsg
        Case WM_CREATE
            ' lpCreateParams contient l'index du graphe cible (passé via CreateWindowEx)
            Dim pCS As CREATESTRUCT Ptr = Cast(CREATESTRUCT Ptr, lParam)
            Dim targetIdx As Long = CLng(CInt(pCS->lpCreateParams))
            SetWindowLongPtr(hWnd, GWLP_USERDATA, targetIdx)
            ' Titre indiquant le graphe cible
            Dim winTitle As String = "Technicals - Graphe " & (targetIdx + 1)
            Dim zWinTitle As ZString * 40 : zWinTitle = winTitle
            SetWindowText(hWnd, @zWinTitle)

            Dim hList As HWND = CreateWindowEx(WS_EX_CLIENTEDGE, "LISTBOX", "", _
                WS_CHILD Or WS_VISIBLE Or WS_VSCROLL Or LBS_NOTIFY, _
                10, 10, 200, 100, hWnd, Cast(HMENU, ID_LST_INDICATORS), _
                GetModuleHandle(NULL), NULL)
            For i As Integer = 0 To indRegistry.count - 1
                Dim nm As String = indRegistry.defs(i).name
                SendMessage(hList, LB_ADDSTRING, 0, Cast(LPARAM, StrPtr(nm)))
            Next
            CreateWindowEx(0, "STATIC", "-- Parametres --", _
                WS_CHILD Or WS_VISIBLE Or SS_CENTER, 10, 120, 200, 16, hWnd, _
                Cast(HMENU, ID_LBL_PARAMS), GetModuleHandle(NULL), NULL)
            CreateWindowEx(0, "STATIC", "Periode :", _
                WS_CHILD Or WS_VISIBLE, 10, 144, 80, 20, hWnd, _
                Cast(HMENU, ID_LBL_PERIOD), GetModuleHandle(NULL), NULL)
            CreateWindowEx(WS_EX_CLIENTEDGE, "EDIT", "20", _
                WS_CHILD Or WS_VISIBLE Or ES_NUMBER, 95, 142, 60, 22, hWnd, _
                Cast(HMENU, ID_EDT_PERIOD), GetModuleHandle(NULL), NULL)
            SendMessage(GetDlgItem(hWnd, ID_EDT_PERIOD), EM_SETLIMITTEXT, 4, 0)
            CreateWindowEx(0, "STATIC", "", WS_CHILD, _
                10, 172, 80, 20, hWnd, Cast(HMENU, ID_LBL_PERIOD2), GetModuleHandle(NULL), NULL)
            CreateWindowEx(WS_EX_CLIENTEDGE, "EDIT", "", WS_CHILD Or ES_NUMBER, _
                95, 170, 60, 22, hWnd, Cast(HMENU, ID_EDT_PERIOD2), GetModuleHandle(NULL), NULL)
            CreateWindowEx(0, "BUTTON", "Appliquer", _
                WS_CHILD Or WS_VISIBLE, 45, 202, 130, 30, hWnd, _
                Cast(HMENU, ID_BTN_APPLY), GetModuleHandle(NULL), NULL)
            SendMessage(GetDlgItem(hWnd, ID_LST_INDICATORS), LB_SETCURSEL, 0, 0)
            If indRegistry.count > 0 Then
                Dim defPer As Long = indRegistry.defs(0).defaultPeriod
                Dim buf0 As ZString * 8 : buf0 = Str(defPer)
                SetWindowText(GetDlgItem(hWnd, ID_EDT_PERIOD), @buf0)
                Dim lbl0 As String = "Periode " & indRegistry.defs(0).labelPrefix & " :"
                Dim zlbl0 As ZString * 32 : zlbl0 = lbl0
                SetWindowText(GetDlgItem(hWnd, ID_LBL_PERIOD), @zlbl0)
                Dim p2lbl0 As String = Trim(indRegistry.defs(0).param2Label)
                If Len(p2lbl0) > 0 Then
                    Dim zp2lbl0 As ZString * 32 : zp2lbl0 = p2lbl0
                    SetWindowText(GetDlgItem(hWnd, ID_LBL_PERIOD2), @zp2lbl0)
                    Dim buf2 As ZString * 8 : buf2 = Str(indRegistry.defs(0).defaultParam2)
                    SetWindowText(GetDlgItem(hWnd, ID_EDT_PERIOD2), @buf2)
                    ShowWindow(GetDlgItem(hWnd, ID_LBL_PERIOD2), SW_SHOW)
                    ShowWindow(GetDlgItem(hWnd, ID_EDT_PERIOD2), SW_SHOW)
                Else
                    ShowWindow(GetDlgItem(hWnd, ID_LBL_PERIOD2), SW_HIDE)
                    ShowWindow(GetDlgItem(hWnd, ID_EDT_PERIOD2), SW_HIDE)
                End If
            End If

        Case WM_COMMAND
            Dim cmdId  As Integer = Loword(wParam)
            Dim cmdEvt As Integer = Hiword(wParam)

            If cmdId = ID_LST_INDICATORS And cmdEvt = LBN_SELCHANGE Then
                Dim selIdx As Integer = SendMessage(GetDlgItem(hWnd, ID_LST_INDICATORS), LB_GETCURSEL, 0, 0)
                If selIdx >= 0 And selIdx < indRegistry.count Then
                    Dim defPer As Long = indRegistry.defs(selIdx).defaultPeriod
                    Dim buf As ZString * 8 : buf = Str(defPer)
                    SetWindowText(GetDlgItem(hWnd, ID_EDT_PERIOD), @buf)
                    Dim lbl As String = "Periode " & indRegistry.defs(selIdx).labelPrefix & " :"
                    Dim zlbl As ZString * 32 : zlbl = lbl
                    SetWindowText(GetDlgItem(hWnd, ID_LBL_PERIOD), @zlbl)
                    Dim p2lbl As String = Trim(indRegistry.defs(selIdx).param2Label)
                    If Len(p2lbl) > 0 Then
                        Dim zp2lbl As ZString * 32 : zp2lbl = p2lbl
                        SetWindowText(GetDlgItem(hWnd, ID_LBL_PERIOD2), @zp2lbl)
                        Dim buf2 As ZString * 8 : buf2 = Str(indRegistry.defs(selIdx).defaultParam2)
                        SetWindowText(GetDlgItem(hWnd, ID_EDT_PERIOD2), @buf2)
                        ShowWindow(GetDlgItem(hWnd, ID_LBL_PERIOD2), SW_SHOW)
                        ShowWindow(GetDlgItem(hWnd, ID_EDT_PERIOD2), SW_SHOW)
                    Else
                        ShowWindow(GetDlgItem(hWnd, ID_LBL_PERIOD2), SW_HIDE)
                        ShowWindow(GetDlgItem(hWnd, ID_EDT_PERIOD2), SW_HIDE)
                    End If
                End If
            End If

            If cmdId = ID_BTN_APPLY Then
                Dim selIdx2 As Integer = SendMessage(GetDlgItem(hWnd, ID_LST_INDICATORS), LB_GETCURSEL, 0, 0)
                If selIdx2 = LB_ERR Or selIdx2 >= indRegistry.count Then Return 0
                Dim eBuf As ZString * 8
                GetWindowText(GetDlgItem(hWnd, ID_EDT_PERIOD), @eBuf, 8)
                Dim per As Long = Val(eBuf)
                If per < 1   Then per = 1
                If per > 999 Then per = 999
                Dim p2 As Long = 0
                Dim p2lbl2 As String = Trim(indRegistry.defs(selIdx2).param2Label)
                If Len(p2lbl2) > 0 Then
                    Dim eBuf2 As ZString * 8
                    GetWindowText(GetDlgItem(hWnd, ID_EDT_PERIOD2), @eBuf2, 8)
                    p2 = Val(eBuf2)
                End If
                ' Récupérer le graphe cible depuis GWLP_USERDATA
                Dim tgtIdx As Long = GetWindowLongPtr(hWnd, GWLP_USERDATA)
                Dim pCDA As ChartWinData Ptr = GetChartData(hCharts(tgtIdx))
                If pCDA <> NULL Then
                    pCDA->ActiveCount += 1
                    ReDim Preserve pCDA->ActivePanels(pCDA->ActiveCount - 1)
                    pCDA->ActivePanels(pCDA->ActiveCount - 1).defIndex = selIdx2
                    pCDA->ActivePanels(pCDA->ActiveCount - 1).period   = per
                    pCDA->ActivePanels(pCDA->ActiveCount - 1).param2   = p2
                End If
                ' Synchro globale ActivePanels pour compatibilité
                ActiveCount = pCDA->ActiveCount
                ReDim ActivePanels(ActiveCount - 1)
                Dim sj As Integer
                For sj = 0 To ActiveCount - 1
                    ActivePanels(sj) = pCDA->ActivePanels(sj)
                Next
                InvalidateRect(hCharts(tgtIdx), NULL, FALSE)
            End If

        Case WM_CLOSE : DestroyWindow(hWnd)
    End Select
    Return DefWindowProc(hWnd, uMsg, wParam, lParam)
End Function

' ── Helper : récupère les données d'une fenêtre graphe enfant ────────────────
Function GetChartData(hWnd As HWND) As ChartWinData Ptr
    Return Cast(ChartWinData Ptr, GetWindowLongPtr(hWnd, GWLP_USERDATA))
End Function

' ── Dispose les fenêtres enfant selon le nombre de graphes ───────────────────
Sub ArrangeChartWindows(hParent As HWND)
    Dim rc As RECT
    GetClientRect(hParent, @rc)
    Dim cLeft  As Long = toolbarW
    Dim cTop   As Long = ZOOM_BAR_H
    Dim cW     As Long = rc.right  - toolbarW
    Dim cH     As Long = rc.bottom - ZOOM_BAR_H - SCROLL_H

    Select Case chartCount
        Case 1
            If hCharts(0) <> 0 Then MoveWindow(hCharts(0), cLeft, cTop, cW, cH, TRUE)
        Case 2
            Dim hw As Long = cW \ 2
            If hCharts(0) <> 0 Then MoveWindow(hCharts(0), cLeft,      cTop, hw,      cH, TRUE)
            If hCharts(1) <> 0 Then MoveWindow(hCharts(1), cLeft + hw, cTop, cW - hw, cH, TRUE)
        Case 4
            Dim hw2 As Long = cW \ 2
            Dim hh  As Long = cH \ 2
            If hCharts(0) <> 0 Then MoveWindow(hCharts(0), cLeft,       cTop,       hw2,      hh,      TRUE)
            If hCharts(1) <> 0 Then MoveWindow(hCharts(1), cLeft + hw2, cTop,       cW - hw2, hh,      TRUE)
            If hCharts(2) <> 0 Then MoveWindow(hCharts(2), cLeft,       cTop + hh,  hw2,      cH - hh, TRUE)
            If hCharts(3) <> 0 Then MoveWindow(hCharts(3), cLeft + hw2, cTop + hh,  cW - hw2, cH - hh, TRUE)
    End Select
End Sub

' ── Change le nombre de graphes actifs ───────────────────────────────────────
Sub SetChartCount(hParent As HWND, n As Integer)
    Dim i As Integer
    For i = 0 To MAX_CHARTS - 1
        If hCharts(i) <> 0 Then ShowWindow(hCharts(i), SW_HIDE)
    Next
    chartCount = n
    Dim hInst As HINSTANCE = GetModuleHandle(NULL)
    For i = 0 To n - 1
        If hCharts(i) = 0 Then
            hCharts(i) = CreateWindowEx(0, "QChartWnd", "", _
                WS_CHILD Or WS_VISIBLE Or WS_BORDER, _
                0, 0, 100, 100, hParent, Cast(HMENU, i), hInst, NULL)
            Dim pCDi As ChartWinData Ptr = GetChartData(hCharts(i))
            If pCDi <> NULL Then pCDi->chartIdx = i
        Else
            ShowWindow(hCharts(i), SW_SHOW)
            Dim pCDi As ChartWinData Ptr = GetChartData(hCharts(i))
            If pCDi <> NULL Then pCDi->chartIdx = i
        End If
    Next
    ArrangeChartWindows(hParent)
    activeChartIdx = 0
    If hCharts(0) <> 0 Then SetFocus(hCharts(0))
End Sub

' ── WndProc des fenêtres graphe enfant ───────────────────────────────────────
Function ChartWndProc(hWnd As HWND, uMsg As UINT, wParam As WPARAM, lParam As LPARAM) As LRESULT
    Dim pCD As ChartWinData Ptr = GetChartData(hWnd)

    Select Case uMsg

    Case WM_CREATE
        pCD = CAllocate(SizeOf(ChartWinData))
        pCD->hwnd        = hWnd
        pCD->chartIdx    = 0
        pCD->Chart.ViewStart = 0
        pCD->Chart.ViewCount = 60
        pCD->Chart.IsLoaded  = 0
        pCD->currentTool = ID_TOOL_SELECT
        pCD->isDrawing   = 0
        pCD->crosshairX  = -1
        pCD->crosshairY  = -1
        pCD->rightClickedOverlayIdx = -1
        ReDim pCD->Lines(-1)
        ReDim pCD->Circles(-1)
        ReDim pCD->FiboFans(-1)
        ReDim pCD->GannFans(-1)
        ReDim pCD->FiboRets(-1)
        ReDim pCD->GannGrids(-1)
        ReDim pCD->Pentagrams(-1)
        ReDim pCD->ParaLinesArr(-1)
        ReDim pCD->ActivePanels(-1)
        SetWindowLongPtr(hWnd, GWLP_USERDATA, Cast(LONG_PTR, pCD))
        Return 0

    Case WM_DESTROY
        If pCD <> NULL Then
            DeAllocate(pCD)
            SetWindowLongPtr(hWnd, GWLP_USERDATA, 0)
        End If
        Return 0

    Case WM_ERASEBKGND
        Return 1

    Case WM_PAINT
        If pCD = NULL Then Return DefWindowProc(hWnd, uMsg, wParam, lParam)
        Dim rcC As RECT : GetClientRect(hWnd, @rcC)
        Dim cw As Integer = rcC.right - rcC.left
        Dim ch As Integer = rcC.bottom - rcC.top
        Dim ps As PAINTSTRUCT
        Dim hDC2 As HDC = BeginPaint(hWnd, @ps)
        Dim hMemDC  As HDC     = CreateCompatibleDC(hDC2)
        Dim hBitmap As HBITMAP = CreateCompatibleBitmap(hDC2, cw, ch)
        Dim hOld    As HBITMAP = SelectObject(hMemDC, hBitmap)
        RenderChartGDIPlus(hWnd, hMemDC, cw, ch, pCD)
        BitBlt(hDC2, 0, 0, cw, ch, hMemDC, 0, 0, SRCCOPY)
        ' Bordure colorée si ce graphe est actif (dessinée sur le DC final)
        If pCD->chartIdx = activeChartIdx And chartCount > 1 Then
            Dim hBorderPen As HPEN = CreatePen(PS_SOLID, 3, RGB(0, 120, 215))
            Dim hOldPen As HPEN = SelectObject(hDC2, hBorderPen)
            Dim hNullBrush As HBRUSH = GetStockObject(NULL_BRUSH)
            Dim hOldBrush As HBRUSH = SelectObject(hDC2, hNullBrush)
            Rectangle(hDC2, 1, 1, cw - 1, ch - 1)
            SelectObject(hDC2, hOldPen)
            SelectObject(hDC2, hOldBrush)
            DeleteObject(hBorderPen)
        End If
        SelectObject(hMemDC, hOld)
        DeleteObject(hBitmap)
        DeleteDC(hMemDC)
        EndPaint(hWnd, @ps)
        Return 0

    Case WM_LBUTTONDOWN
        ' Activer ce graphe
        For fi As Integer = 0 To MAX_CHARTS - 1
            If hCharts(fi) = hWnd Then activeChartIdx = fi : Exit For
        Next fi
        SetFocus(hWnd)
        If pCD->Chart.IsLoaded = 0 Then Return 0
        ' Propager l'outil courant depuis la toolbar (stocké dans currentTool global)
        pCD->currentTool = currentTool

        Dim mx As Integer = LoWord(lParam)
        Dim my As Integer = HiWord(lParam)

        ' ── Recalcul de la géométrie depuis les dimensions courantes ──────────
        ' (même formules que RenderChartGDIPlus — ne pas dépendre du cache pCD->oriX etc.)
        Dim rcLB As RECT : GetClientRect(hWnd, @rcLB)
        Dim cwLB As Integer = rcLB.right  - rcLB.left
        Dim chLB As Integer = rcLB.bottom - rcLB.top

        Dim pcLB As Long = 0   ' nb de panels séparés
        Dim i As Integer
        For i = 0 To pCD->ActiveCount - 1
            If indRegistry.defs(pCD->ActivePanels(i).defIndex).isPanel = 1 Then pcLB += 1
        Next
        Dim rsiAreaH_LB As Integer = pcLB * (RSI_PANEL_H + RSI_PANEL_GAP)
        Dim mainChartH_LB As Integer = chLB - rsiAreaH_LB - 40 - ZOOM_BAR_H

        ' Echelle Y (nécessite vMin/vMax — utiliser le cache si disponible, sinon recalculer)
        Dim vMinLB As Double = pCD->vMin
        Dim vMaxLB As Double = pCD->vMax
        If vMinLB = 0 And vMaxLB = 0 Then
            vMinLB = 1e30 : vMaxLB = -1e30
            Dim lastIdxLB As Integer = pCD->Chart.ViewStart + pCD->Chart.ViewCount - 1
            If lastIdxLB > UBound(pCD->Chart.History) Then lastIdxLB = UBound(pCD->Chart.History)
            For i = pCD->Chart.ViewStart To lastIdxLB
                If pCD->Chart.History(i).L < vMinLB Then vMinLB = pCD->Chart.History(i).L
                If pCD->Chart.History(i).H > vMaxLB Then vMaxLB = pCD->Chart.History(i).H
            Next
            vMinLB *= 0.999 : vMaxLB *= 1.001
        End If

        Dim oriXlb As Single = 65 + toolbarW
        Dim oriYlb As Single = mainChartH_LB + ZOOM_BAR_H
        Dim lenXlb As Single = cwLB - 120 - toolbarW
        Dim lenYlb As Single = mainChartH_LB - 40
        Dim scaleYlb As Double = IIf(vMaxLB - vMinLB <> 0, lenYlb / (vMaxLB - vMinLB), 1)
        Dim stepXlb As Single = IIf(pCD->Chart.ViewCount > 0, lenXlb / pCD->Chart.ViewCount, 1)

        ' ── Sync complète des globales depuis pCD AVANT tout appel helper ────
        ' QChart doit refléter CE graphe (SnapToCandle, HitTestCanvas l'utilisent)
        QChart = pCD->Chart

        ' mainChartH_cached utilisé par HitTestCanvas — recalculer proprement
        mainChartH_cached = mainChartH_LB

        ' Sync globales géométrie (déjà calculées ci-dessus)
        g_oriX   = oriXlb  : g_oriY   = oriYlb
        g_stepX  = stepXlb : g_scaleY = scaleYlb
        g_vMin   = vMinLB  : g_vMax   = vMaxLB
        g_lenY   = lenYlb

        ' Sync cache pCD pour cohérence avec le prochain rendu
        pCD->oriX   = oriXlb  : pCD->oriY   = oriYlb
        pCD->stepX  = stepXlb : pCD->scaleY = scaleYlb
        pCD->vMin   = vMinLB  : pCD->vMax   = vMaxLB
        pCD->lenY   = lenYlb
        pCD->mainChartH_cached = mainChartH_LB

        PanelGeomCount = pCD->PanelGeomCount
        For i = 0 To pCD->PanelGeomCount - 1
            PanelGeoms(i) = pCD->PanelGeoms(i)
        Next

        ' Détection clic ✕ sur panneaux / overlays actifs
        Dim panelHitIdx As Long = 0
        Dim globalOvHitIdx As Long = 0
        Dim panelCnt As Long = 0
        For i As Integer = 0 To pCD->ActiveCount - 1
            If indRegistry.defs(pCD->ActivePanels(i).defIndex).isPanel = 1 Then panelCnt += 1
        Next
        ' oriX réel : calculé comme dans RenderChartGDIPlus
        Dim rcHT As RECT : GetClientRect(hWnd, @rcHT)
        Dim htOriX As Long = 65 + toolbarW   ' même formule que RenderChartGDIPlus
        Dim htLenX As Single = (rcHT.right - rcHT.left) - 120 - toolbarW
        Dim htMainH As Long  = (rcHT.bottom - rcHT.top) - panelCnt * (RSI_PANEL_H + RSI_PANEL_GAP) - 40 - ZOOM_BAR_H

        For i As Integer = 0 To pCD->ActiveCount - 1
            Dim def As IndicatorDef = indRegistry.defs(pCD->ActivePanels(i).defIndex)
            If def.isPanel = 0 Then
                ' Overlay : zone hit = label entier + croix, tolérance +4px de chaque côté
                Dim maLbl As String = def.labelPrefix & "(" & pCD->ActivePanels(i).period & ")"
                Dim htLblX As Long = htOriX + 4
                Dim htLblY As Long = ZOOM_BAR_H + 14 + globalOvHitIdx * (RSI_CLOSE_BTN + 4)
                Dim htZoneW As Long = Len(maLbl) * 7 + 3 + RSI_CLOSE_BTN + 8
                Dim htZoneH As Long = RSI_CLOSE_BTN + 8
                If mx >= htLblX And mx <= htLblX + htZoneW And _
                   my >= htLblY - 4 And my <= htLblY - 4 + htZoneH Then
                    For j As Integer = i To pCD->ActiveCount - 2 : pCD->ActivePanels(j) = pCD->ActivePanels(j+1) : Next
                    pCD->ActiveCount -= 1
                    If pCD->ActiveCount = 0 Then ReDim pCD->ActivePanels(-1) Else ReDim Preserve pCD->ActivePanels(pCD->ActiveCount - 1)
                    InvalidateRect(hWnd, NULL, FALSE) : Return 0
                End If
                globalOvHitIdx += 1
            Else
                ' Panel séparé : croix en haut à droite, position exacte comme dans RenderChartGDIPlus
                Dim htRTop As Long = htMainH + RSI_PANEL_MARGIN + panelHitIdx * (RSI_PANEL_H + RSI_PANEL_GAP)
                Dim htBxRSI As Single = htOriX + htLenX - RSI_CLOSE_BTN - 2
                Dim htByRSI As Single = htRTop + 2
                ' Zone de hit élargie +6px de chaque côté
                If mx >= htBxRSI - 6 And mx <= htBxRSI + RSI_CLOSE_BTN + 6 And _
                   my >= htByRSI - 6 And my <= htByRSI + RSI_CLOSE_BTN + 6 Then
                    For j As Integer = i To pCD->ActiveCount - 2 : pCD->ActivePanels(j) = pCD->ActivePanels(j+1) : Next
                    pCD->ActiveCount -= 1
                    If pCD->ActiveCount = 0 Then ReDim pCD->ActivePanels(-1) Else ReDim Preserve pCD->ActivePanels(pCD->ActiveCount - 1)
                    InvalidateRect(hWnd, NULL, FALSE) : Return 0
                End If
                panelHitIdx += 1
            End If
        Next

        Select Case pCD->currentTool
        Case ID_TOOL_LINE
            Dim clickCanvas As Integer = HitTestCanvas(mx, my)
            If clickCanvas = -1 Then Return 0
            If pCD->isDrawing = 0 Then
                If clickCanvas = 0 Then
                    SnapToCandle(mx, my)
                    pCD->tmpBar   = g_snapBar
                    pCD->tmpPrice = g_snapPrice
                Else
                    pCD->tmpBar   = pCD->Chart.ViewStart + CInt((mx - g_oriX) / g_stepX)
                    pCD->tmpPrice = ScreenYToValue(my, clickCanvas)
                End If
                pCD->tmpCanvasType = clickCanvas
                pCD->isDrawing = 1
            Else
                Dim n As Integer = UBound(pCD->Lines) + 1
                ReDim Preserve pCD->Lines(n)
                pCD->Lines(n).bar1       = pCD->tmpBar
                pCD->Lines(n).price1     = pCD->tmpPrice
                pCD->Lines(n).canvasType = pCD->tmpCanvasType
                If pCD->tmpCanvasType = 0 Then
                    SnapToCandle(mx, my)
                    pCD->Lines(n).bar2   = g_snapBar
                    pCD->Lines(n).price2 = g_snapPrice
                Else
                    pCD->Lines(n).bar2   = pCD->Chart.ViewStart + CInt((mx - g_oriX) / g_stepX)
                    pCD->Lines(n).price2 = ScreenYToValue(my, pCD->tmpCanvasType)
                End If
                pCD->isDrawing = 0
            End If
        Case ID_TOOL_CIRCLE
            SnapToCandle(mx, my)
            pCD->circleClickNb += 1
            pCD->circleBar(pCD->circleClickNb)   = g_snapBar
            pCD->circlePrice(pCD->circleClickNb) = g_snapPrice
            If pCD->circleClickNb = 3 Then
                Dim nc As Integer = UBound(pCD->Circles) + 1
                ReDim Preserve pCD->Circles(nc)
                pCD->Circles(nc).bar1   = pCD->circleBar(1)   : pCD->Circles(nc).price1 = pCD->circlePrice(1)
                pCD->Circles(nc).bar2   = pCD->circleBar(2)   : pCD->Circles(nc).price2 = pCD->circlePrice(2)
                pCD->Circles(nc).bar3   = pCD->circleBar(3)   : pCD->Circles(nc).price3 = pCD->circlePrice(3)
                pCD->circleClickNb = 0
            End If
        Case ID_TOOL_FIBOFAN
            SnapToCandle(mx, my)
            pCD->fiboFanClickNb += 1
            If pCD->fiboFanClickNb = 1 Then
                pCD->fiboFanBar1   = g_snapBar
                pCD->fiboFanPrice1 = g_snapPrice
            Else
                Dim nff As Integer = UBound(pCD->FiboFans) + 1
                ReDim Preserve pCD->FiboFans(nff)
                pCD->FiboFans(nff).bar1   = pCD->fiboFanBar1   : pCD->FiboFans(nff).price1 = pCD->fiboFanPrice1
                pCD->FiboFans(nff).bar2   = g_snapBar          : pCD->FiboFans(nff).price2 = g_snapPrice
                pCD->fiboFanClickNb = 0
            End If
        Case ID_TOOL_GANNFAN
            SnapToCandle(mx, my)
            pCD->gannFanClickNb += 1
            If pCD->gannFanClickNb = 1 Then
                pCD->gannFanBar1   = g_snapBar
                pCD->gannFanPrice1 = g_snapPrice
            Else
                Dim ngf As Integer = UBound(pCD->GannFans) + 1
                ReDim Preserve pCD->GannFans(ngf)
                pCD->GannFans(ngf).bar1   = pCD->gannFanBar1   : pCD->GannFans(ngf).price1 = pCD->gannFanPrice1
                pCD->GannFans(ngf).bar2   = g_snapBar          : pCD->GannFans(ngf).price2 = g_snapPrice
                pCD->gannFanClickNb = 0
            End If
        Case ID_TOOL_FIBORET
            SnapToCandle(mx, my)
            pCD->fiboRetClickNb += 1
            If pCD->fiboRetClickNb = 1 Then
                pCD->fiboRetBar1   = g_snapBar
                pCD->fiboRetPrice1 = g_snapPrice
            Else
                Dim nfr As Integer = UBound(pCD->FiboRets) + 1
                ReDim Preserve pCD->FiboRets(nfr)
                pCD->FiboRets(nfr).bar1   = pCD->fiboRetBar1   : pCD->FiboRets(nfr).price1 = pCD->fiboRetPrice1
                pCD->FiboRets(nfr).bar2   = g_snapBar          : pCD->FiboRets(nfr).price2 = g_snapPrice
                pCD->fiboRetClickNb = 0
            End If
        Case ID_TOOL_GANNGRID
            SnapToCandle(mx, my)
            pCD->gannGridClickNb += 1
            If pCD->gannGridClickNb = 1 Then
                pCD->gannGridBar1   = g_snapBar
                pCD->gannGridPrice1 = g_snapPrice
            Else
                Dim ngg As Integer = UBound(pCD->GannGrids) + 1
                ReDim Preserve pCD->GannGrids(ngg)
                pCD->GannGrids(ngg).bar1   = pCD->gannGridBar1   : pCD->GannGrids(ngg).price1 = pCD->gannGridPrice1
                pCD->GannGrids(ngg).bar2   = g_snapBar           : pCD->GannGrids(ngg).price2 = g_snapPrice
                pCD->gannGridClickNb = 0
            End If
        Case ID_TOOL_PENTAGRAM
            SnapToCandle(mx, my)
            pCD->pentaClickNb += 1
            If pCD->pentaClickNb = 1 Then
                pCD->pentaBar1   = g_snapBar
                pCD->pentaPrice1 = g_snapPrice
            Else
                Dim npt As Integer = UBound(pCD->Pentagrams) + 1
                ReDim Preserve pCD->Pentagrams(npt)
                pCD->Pentagrams(npt).bar1   = pCD->pentaBar1   : pCD->Pentagrams(npt).price1 = pCD->pentaPrice1
                pCD->Pentagrams(npt).bar2   = g_snapBar        : pCD->Pentagrams(npt).price2 = g_snapPrice
                pCD->pentaClickNb = 0
            End If
        Case ID_TOOL_PARALINES
            SnapToCandle(mx, my)
            pCD->paraClickNb += 1
            If pCD->paraClickNb = 1 Then
                pCD->paraBar1   = g_snapBar
                pCD->paraPrice1 = g_snapPrice
            ElseIf pCD->paraClickNb = 2 Then
                pCD->paraBar2   = g_snapBar
                pCD->paraPrice2 = g_snapPrice
            Else
                Dim npl As Integer = UBound(pCD->ParaLinesArr) + 1
                ReDim Preserve pCD->ParaLinesArr(npl)
                pCD->ParaLinesArr(npl).bar1   = pCD->paraBar1   : pCD->ParaLinesArr(npl).price1 = pCD->paraPrice1
                pCD->ParaLinesArr(npl).bar2   = pCD->paraBar2   : pCD->ParaLinesArr(npl).price2 = pCD->paraPrice2
                pCD->ParaLinesArr(npl).bar3   = g_snapBar       : pCD->ParaLinesArr(npl).price3 = g_snapPrice
                pCD->paraClickNb = 0
            End If
        Case ID_TOOL_ERASER
            Dim ERASE_R As Single = 15.0   ' rayon de hit en pixels

            ' Helper inline : distance point-point
            #define EPtDist(ax,ay,bx,by) Sqr(((ax)-(bx))^2+((ay)-(by))^2)

            ' ── Trendlines ───────────────────────────────────────────────────
            Dim foundE As Integer = -1
            Dim bestDistE As Single = 1e30
            Dim eiE As Integer
            For eiE = 0 To UBound(pCD->Lines)
                Dim ex1 As Single = g_oriX + (pCD->Lines(eiE).bar1 - pCD->Chart.ViewStart) * g_stepX + (g_stepX/2)
                Dim ey1 As Single = ValueToScreenY(pCD->Lines(eiE).price1, pCD->Lines(eiE).canvasType)
                Dim ex2 As Single = g_oriX + (pCD->Lines(eiE).bar2 - pCD->Chart.ViewStart) * g_stepX + (g_stepX/2)
                Dim ey2 As Single = ValueToScreenY(pCD->Lines(eiE).price2, pCD->Lines(eiE).canvasType)
                Dim dE As Single = DistToSegment(CSng(mx), CSng(my), ex1, ey1, ex2, ey2)
                Dim d1E As Single = EPtDist(CSng(mx), CSng(my), ex1, ey1)
                Dim d2E As Single = EPtDist(CSng(mx), CSng(my), ex2, ey2)
                If d1E < dE Then dE = d1E
                If d2E < dE Then dE = d2E
                If dE < bestDistE Then bestDistE = dE : foundE = eiE
            Next
            If foundE > -1 And bestDistE < ERASE_R Then
                For j As Integer = foundE To UBound(pCD->Lines) - 1 : pCD->Lines(j) = pCD->Lines(j+1) : Next
                If UBound(pCD->Lines) = 0 Then ReDim pCD->Lines(-1) Else ReDim Preserve pCD->Lines(UBound(pCD->Lines) - 1)
                InvalidateRect(hWnd, NULL, FALSE) : Return 0
            End If

            ' ── Cercles ──────────────────────────────────────────────────────
            Dim foundC As Integer = -1
            Dim bestDistC As Single = 1e30
            Dim eiC As Integer
            For eiC = 0 To UBound(pCD->Circles)
                ' Recalculer centre et rayon du cercle en pixels
                Dim cpx1 As Single = g_oriX + (pCD->Circles(eiC).bar1 - pCD->Chart.ViewStart) * g_stepX + g_stepX*0.5
                Dim cpy1 As Single = ValueToScreenY(pCD->Circles(eiC).price1, 0)
                Dim cpx2 As Single = g_oriX + (pCD->Circles(eiC).bar2 - pCD->Chart.ViewStart) * g_stepX + g_stepX*0.5
                Dim cpy2 As Single = ValueToScreenY(pCD->Circles(eiC).price2, 0)
                Dim cpx3 As Single = g_oriX + (pCD->Circles(eiC).bar3 - pCD->Chart.ViewStart) * g_stepX + g_stepX*0.5
                Dim cpy3 As Single = ValueToScreenY(pCD->Circles(eiC).price3, 0)
                ' Distance aux 3 points de contrôle
                Dim dc1 As Single = EPtDist(CSng(mx), CSng(my), cpx1, cpy1)
                Dim dc2 As Single = EPtDist(CSng(mx), CSng(my), cpx2, cpy2)
                Dim dc3 As Single = EPtDist(CSng(mx), CSng(my), cpx3, cpy3)
                Dim dcMin As Single = dc1
                If dc2 < dcMin Then dcMin = dc2
                If dc3 < dcMin Then dcMin = dc3
                ' Distance au cercle lui-même (si centre calculable)
                Dim cxda As Double = cpx2 - cpx1 : Dim cyda As Double = cpy2 - cpy1
                Dim cxdb As Double = cpx3 - cpx2 : Dim cydb As Double = cpy3 - cpy2
                If Abs(cxda) > 0.001 And Abs(cxdb) > 0.001 Then
                    Dim caSlp As Double = cyda / cxda : Dim cbSlp As Double = cydb / cxdb
                    If Abs(cbSlp - caSlp) > 0.001 Then
                        Dim ccx As Single = CSng((caSlp*cbSlp*(cpy1-cpy3)+cbSlp*(cpx1+cpx2)-caSlp*(cpx2+cpx3))/(2.0*(cbSlp-caSlp)))
                        Dim ccy As Single = CSng(-1.0*(ccx-(cpx1+cpx2)/2.0)/caSlp+(cpy1+cpy2)/2.0)
                        Dim cRad As Single = EPtDist(cpx1, cpy1, ccx, ccy)
                        Dim dFromCenter As Single = EPtDist(CSng(mx), CSng(my), ccx, ccy)
                        Dim dCirc As Single = Abs(dFromCenter - cRad)
                        If dCirc < dcMin Then dcMin = dCirc
                    End If
                End If
                If dcMin < bestDistC Then bestDistC = dcMin : foundC = eiC
            Next
            If foundC > -1 And bestDistC < ERASE_R Then
                For j As Integer = foundC To UBound(pCD->Circles) - 1 : pCD->Circles(j) = pCD->Circles(j+1) : Next
                If UBound(pCD->Circles) = 0 Then ReDim pCD->Circles(-1) Else ReDim Preserve pCD->Circles(UBound(pCD->Circles) - 1)
                InvalidateRect(hWnd, NULL, FALSE) : Return 0
            End If

            ' ── FiboFans ─────────────────────────────────────────────────────
            Dim foundFF As Integer = -1 : Dim bestFF As Single = 1e30
            For eiC = 0 To UBound(pCD->FiboFans)
                Dim ffx1 As Single = g_oriX + (pCD->FiboFans(eiC).bar1 - pCD->Chart.ViewStart) * g_stepX + g_stepX*0.5
                Dim ffy1 As Single = ValueToScreenY(pCD->FiboFans(eiC).price1, 0)
                Dim ffx2 As Single = g_oriX + (pCD->FiboFans(eiC).bar2 - pCD->Chart.ViewStart) * g_stepX + g_stepX*0.5
                Dim ffy2 As Single = ValueToScreenY(pCD->FiboFans(eiC).price2, 0)
                Dim dFF As Single = DistToSegment(CSng(mx), CSng(my), ffx1, ffy1, ffx2, ffy2)
                Dim dFF1 As Single = EPtDist(CSng(mx), CSng(my), ffx1, ffy1)
                Dim dFF2 As Single = EPtDist(CSng(mx), CSng(my), ffx2, ffy2)
                If dFF1 < dFF Then dFF = dFF1
                If dFF2 < dFF Then dFF = dFF2
                If dFF < bestFF Then bestFF = dFF : foundFF = eiC
            Next
            If foundFF > -1 And bestFF < ERASE_R Then
                For j As Integer = foundFF To UBound(pCD->FiboFans) - 1 : pCD->FiboFans(j) = pCD->FiboFans(j+1) : Next
                If UBound(pCD->FiboFans) = 0 Then ReDim pCD->FiboFans(-1) Else ReDim Preserve pCD->FiboFans(UBound(pCD->FiboFans) - 1)
                InvalidateRect(hWnd, NULL, FALSE) : Return 0
            End If

            ' ── GannFans ─────────────────────────────────────────────────────
            Dim foundGF As Integer = -1 : Dim bestGF As Single = 1e30
            For eiC = 0 To UBound(pCD->GannFans)
                Dim gfx1 As Single = g_oriX + (pCD->GannFans(eiC).bar1 - pCD->Chart.ViewStart) * g_stepX + g_stepX*0.5
                Dim gfy1 As Single = ValueToScreenY(pCD->GannFans(eiC).price1, 0)
                Dim gfx2 As Single = g_oriX + (pCD->GannFans(eiC).bar2 - pCD->Chart.ViewStart) * g_stepX + g_stepX*0.5
                Dim gfy2 As Single = ValueToScreenY(pCD->GannFans(eiC).price2, 0)
                Dim dGF As Single = DistToSegment(CSng(mx), CSng(my), gfx1, gfy1, gfx2, gfy2)
                Dim dGF1 As Single = EPtDist(CSng(mx), CSng(my), gfx1, gfy1)
                If dGF1 < dGF Then dGF = dGF1
                If dGF < bestGF Then bestGF = dGF : foundGF = eiC
            Next
            If foundGF > -1 And bestGF < ERASE_R Then
                For j As Integer = foundGF To UBound(pCD->GannFans) - 1 : pCD->GannFans(j) = pCD->GannFans(j+1) : Next
                If UBound(pCD->GannFans) = 0 Then ReDim pCD->GannFans(-1) Else ReDim Preserve pCD->GannFans(UBound(pCD->GannFans) - 1)
                InvalidateRect(hWnd, NULL, FALSE) : Return 0
            End If

            ' ── FiboRetracements ─────────────────────────────────────────────
            Dim foundFR As Integer = -1 : Dim bestFR As Single = 1e30
            For eiC = 0 To UBound(pCD->FiboRets)
                Dim frx1 As Single = g_oriX + (pCD->FiboRets(eiC).bar1 - pCD->Chart.ViewStart) * g_stepX + g_stepX*0.5
                Dim fry1 As Single = ValueToScreenY(pCD->FiboRets(eiC).price1, 0)
                Dim frx2 As Single = g_oriX + (pCD->FiboRets(eiC).bar2 - pCD->Chart.ViewStart) * g_stepX + g_stepX*0.5
                Dim fry2 As Single = ValueToScreenY(pCD->FiboRets(eiC).price2, 0)
                Dim dFR1 As Single = EPtDist(CSng(mx), CSng(my), frx1, fry1)
                Dim dFR2 As Single = EPtDist(CSng(mx), CSng(my), frx2, fry2)
                Dim dFR As Single = IIf(dFR1 < dFR2, dFR1, dFR2)
                If dFR < bestFR Then bestFR = dFR : foundFR = eiC
            Next
            If foundFR > -1 And bestFR < ERASE_R Then
                For j As Integer = foundFR To UBound(pCD->FiboRets) - 1 : pCD->FiboRets(j) = pCD->FiboRets(j+1) : Next
                If UBound(pCD->FiboRets) = 0 Then ReDim pCD->FiboRets(-1) Else ReDim Preserve pCD->FiboRets(UBound(pCD->FiboRets) - 1)
                InvalidateRect(hWnd, NULL, FALSE) : Return 0
            End If

            ' ── GannGrids ────────────────────────────────────────────────────
            Dim foundGG As Integer = -1 : Dim bestGG As Single = 1e30
            For eiC = 0 To UBound(pCD->GannGrids)
                Dim ggx1 As Single = g_oriX + (pCD->GannGrids(eiC).bar1 - pCD->Chart.ViewStart) * g_stepX + g_stepX*0.5
                Dim ggy1 As Single = ValueToScreenY(pCD->GannGrids(eiC).price1, 0)
                Dim ggx2 As Single = g_oriX + (pCD->GannGrids(eiC).bar2 - pCD->Chart.ViewStart) * g_stepX + g_stepX*0.5
                Dim ggy2 As Single = ValueToScreenY(pCD->GannGrids(eiC).price2, 0)
                Dim dGG1 As Single = EPtDist(CSng(mx), CSng(my), ggx1, ggy1)
                Dim dGG2 As Single = EPtDist(CSng(mx), CSng(my), ggx2, ggy2)
                Dim dGG As Single = IIf(dGG1 < dGG2, dGG1, dGG2)
                If dGG < bestGG Then bestGG = dGG : foundGG = eiC
            Next
            If foundGG > -1 And bestGG < ERASE_R Then
                For j As Integer = foundGG To UBound(pCD->GannGrids) - 1 : pCD->GannGrids(j) = pCD->GannGrids(j+1) : Next
                If UBound(pCD->GannGrids) = 0 Then ReDim pCD->GannGrids(-1) Else ReDim Preserve pCD->GannGrids(UBound(pCD->GannGrids) - 1)
                InvalidateRect(hWnd, NULL, FALSE) : Return 0
            End If

            ' ── Pentagrams ───────────────────────────────────────────────────
            Dim foundPT As Integer = -1 : Dim bestPT As Single = 1e30
            For eiC = 0 To UBound(pCD->Pentagrams)
                Dim ptx1 As Single = g_oriX + (pCD->Pentagrams(eiC).bar1 - pCD->Chart.ViewStart) * g_stepX + g_stepX*0.5
                Dim pty1 As Single = ValueToScreenY(pCD->Pentagrams(eiC).price1, 0)
                Dim ptx2 As Single = g_oriX + (pCD->Pentagrams(eiC).bar2 - pCD->Chart.ViewStart) * g_stepX + g_stepX*0.5
                Dim pty2 As Single = ValueToScreenY(pCD->Pentagrams(eiC).price2, 0)
                Dim dPT1 As Single = EPtDist(CSng(mx), CSng(my), ptx1, pty1)
                Dim dPT2 As Single = EPtDist(CSng(mx), CSng(my), ptx2, pty2)
                Dim dPT As Single = IIf(dPT1 < dPT2, dPT1, dPT2)
                If dPT < bestPT Then bestPT = dPT : foundPT = eiC
            Next
            If foundPT > -1 And bestPT < ERASE_R Then
                For j As Integer = foundPT To UBound(pCD->Pentagrams) - 1 : pCD->Pentagrams(j) = pCD->Pentagrams(j+1) : Next
                If UBound(pCD->Pentagrams) = 0 Then ReDim pCD->Pentagrams(-1) Else ReDim Preserve pCD->Pentagrams(UBound(pCD->Pentagrams) - 1)
                InvalidateRect(hWnd, NULL, FALSE) : Return 0
            End If

            ' ── ParaLines ────────────────────────────────────────────────────
            Dim foundPL As Integer = -1 : Dim bestPL As Single = 1e30
            For eiC = 0 To UBound(pCD->ParaLinesArr)
                Dim plx1 As Single = g_oriX + (pCD->ParaLinesArr(eiC).bar1 - pCD->Chart.ViewStart) * g_stepX + g_stepX*0.5
                Dim ply1 As Single = ValueToScreenY(pCD->ParaLinesArr(eiC).price1, 0)
                Dim plx2 As Single = g_oriX + (pCD->ParaLinesArr(eiC).bar2 - pCD->Chart.ViewStart) * g_stepX + g_stepX*0.5
                Dim ply2 As Single = ValueToScreenY(pCD->ParaLinesArr(eiC).price2, 0)
                Dim plx3 As Single = g_oriX + (pCD->ParaLinesArr(eiC).bar3 - pCD->Chart.ViewStart) * g_stepX + g_stepX*0.5
                Dim ply3 As Single = ValueToScreenY(pCD->ParaLinesArr(eiC).price3, 0)
                Dim dPL1 As Single = EPtDist(CSng(mx), CSng(my), plx1, ply1)
                Dim dPL2 As Single = EPtDist(CSng(mx), CSng(my), plx2, ply2)
                Dim dPL3 As Single = EPtDist(CSng(mx), CSng(my), plx3, ply3)
                Dim dPL As Single = dPL1
                If dPL2 < dPL Then dPL = dPL2
                If dPL3 < dPL Then dPL = dPL3
                If dPL < bestPL Then bestPL = dPL : foundPL = eiC
            Next
            If foundPL > -1 And bestPL < ERASE_R Then
                For j As Integer = foundPL To UBound(pCD->ParaLinesArr) - 1 : pCD->ParaLinesArr(j) = pCD->ParaLinesArr(j+1) : Next
                If UBound(pCD->ParaLinesArr) = 0 Then ReDim pCD->ParaLinesArr(-1) Else ReDim Preserve pCD->ParaLinesArr(UBound(pCD->ParaLinesArr) - 1)
                InvalidateRect(hWnd, NULL, FALSE) : Return 0
            End If
        End Select
        InvalidateRect(hWnd, NULL, FALSE)
        Return 0

    Case WM_MOUSEMOVE
        If pCD = NULL Then Return DefWindowProc(hWnd, uMsg, wParam, lParam)
        pCD->currentTool = currentTool
        If pCD->currentTool = ID_TOOL_CROSSHAIR And pCD->Chart.IsLoaded Then
            pCD->crosshairX = LoWord(lParam) : pCD->crosshairY = HiWord(lParam)
            SetCursor(LoadCursor(NULL, IDC_CROSS))
            InvalidateRect(hWnd, NULL, FALSE)
        ElseIf pCD->Chart.IsLoaded And ( _
            (pCD->currentTool = ID_TOOL_LINE     And pCD->isDrawing = 1) Or _
            (pCD->currentTool = ID_TOOL_FIBOFAN  And pCD->fiboFanClickNb  = 1) Or _
            (pCD->currentTool = ID_TOOL_GANNFAN  And pCD->gannFanClickNb  = 1) Or _
            (pCD->currentTool = ID_TOOL_FIBORET  And pCD->fiboRetClickNb  = 1) Or _
            (pCD->currentTool = ID_TOOL_GANNGRID And pCD->gannGridClickNb = 1) Or _
            (pCD->currentTool = ID_TOOL_PENTAGRAM And pCD->pentaClickNb   = 1) Or _
            (pCD->currentTool = ID_TOOL_CIRCLE   And pCD->circleClickNb  >= 1) Or _
            (pCD->currentTool = ID_TOOL_PARALINES And pCD->paraClickNb   >= 1)) Then
            InvalidateRect(hWnd, NULL, FALSE)
        End If
        Return 0

    Case WM_RBUTTONDOWN
        If pCD = NULL Then Return DefWindowProc(hWnd, uMsg, wParam, lParam)
        pCD->currentTool = currentTool
        If pCD->isDrawing     Then pCD->isDrawing     = 0 : InvalidateRect(hWnd, NULL, FALSE) : Return 0
        If pCD->circleClickNb  > 0 Then pCD->circleClickNb  = 0 : InvalidateRect(hWnd, NULL, FALSE) : Return 0
        If pCD->fiboFanClickNb > 0 Then pCD->fiboFanClickNb = 0 : InvalidateRect(hWnd, NULL, FALSE) : Return 0
        If pCD->gannFanClickNb > 0 Then pCD->gannFanClickNb = 0 : InvalidateRect(hWnd, NULL, FALSE) : Return 0
        If pCD->fiboRetClickNb > 0 Then pCD->fiboRetClickNb = 0 : InvalidateRect(hWnd, NULL, FALSE) : Return 0
        If pCD->gannGridClickNb > 0 Then pCD->gannGridClickNb = 0 : InvalidateRect(hWnd, NULL, FALSE) : Return 0
        If pCD->pentaClickNb   > 0 Then pCD->pentaClickNb   = 0 : InvalidateRect(hWnd, NULL, FALSE) : Return 0
        If pCD->paraClickNb    > 0 Then pCD->paraClickNb    = 0 : InvalidateRect(hWnd, NULL, FALSE) : Return 0

        ' Sync globales pour HitTestOverlayLabel/HitTestPanelArea
        ' Recalcul depuis dimensions courantes (même logique que WM_LBUTTONDOWN)
        Dim rcRB As RECT : GetClientRect(hWnd, @rcRB)
        Dim cwRB As Integer = rcRB.right - rcRB.left
        Dim chRB As Integer = rcRB.bottom - rcRB.top
        Dim pcRB As Long = 0
        Dim iiRB As Integer
        For iiRB = 0 To pCD->ActiveCount - 1
            If indRegistry.defs(pCD->ActivePanels(iiRB).defIndex).isPanel = 1 Then pcRB += 1
        Next
        Dim mainHrb As Integer = chRB - pcRB * (RSI_PANEL_H + RSI_PANEL_GAP) - 40 - ZOOM_BAR_H
        Dim vMinRB As Double = pCD->vMin : Dim vMaxRB As Double = pCD->vMax
        If vMinRB = 0 And vMaxRB = 0 Then vMinRB = 1.0 : vMaxRB = 2.0
        Dim oriXrb As Single = 65 + toolbarW
        Dim oriYrb As Single = mainHrb + ZOOM_BAR_H
        Dim lenXrb As Single = cwRB - 120 - toolbarW
        Dim lenYrb As Single = mainHrb - 40
        Dim scaleYrb As Double = IIf(vMaxRB - vMinRB <> 0, lenYrb / (vMaxRB - vMinRB), 1)
        Dim stepXrb As Single = IIf(pCD->Chart.ViewCount > 0, lenXrb / pCD->Chart.ViewCount, 1)
        g_oriX = oriXrb : g_oriY = oriYrb : g_stepX = stepXrb
        g_scaleY = scaleYrb : g_vMin = vMinRB : g_vMax = vMaxRB : g_lenY = lenYrb
        ' Sync QChart et mainChartH_cached pour HitTestCanvas et helpers
        QChart = pCD->Chart
        mainChartH_cached = mainHrb
        PanelGeomCount = pCD->PanelGeomCount
        Dim rmxi As Integer
        For rmxi = 0 To pCD->PanelGeomCount - 1 : PanelGeoms(rmxi) = pCD->PanelGeoms(rmxi) : Next
        ActiveCount = pCD->ActiveCount
        If pCD->ActiveCount > 0 Then ReDim ActivePanels(pCD->ActiveCount - 1)
        For rmxi = 0 To pCD->ActiveCount - 1 : ActivePanels(rmxi) = pCD->ActivePanels(rmxi) : Next

        Dim rmx As Integer = LoWord(lParam)
        Dim rmy As Integer = HiWord(lParam)

        ' ── Tester d'abord si clic sur un indicator label/panel ──────────────
        Dim hitInd As Integer = HitTestOverlayLabel(rmx, rmy)
        If hitInd < 0 Then hitInd = HitTestPanelArea(rmx, rmy)

        ' ── Construire le menu contextuel ────────────────────────────────────
        Dim hPop As HMENU = CreatePopupMenu()

        ' Toujours présent : charger un CSV dans ce graphe
        Dim zLoad As ZString * 32 = "Charger CSV..."
        AppendMenu(hPop, MF_STRING, ID_CHART_LOADCSV, @zLoad)

        ' Toujours présent : ouvrir la fenêtre indicateurs pour ce graphe
        Dim zTech As ZString * 32 = "Indicateurs techniques..."
        AppendMenu(hPop, MF_STRING, ID_CHART_TECHNICALS, @zTech)

        ' Séparateur + option indicateur si clic sur un label
        If hitInd >= 0 Then
            AppendMenu(hPop, MF_SEPARATOR, 0, NULL)
            pCD->rightClickedOverlayIdx = hitInd : rightClickedOverlayIdx = hitInd
            Dim defR As IndicatorDef = indRegistry.defs(pCD->ActivePanels(hitInd).defIndex)
            Dim mLbl As String = "Parametres " & defR.labelPrefix & "(" & pCD->ActivePanels(hitInd).period & ")..."
            Dim zmLbl As ZString * 64 : zmLbl = mLbl
            AppendMenu(hPop, MF_STRING, ID_POPUP_PARAMS, @zmLbl)
        End If

        Dim pt2 As POINT : pt2.x = rmx : pt2.y = rmy
        ClientToScreen(hWnd, @pt2)
        Dim cmdR As Integer = TrackPopupMenu(hPop, TPM_LEFTALIGN Or TPM_RIGHTBUTTON Or TPM_RETURNCMD, pt2.x, pt2.y, 0, hWnd, NULL)
        DestroyMenu(hPop)

        If cmdR = ID_CHART_LOADCSV Then
            Dim fR As String = File_GetName(GetParent(hWnd))
            If fR <> "" Then LoadCSVToChart(fR, pCD, GetParent(hWnd))
        ElseIf cmdR = ID_CHART_TECHNICALS Then
            OpenTechnicalsForChart(GetParent(hWnd), pCD->chartIdx)
        ElseIf cmdR = ID_POPUP_PARAMS And hitInd >= 0 Then
            PostMessage(GetParent(hWnd), WM_COMMAND, ID_POPUP_PARAMS, 0)
        End If
        Return 0

    Case WM_MOUSEWHEEL
        If pCD = NULL Or pCD->Chart.IsLoaded = 0 Then Return 0
        Dim deltaMW As Short = HiWord(wParam)
        Dim cpMW As Integer = pCD->Chart.ViewStart
        If deltaMW < 0 Then cpMW += 5 Else cpMW -= 5
        Dim msMW As Integer = (UBound(pCD->Chart.History) + 1) - pCD->Chart.ViewCount
        If cpMW < 0 Then cpMW = 0
        If cpMW > msMW Then cpMW = msMW
        pCD->Chart.ViewStart = cpMW
        If pCD->chartIdx = activeChartIdx Then SetScrollPos(hScroll, SB_CTL, cpMW, TRUE)
        InvalidateRect(hWnd, NULL, FALSE)
        Return 0

    Case WM_SETFOCUS
        For fi As Integer = 0 To MAX_CHARTS - 1
            If hCharts(fi) = hWnd Then activeChartIdx = fi : Exit For
        Next fi
        ' Sync scrollbar avec les données propres à ce graphe
        If pCD <> NULL And pCD->Chart.IsLoaded Then
            Dim msSF As Integer = (UBound(pCD->Chart.History) + 1) - pCD->Chart.ViewCount
            If msSF < 0 Then msSF = 0
            SetScrollRange(hScroll, SB_CTL, 0, msSF, TRUE)
            SetScrollPos(hScroll, SB_CTL, pCD->Chart.ViewStart, TRUE)
            QChart = pCD->Chart
        Else
            SetScrollRange(hScroll, SB_CTL, 0, 0, TRUE)
            SetScrollPos(hScroll, SB_CTL, 0, TRUE)
        End If
        ' Redessiner tous les graphes pour mettre à jour la bordure active/inactive
        Dim rfi As Integer
        For rfi = 0 To MAX_CHARTS - 1
            If hCharts(rfi) <> 0 Then InvalidateRect(hCharts(rfi), NULL, FALSE)
        Next rfi
        Return 0

    Case WM_KILLFOCUS
        ' Redessiner pour effacer la bordure active
        InvalidateRect(hWnd, NULL, FALSE)
        Return 0

    End Select
    Return DefWindowProc(hWnd, uMsg, wParam, lParam)
End Function

Function WndProc(hWnd As HWND, uMsg As UINT, wParam As WPARAM, lParam As LPARAM) As LRESULT
    Select Case uMsg
        Case WM_CREATE
            hWndMain = hWnd
            LoadIniFile()
            ' ── Enregistrer la classe des fenêtres graphe enfant ─────────────
            Dim wcChart As WNDCLASSEX
            wcChart.cbSize        = SizeOf(WNDCLASSEX)
            wcChart.style         = CS_HREDRAW Or CS_VREDRAW
            wcChart.lpfnWndProc   = @ChartWndProc
            wcChart.hInstance     = GetModuleHandle(NULL)
            wcChart.hCursor       = LoadCursor(NULL, IDC_ARROW)
            wcChart.hbrBackground = NULL
            Dim chartClassName As String = "QChartWnd"
            wcChart.lpszClassName = StrPtr(chartClassName)
            RegisterClassEx(@wcChart)

            Dim hM As HMENU = CreateMenu()
            Dim hF As HMENU = CreatePopupMenu()
            AppendMenu(hF, MF_STRING, ID_MENU_OPEN,       "&Open CSV")
            AppendMenu(hF, MF_STRING, ID_MENU_DATASOURCE, "&Data Source...")
            AppendMenu(hM, MF_POPUP, Cast(UINT_PTR, hF), "&File")
            ' ── Menu View (layout multi-graphe) ──────────────────────────────
            Dim hV As HMENU = CreatePopupMenu()
            AppendMenu(hV, MF_STRING Or MF_CHECKED, ID_MENU_VIEW1, "1 graphe")
            AppendMenu(hV, MF_STRING, ID_MENU_VIEW2, "2 graphes")
            AppendMenu(hV, MF_STRING, ID_MENU_VIEW4, "4 graphes")
            AppendMenu(hM, MF_POPUP, Cast(UINT_PTR, hV), "&Vue")
            SetMenu(hWnd, hM)
            hToolbar = CreateWindowEx(0, TOOLBARCLASSNAME, NULL, _
                WS_CHILD Or WS_VISIBLE Or CCS_VERT Or CCS_NORESIZE Or TBSTYLE_FLAT Or TBSTYLE_WRAPABLE, _
                0, 0, toolbarW, 0, hWnd, NULL, GetModuleHandle(NULL), NULL)
            SendMessage(hToolbar, TB_BUTTONSTRUCTSIZE, SizeOf(TBBUTTON), 0)

            ' ── ImageList personnalisé chargé depuis images\ ─────────────────
            ' Ordre des indices (= iBitmap) :
            '  0=cursor  1=trendline  2=eraser  3=aiming
            '  4=circlegiven3points  5=fibofan  6=gann(fibofan)
            '  7=fiboret  8=grid  9=pentagram  10=para
            Dim hImgList As HANDLE
            hImgList = ImageList_Create(16, 16, ILC_COLOR32 Or ILC_MASK, 11, 0)

            Dim imgNames(10) As String
            imgNames(0)  = "images\cursor.bmp"
            imgNames(1)  = "images\trendline.bmp"
            imgNames(2)  = "images\eraser.bmp"
            imgNames(3)  = "images\aiming.bmp"
            imgNames(4)  = "images\circlegiven3points.bmp"
            imgNames(5)  = "images\fibofan.bmp"
            imgNames(6)  = "images\fibofan.bmp"        ' gann fan — même icône en attendant dédiée
            imgNames(7)  = "images\fiboret.bmp"
            imgNames(8)  = "images\grid.bmp"
            imgNames(9)  = "images\pentagram.bmp"
            imgNames(10) = "images\para.bmp"

            Dim iBmpIdx As Integer
            For iBmpIdx = 0 To 10
                Dim hBmp As HBITMAP = LoadImageA(NULL, StrPtr(imgNames(iBmpIdx)), _
                    IMAGE_BITMAP, 16, 16, LR_LOADFROMFILE Or LR_CREATEDIBSECTION)
                If hBmp <> NULL Then
                    ImageList_Add(hImgList, hBmp, NULL)
                    DeleteObject(hBmp)
                Else
                    ' Fallback : bitmap vide blanc si fichier manquant
                    Dim hFb As HBITMAP = CreateCompatibleBitmap(GetDC(NULL), 16, 16)
                    ImageList_Add(hImgList, hFb, NULL)
                    DeleteObject(hFb)
                End If
            Next iBmpIdx

            SendMessage(hToolbar, TB_SETIMAGELIST, 0, Cast(LPARAM, hImgList))

            Dim tbb(10) As TBBUTTON
            tbb(0).iBitmap  = 0  : tbb(0).idCommand  = ID_TOOL_SELECT    : tbb(0).fsState = TBSTATE_ENABLED Or TBSTATE_CHECKED : tbb(0).fsStyle = TBSTYLE_CHECKGROUP
            tbb(1).iBitmap  = 1  : tbb(1).idCommand  = ID_TOOL_LINE      : tbb(1).fsState = TBSTATE_ENABLED                   : tbb(1).fsStyle = TBSTYLE_CHECKGROUP
            tbb(2).iBitmap  = 2  : tbb(2).idCommand  = ID_TOOL_ERASER    : tbb(2).fsState = TBSTATE_ENABLED                   : tbb(2).fsStyle = TBSTYLE_CHECKGROUP
            tbb(3).iBitmap  = 3  : tbb(3).idCommand  = ID_TOOL_CROSSHAIR : tbb(3).fsState = TBSTATE_ENABLED                   : tbb(3).fsStyle = TBSTYLE_CHECKGROUP
            tbb(4).iBitmap  = 4  : tbb(4).idCommand  = ID_TOOL_CIRCLE    : tbb(4).fsState = TBSTATE_ENABLED                   : tbb(4).fsStyle = TBSTYLE_CHECKGROUP
            tbb(5).iBitmap  = 5  : tbb(5).idCommand  = ID_TOOL_FIBOFAN   : tbb(5).fsState = TBSTATE_ENABLED                   : tbb(5).fsStyle = TBSTYLE_CHECKGROUP
            tbb(6).iBitmap  = 6  : tbb(6).idCommand  = ID_TOOL_GANNFAN   : tbb(6).fsState = TBSTATE_ENABLED                   : tbb(6).fsStyle = TBSTYLE_CHECKGROUP
            tbb(7).iBitmap  = 7  : tbb(7).idCommand  = ID_TOOL_FIBORET   : tbb(7).fsState = TBSTATE_ENABLED                   : tbb(7).fsStyle = TBSTYLE_CHECKGROUP
            tbb(8).iBitmap  = 8  : tbb(8).idCommand  = ID_TOOL_GANNGRID  : tbb(8).fsState = TBSTATE_ENABLED                   : tbb(8).fsStyle = TBSTYLE_CHECKGROUP
            tbb(9).iBitmap  = 9  : tbb(9).idCommand  = ID_TOOL_PENTAGRAM : tbb(9).fsState = TBSTATE_ENABLED                   : tbb(9).fsStyle = TBSTYLE_CHECKGROUP
            tbb(10).iBitmap = 10 : tbb(10).idCommand = ID_TOOL_PARALINES : tbb(10).fsState = TBSTATE_ENABLED                  : tbb(10).fsStyle = TBSTYLE_CHECKGROUP
            SendMessage(hToolbar, TB_ADDBUTTONS, 11, Cast(LPARAM, @tbb(0)))
            SendMessage(hToolbar, TB_AUTOSIZE, 0, 0)
            hBtnIndicators = CreateWindowEx(0, "BUTTON", "Technicals", WS_CHILD Or WS_VISIBLE, 0, 0, toolbarW, 30, hWnd, Cast(HMENU, ID_BTN_INDICATORS), GetModuleHandle(NULL), NULL)
            hScroll = CreateWindowEx(0, "SCROLLBAR", "", WS_CHILD Or WS_VISIBLE Or SBS_HORZ, 0, 0, 0, 0, hWnd, NULL, GetModuleHandle(NULL), NULL)

            ' Barre de zoom horizontale en haut du graphique (à droite de la toolbar verticale)
            hZoomBar = CreateWindowEx(0, TOOLBARCLASSNAME, NULL, _
                WS_CHILD Or WS_VISIBLE Or CCS_NORESIZE Or CCS_NODIVIDER Or TBSTYLE_FLAT, _
                0, 0, 0, ZOOM_BAR_H, hWnd, NULL, GetModuleHandle(NULL), NULL)
            SendMessage(hZoomBar, TB_BUTTONSTRUCTSIZE, SizeOf(TBBUTTON), 0)
            ' Boutons texte : pas d'image (iBitmap=-2 = I_IMAGENONE), style texte
            SendMessage(hZoomBar, TB_SETBITMAPSIZE, 0, MAKELONG(0, 0))
            Dim zbb(1) As TBBUTTON
            zbb(0).iBitmap   = -2 ' I_IMAGENONE
            zbb(0).idCommand = ID_BTN_ZOOM_IN
            zbb(0).fsState   = TBSTATE_ENABLED
            zbb(0).fsStyle   = TBSTYLE_BUTTON
            zbb(0).iString   = Cast(INT_PTR, StrPtr(" + "))
            zbb(1).iBitmap   = -2
            zbb(1).idCommand = ID_BTN_ZOOM_OUT
            zbb(1).fsState   = TBSTATE_ENABLED
            zbb(1).fsStyle   = TBSTYLE_BUTTON
            zbb(1).iString   = Cast(INT_PTR, StrPtr(" - "))
            SendMessage(hZoomBar, TB_ADDBUTTONS, 2, Cast(LPARAM, @zbb(0)))
            SendMessage(hZoomBar, TB_AUTOSIZE, 0, 0)
            ReDim Lines(-1) : ReDim ActivePanels(-1)
            ' Enregistrer tous les indicateurs du dossier indicators/
            RegisterAllIndicators(@indRegistry)
            ' ── Créer le premier graphe (layout 1 fenêtre par défaut) ────────
            chartCount = 1
            SetChartCount(hWnd, 1)
            Return 0

        Case WM_COMMAND
            Dim id As Integer = Loword(wParam)
            If id = ID_MENU_OPEN Then
                Dim f As String = File_GetName(hWnd) : If f <> "" Then LoadCSV(f, hWnd)
            ElseIf id = ID_MENU_DATASOURCE Then
                OpenDataSourceWindow(hWnd)
            ElseIf id = ID_DS_GETCHART Then
                TiingoGetChart(hWnd)
            ElseIf id = ID_MENU_VIEW1 Or id = ID_MENU_VIEW2 Or id = ID_MENU_VIEW4 Then
                ' Mettre à jour les checkmarks du menu Vue
                Dim hMenuBar As HMENU = GetMenu(hWnd)
                Dim hViewMenu As HMENU = GetSubMenu(hMenuBar, 1)   ' index 1 = Vue
                CheckMenuItem(hViewMenu, ID_MENU_VIEW1, IIf(id = ID_MENU_VIEW1, MF_CHECKED, MF_UNCHECKED))
                CheckMenuItem(hViewMenu, ID_MENU_VIEW2, IIf(id = ID_MENU_VIEW2, MF_CHECKED, MF_UNCHECKED))
                CheckMenuItem(hViewMenu, ID_MENU_VIEW4, IIf(id = ID_MENU_VIEW4, MF_CHECKED, MF_UNCHECKED))
                Dim newN As Integer = 1
                If id = ID_MENU_VIEW2 Then newN = 2
                If id = ID_MENU_VIEW4 Then newN = 4
                SetChartCount(hWnd, newN)
            ElseIf id >= ID_TOOL_SELECT And id <= ID_TOOL_PARALINES Then
                currentTool = id : isDrawing = 0
                ' Propager l'outil à tous les graphes
                Dim ci2 As Integer
                For ci2 = 0 To chartCount - 1
                    Dim pCDi As ChartWinData Ptr = GetChartData(hCharts(ci2))
                    If pCDi <> NULL Then
                        pCDi->currentTool    = id
                        pCDi->isDrawing      = 0
                        pCDi->circleClickNb  = 0
                        pCDi->fiboFanClickNb = 0
                        pCDi->gannFanClickNb = 0
                        pCDi->fiboRetClickNb = 0
                        pCDi->gannGridClickNb = 0
                        pCDi->pentaClickNb   = 0
                        pCDi->paraClickNb    = 0
                        If id <> ID_TOOL_CROSSHAIR Then
                            pCDi->crosshairX = -1 : pCDi->crosshairY = -1
                        End If
                    End If
                Next
            ElseIf id = ID_BTN_INDICATORS Then
                Dim tgtChart As Integer = activeChartIdx
                If hCharts(tgtChart) = 0 Then tgtChart = 0
                OpenTechnicalsForChart(hWnd, tgtChart)

            ElseIf id = ID_POPUP_PARAMS Then
                ' Ouvrir le dialogue de modification de période pour l'overlay cliqué
                If rightClickedOverlayIdx >= 0 And rightClickedOverlayIdx < ActiveCount Then
                    Dim wcP As WNDCLASS
                    wcP.lpfnWndProc   = @ParamsDlgProc
                    wcP.hInstance     = GetModuleHandle(NULL)
                    wcP.hCursor       = LoadCursor(NULL, IDC_ARROW)
                    wcP.hbrBackground = GetStockObject(WHITE_BRUSH)
                    wcP.lpszClassName = StrPtr("ParamsWin")
                    RegisterClass(@wcP)
                    Dim def3 As IndicatorDef = indRegistry.defs(ActivePanels(rightClickedOverlayIdx).defIndex)
                    Dim dlgTitle As String = "Parametres — " & def3.name
                    Dim zDlgTitle As ZString * 64 : zDlgTitle = dlgTitle
                    CreateWindowEx(0, "ParamsWin", @zDlgTitle, _
                        WS_OVERLAPPED Or WS_CAPTION Or WS_SYSMENU Or WS_VISIBLE, _
                        CW_USEDEFAULT, CW_USEDEFAULT, 215, 110, _
                        hWnd, NULL, GetModuleHandle(NULL), NULL)
                End If

            ElseIf id = ID_BTN_ZOOM_IN Or id = ID_BTN_ZOOM_OUT Then
                Dim pCDZ As ChartWinData Ptr = GetChartData(hCharts(activeChartIdx))
                If pCDZ = NULL Or pCDZ->Chart.IsLoaded = 0 Then Return 0
                Dim totalHZ As Integer = UBound(pCDZ->Chart.History) + 1
                Dim centerBarZ As Integer = pCDZ->Chart.ViewStart + pCDZ->Chart.ViewCount \ 2
                Dim newCountZ As Integer = pCDZ->Chart.ViewCount
                If id = ID_BTN_ZOOM_IN Then newCountZ -= ZOOM_STEP Else newCountZ += ZOOM_STEP
                If newCountZ < ZOOM_MIN_BARS Then newCountZ = ZOOM_MIN_BARS
                If newCountZ > ZOOM_MAX_BARS Then newCountZ = ZOOM_MAX_BARS
                If newCountZ > totalHZ Then newCountZ = totalHZ
                pCDZ->Chart.ViewCount = newCountZ
                Dim newStartZ As Integer = centerBarZ - newCountZ \ 2
                If newStartZ < 0 Then newStartZ = 0
                Dim maxStartZ As Integer = totalHZ - newCountZ
                If maxStartZ < 0 Then maxStartZ = 0
                If newStartZ > maxStartZ Then newStartZ = maxStartZ
                pCDZ->Chart.ViewStart = newStartZ
                SetScrollRange(hScroll, SB_CTL, 0, maxStartZ, TRUE)
                SetScrollPos(hScroll, SB_CTL, newStartZ, TRUE)
                InvalidateRect(hCharts(activeChartIdx), NULL, FALSE)
            End If

        Case WM_MOUSEMOVE
            If currentTool = ID_TOOL_CROSSHAIR And QChart.IsLoaded Then
                crosshairX = Loword(lParam)
                crosshairY = Hiword(lParam)
                SetCursor(LoadCursor(NULL, IDC_CROSS))
                ForceRedraw(hWnd)
            ElseIf currentTool = ID_TOOL_LINE And QChart.IsLoaded Then
                SnapToCandle(Loword(lParam), Hiword(lParam))
                ForceRedraw(hWnd)
            ElseIf currentTool = ID_TOOL_FIBOFAN And fiboFanClickNb = 1 And QChart.IsLoaded Then
                ForceRedraw(hWnd)
            ElseIf currentTool = ID_TOOL_GANNFAN And gannFanClickNb = 1 And QChart.IsLoaded Then
                ForceRedraw(hWnd)
            ElseIf currentTool = ID_TOOL_FIBORET And fiboRetClickNb = 1 And QChart.IsLoaded Then
                ForceRedraw(hWnd)
            ElseIf currentTool = ID_TOOL_GANNGRID And gannGridClickNb = 1 And QChart.IsLoaded Then
                ForceRedraw(hWnd)
            ElseIf currentTool = ID_TOOL_PENTAGRAM And pentaClickNb = 1 And QChart.IsLoaded Then
                ForceRedraw(hWnd)
            ElseIf currentTool = ID_TOOL_PARALINES And paraClickNb >= 1 And QChart.IsLoaded Then
                ForceRedraw(hWnd)
            ElseIf isDrawing = 1 Then
                ForceRedraw(hWnd)
            End If

        Case WM_LBUTTONDOWN
            If QChart.IsLoaded = 0 Then Return 0
            Dim mx As Integer = Loword(lParam)
            Dim my As Integer = Hiword(lParam)
            If mx < toolbarW Then Return 0

            ' Détection clic ✕ sur panneaux actifs
            Dim panelAreaIdx As Long = 0
            Dim panelCount2 As Long = 0
            For i As Integer = 0 To ActiveCount - 1
                If indRegistry.defs(ActivePanels(i).defIndex).isPanel = 1 Then panelCount2 += 1
            Next
            Dim panelHitIdx As Long = 0
            Dim globalOverlayHitIdx As Long = 0
            Dim htOriX2 As Long = 65 + toolbarW
            Dim htLenX2 As Single = winW - 120 - toolbarW
            Dim htMainH2 As Long = (winH - SCROLL_H) - panelCount2 * (RSI_PANEL_H + RSI_PANEL_GAP) - 40 - ZOOM_BAR_H
            For i As Integer = 0 To ActiveCount - 1
                Dim defIdx As Long = ActivePanels(i).defIndex
                Dim def As IndicatorDef = indRegistry.defs(defIdx)
                If def.isPanel = 0 Then
                    Dim maLbl2 As String = def.labelPrefix & "(" & ActivePanels(i).period & ")"
                    Dim htLblX2 As Long = htOriX2 + 4
                    Dim htLblY2 As Long = ZOOM_BAR_H + 14 + globalOverlayHitIdx * (RSI_CLOSE_BTN + 4)
                    Dim htZoneW2 As Long = Len(maLbl2) * 7 + 3 + RSI_CLOSE_BTN + 8
                    Dim htZoneH2 As Long = RSI_CLOSE_BTN + 8
                    If mx >= htLblX2 And mx <= htLblX2 + htZoneW2 And _
                       my >= htLblY2 - 4 And my <= htLblY2 - 4 + htZoneH2 Then
                        For j As Integer = i To ActiveCount - 2
                            ActivePanels(j) = ActivePanels(j + 1)
                        Next
                        ActiveCount -= 1
                        If ActiveCount = 0 Then ReDim ActivePanels(-1) Else ReDim Preserve ActivePanels(ActiveCount - 1)
                        ForceRedraw(hWnd) : Return 0
                    End If
                    globalOverlayHitIdx += 1
                Else
                    Dim htRTop2 As Long = htMainH2 + RSI_PANEL_MARGIN + panelHitIdx * (RSI_PANEL_H + RSI_PANEL_GAP)
                    Dim htBxRSI2 As Single = htOriX2 + htLenX2 - RSI_CLOSE_BTN - 2
                    Dim htByRSI2 As Single = htRTop2 + 2
                    If mx >= htBxRSI2 - 6 And mx <= htBxRSI2 + RSI_CLOSE_BTN + 6 And _
                       my >= htByRSI2 - 6 And my <= htByRSI2 + RSI_CLOSE_BTN + 6 Then
                        For j As Integer = i To ActiveCount - 2
                            ActivePanels(j) = ActivePanels(j + 1)
                        Next
                        ActiveCount -= 1
                        If ActiveCount = 0 Then ReDim ActivePanels(-1) Else ReDim Preserve ActivePanels(ActiveCount - 1)
                        ForceRedraw(hWnd) : Return 0
                    End If
                    panelHitIdx += 1
                End If
            Next

            If currentTool = ID_TOOL_LINE Then
                ' Détecter le canvas sous le curseur
                Dim clickCanvas As Integer = HitTestCanvas(mx, my)
                If clickCanvas = -1 Then Return 0   ' hors de tout canvas, ignorer

                If isDrawing = 0 Then
                    ' Premier point : adapter le snap selon le canvas
                    If clickCanvas = 0 Then
                        SnapToCandle(mx, my)
                        tmpBar = g_snapBar
                        tmpPrice = g_snapPrice
                    Else
                        tmpBar   = QChart.ViewStart + CInt((mx - g_oriX) / g_stepX)
                        tmpPrice = ScreenYToValue(my, clickCanvas)
                    End If
                    tmpCanvasType = clickCanvas
                    isDrawing = 1
                Else
                    ' Deuxième point : même canvas que le premier uniquement
                    Dim n As Integer = UBound(Lines) + 1
                    ReDim Preserve Lines(n)
                    Lines(n).bar1 = tmpBar : Lines(n).price1 = tmpPrice
                    Lines(n).canvasType = tmpCanvasType
                    If tmpCanvasType = 0 Then
                        SnapToCandle(mx, my)
                        Lines(n).bar2   = g_snapBar
                        Lines(n).price2 = g_snapPrice
                    Else
                        Lines(n).bar2   = QChart.ViewStart + CInt((mx - g_oriX) / g_stepX)
                        Lines(n).price2 = ScreenYToValue(my, tmpCanvasType)
                    End If
                    isDrawing = 0
                End If
                ForceRedraw(hWnd)

            ElseIf currentTool = ID_TOOL_CIRCLE And QChart.IsLoaded Then
                ' Outil cercle 3 points : accumuler les clics en coordonnées bar/price
                circleClickNb += 1
                circleX(circleClickNb) = CSng(mx)
                circleY(circleClickNb) = CSng(my)
                ' Stocker aussi en bar/price pour que le cercle suive le scroll
                SnapToCandle(mx, my)
                circleBar(circleClickNb)   = g_snapBar
                circlePrice(circleClickNb) = g_snapPrice
                If circleClickNb = 3 Then
                    ' Sauvegarder les 3 points en bar/price
                    Dim nc As Integer = UBound(Circles) + 1
                    ReDim Preserve Circles(nc)
                    Circles(nc).bar1   = circleBar(1)  : Circles(nc).price1 = circlePrice(1)
                    Circles(nc).bar2   = circleBar(2)  : Circles(nc).price2 = circlePrice(2)
                    Circles(nc).bar3   = circleBar(3)  : Circles(nc).price3 = circlePrice(3)
                    circleClickNb = 0
                End If
                ForceRedraw(hWnd)

            ElseIf currentTool = ID_TOOL_FIBOFAN And QChart.IsLoaded Then
                ' Fibonacci Fan : 2 clics — pivot (P1) puis fin (P2)
                SnapToCandle(mx, my)
                fiboFanClickNb += 1
                If fiboFanClickNb = 1 Then
                    fiboFanBar1   = g_snapBar
                    fiboFanPrice1 = g_snapPrice
                Else
                    ' Deuxième clic : sauvegarder le FiboFan
                    Dim nff As Integer = UBound(FiboFans) + 1
                    ReDim Preserve FiboFans(nff)
                    FiboFans(nff).bar1   = fiboFanBar1
                    FiboFans(nff).price1 = fiboFanPrice1
                    FiboFans(nff).bar2   = g_snapBar
                    FiboFans(nff).price2 = g_snapPrice
                    fiboFanClickNb = 0
                End If
                ForceRedraw(hWnd)

            ElseIf currentTool = ID_TOOL_GANNFAN And QChart.IsLoaded Then
                SnapToCandle(mx, my)
                gannFanClickNb += 1
                If gannFanClickNb = 1 Then
                    gannFanBar1   = g_snapBar
                    gannFanPrice1 = g_snapPrice
                Else
                    Dim ngf As Integer = UBound(GannFans) + 1
                    ReDim Preserve GannFans(ngf)
                    GannFans(ngf).bar1   = gannFanBar1
                    GannFans(ngf).price1 = gannFanPrice1
                    GannFans(ngf).bar2   = g_snapBar
                    GannFans(ngf).price2 = g_snapPrice
                    gannFanClickNb = 0
                End If
                ForceRedraw(hWnd)

            ElseIf currentTool = ID_TOOL_FIBORET And QChart.IsLoaded Then
                SnapToCandle(mx, my)
                fiboRetClickNb += 1
                If fiboRetClickNb = 1 Then
                    fiboRetBar1   = g_snapBar
                    fiboRetPrice1 = g_snapPrice
                Else
                    Dim nfr As Integer = UBound(FiboRets) + 1
                    ReDim Preserve FiboRets(nfr)
                    FiboRets(nfr).bar1   = fiboRetBar1
                    FiboRets(nfr).price1 = fiboRetPrice1
                    FiboRets(nfr).bar2   = g_snapBar
                    FiboRets(nfr).price2 = g_snapPrice
                    fiboRetClickNb = 0
                End If
                ForceRedraw(hWnd)

            ElseIf currentTool = ID_TOOL_GANNGRID And QChart.IsLoaded Then
                SnapToCandle(mx, my)
                gannGridClickNb += 1
                If gannGridClickNb = 1 Then
                    gannGridBar1   = g_snapBar
                    gannGridPrice1 = g_snapPrice
                Else
                    Dim ngg As Integer = UBound(GannGrids) + 1
                    ReDim Preserve GannGrids(ngg)
                    GannGrids(ngg).bar1   = gannGridBar1
                    GannGrids(ngg).price1 = gannGridPrice1
                    GannGrids(ngg).bar2   = g_snapBar
                    GannGrids(ngg).price2 = g_snapPrice
                    gannGridClickNb = 0
                End If
                ForceRedraw(hWnd)

            ElseIf currentTool = ID_TOOL_PENTAGRAM And QChart.IsLoaded Then
                SnapToCandle(mx, my)
                pentaClickNb += 1
                If pentaClickNb = 1 Then
                    pentaBar1   = g_snapBar
                    pentaPrice1 = g_snapPrice
                Else
                    Dim npt As Integer = UBound(Pentagrams) + 1
                    ReDim Preserve Pentagrams(npt)
                    Pentagrams(npt).bar1   = pentaBar1
                    Pentagrams(npt).price1 = pentaPrice1
                    Pentagrams(npt).bar2   = g_snapBar
                    Pentagrams(npt).price2 = g_snapPrice
                    pentaClickNb = 0
                End If
                ForceRedraw(hWnd)

            ElseIf currentTool = ID_TOOL_PARALINES And QChart.IsLoaded Then
                SnapToCandle(mx, my)
                paraClickNb += 1
                If paraClickNb = 1 Then
                    paraBar1   = g_snapBar
                    paraPrice1 = g_snapPrice
                ElseIf paraClickNb = 2 Then
                    paraBar2   = g_snapBar
                    paraPrice2 = g_snapPrice
                Else
                    ' 3ème clic : sauvegarder
                    Dim npl As Integer = UBound(ParaLinesArr) + 1
                    ReDim Preserve ParaLinesArr(npl)
                    ParaLinesArr(npl).bar1   = paraBar1   : ParaLinesArr(npl).price1 = paraPrice1
                    ParaLinesArr(npl).bar2   = paraBar2   : ParaLinesArr(npl).price2 = paraPrice2
                    ParaLinesArr(npl).bar3   = g_snapBar  : ParaLinesArr(npl).price3 = g_snapPrice
                    paraClickNb = 0
                End If
                ForceRedraw(hWnd)

            ElseIf currentTool = ID_TOOL_ERASER Then
                Dim found As Integer = -1
                For i As Integer = 0 To UBound(Lines)
                    Dim x1 As Single = g_oriX + (Lines(i).bar1 - QChart.ViewStart) * g_stepX + (g_stepX/2)
                    Dim y1 As Single = ValueToScreenY(Lines(i).price1, Lines(i).canvasType)
                    Dim x2 As Single = g_oriX + (Lines(i).bar2 - QChart.ViewStart) * g_stepX + (g_stepX/2)
                    Dim y2 As Single = ValueToScreenY(Lines(i).price2, Lines(i).canvasType)
                    If DistToSegment(CSng(mx), CSng(my), x1, y1, x2, y2) < 7.0 Then
                        found = i : Exit For
                    End If
                Next
                If found > -1 Then
                    For j As Integer = found To UBound(Lines) - 1 : Lines(j) = Lines(j+1) : Next
                    If UBound(Lines) = 0 Then ReDim Lines(-1) Else ReDim Preserve Lines(UBound(Lines) - 1)
                    ForceRedraw(hWnd)
                End If
                ' Supprimer aussi un cercle proche
                If UBound(Circles) >= 0 Then
                    Dim foundC As Integer = -1
                    For i As Integer = 0 To UBound(Circles)
                        Dim epx1 As Single = g_oriX + (Circles(i).bar1 - QChart.ViewStart) * g_stepX + g_stepX * 0.5
                        Dim epy1 As Single = ValueToScreenY(Circles(i).price1, 0)
                        Dim epx2 As Single = g_oriX + (Circles(i).bar2 - QChart.ViewStart) * g_stepX + g_stepX * 0.5
                        Dim epy2 As Single = ValueToScreenY(Circles(i).price2, 0)
                        Dim epx3 As Single = g_oriX + (Circles(i).bar3 - QChart.ViewStart) * g_stepX + g_stepX * 0.5
                        Dim epy3 As Single = ValueToScreenY(Circles(i).price3, 0)
                        Dim eyda As Double = epy2 - epy1 : Dim exda As Double = epx2 - epx1
                        Dim eydb As Double = epy3 - epy2 : Dim exdb As Double = epx3 - epx2
                        If Abs(exda) > 0.001 And Abs(exdb) > 0.001 Then
                            Dim easlp As Double = eyda/exda : Dim ebslp As Double = eydb/exdb
                            If Abs(ebslp-easlp) > 0.001 Then
                                Dim eccx As Single = CSng((easlp*ebslp*(epy1-epy3)+ebslp*(epx1+epx2)-easlp*(epx2+epx3))/(2.0*(ebslp-easlp)))
                                Dim eccy As Single = CSng(-1.0*(eccx-(epx1+epx2)/2.0)/easlp+(epy1+epy2)/2.0)
                                Dim edx As Single = mx - eccx : Dim edy As Single = my - eccy
                                Dim eRad As Single = CSng(Sqr((epx1-eccx)^2+(epy1-eccy)^2))
                                If Abs(Sqr(edx*edx+edy*edy) - eRad) < 10.0 Then foundC = i : Exit For
                            End If
                        End If
                    Next
                    If foundC > -1 Then
                        For j As Integer = foundC To UBound(Circles) - 1 : Circles(j) = Circles(j+1) : Next
                        If UBound(Circles) = 0 Then ReDim Circles(-1) Else ReDim Preserve Circles(UBound(Circles) - 1)
                        ForceRedraw(hWnd)
                    End If
                End If
                ' Supprimer aussi un FiboFan proche (clic près de la ligne de base)
                If UBound(FiboFans) >= 0 Then
                    Dim foundF As Integer = -1
                    For i As Integer = 0 To UBound(FiboFans)
                        Dim fex1 As Single = g_oriX + (FiboFans(i).bar1 - QChart.ViewStart) * g_stepX + g_stepX * 0.5
                        Dim fey1 As Single = ValueToScreenY(FiboFans(i).price1, 0)
                        Dim fex2 As Single = g_oriX + (FiboFans(i).bar2 - QChart.ViewStart) * g_stepX + g_stepX * 0.5
                        Dim fey2 As Single = ValueToScreenY(FiboFans(i).price2, 0)
                        If DistToSegment(CSng(mx), CSng(my), fex1, fey1, fex2, fey2) < 7.0 Then
                            foundF = i : Exit For
                        End If
                    Next
                    If foundF > -1 Then
                        For j As Integer = foundF To UBound(FiboFans) - 1 : FiboFans(j) = FiboFans(j+1) : Next
                        If UBound(FiboFans) = 0 Then ReDim FiboFans(-1) Else ReDim Preserve FiboFans(UBound(FiboFans) - 1)
                        ForceRedraw(hWnd)
                    End If
                End If
                ' Supprimer aussi un GannFan proche
                If UBound(GannFans) >= 0 Then
                    Dim foundGF As Integer = -1
                    For i As Integer = 0 To UBound(GannFans)
                        Dim gex1 As Single = g_oriX + (GannFans(i).bar1 - QChart.ViewStart) * g_stepX + g_stepX * 0.5
                        Dim gey1 As Single = ValueToScreenY(GannFans(i).price1, 0)
                        Dim gex2 As Single = g_oriX + (GannFans(i).bar2 - QChart.ViewStart) * g_stepX + g_stepX * 0.5
                        Dim gey2 As Single = ValueToScreenY(GannFans(i).price2, 0)
                        If DistToSegment(CSng(mx), CSng(my), gex1, gey1, gex2, gey2) < 7.0 Then
                            foundGF = i : Exit For
                        End If
                    Next
                    If foundGF > -1 Then
                        For j As Integer = foundGF To UBound(GannFans) - 1 : GannFans(j) = GannFans(j+1) : Next
                        If UBound(GannFans) = 0 Then ReDim GannFans(-1) Else ReDim Preserve GannFans(UBound(GannFans) - 1)
                        ForceRedraw(hWnd)
                    End If
                End If
                ' Supprimer aussi un FiboRet proche (clic près de la ligne diagonale)
                If UBound(FiboRets) >= 0 Then
                    Dim foundFR As Integer = -1
                    For i As Integer = 0 To UBound(FiboRets)
                        Dim frex1 As Single = g_oriX + (FiboRets(i).bar1 - QChart.ViewStart) * g_stepX + g_stepX * 0.5
                        Dim frey1 As Single = ValueToScreenY(FiboRets(i).price1, 0)
                        Dim frex2 As Single = g_oriX + (FiboRets(i).bar2 - QChart.ViewStart) * g_stepX + g_stepX * 0.5
                        Dim frey2 As Single = ValueToScreenY(FiboRets(i).price2, 0)
                        If DistToSegment(CSng(mx), CSng(my), frex1, frey1, frex2, frey2) < 7.0 Then
                            foundFR = i : Exit For
                        End If
                    Next
                    If foundFR > -1 Then
                        For j As Integer = foundFR To UBound(FiboRets) - 1 : FiboRets(j) = FiboRets(j+1) : Next
                        If UBound(FiboRets) = 0 Then ReDim FiboRets(-1) Else ReDim Preserve FiboRets(UBound(FiboRets) - 1)
                        ForceRedraw(hWnd)
                    End If
                End If
                ' Supprimer aussi un GannGrid proche (clic près de la cellule de base)
                If UBound(GannGrids) >= 0 Then
                    Dim foundGG As Integer = -1
                    For i As Integer = 0 To UBound(GannGrids)
                        Dim ggex1 As Single = g_oriX + (GannGrids(i).bar1 - QChart.ViewStart) * g_stepX + g_stepX * 0.5
                        Dim ggey1 As Single = ValueToScreenY(GannGrids(i).price1, 0)
                        Dim ggex2 As Single = g_oriX + (GannGrids(i).bar2 - QChart.ViewStart) * g_stepX + g_stepX * 0.5
                        Dim ggey2 As Single = ValueToScreenY(GannGrids(i).price2, 0)
                        If DistToSegment(CSng(mx), CSng(my), ggex1, ggey1, ggex2, ggey2) < 10.0 Then
                            foundGG = i : Exit For
                        End If
                    Next
                    If foundGG > -1 Then
                        For j As Integer = foundGG To UBound(GannGrids) - 1 : GannGrids(j) = GannGrids(j+1) : Next
                        If UBound(GannGrids) = 0 Then ReDim GannGrids(-1) Else ReDim Preserve GannGrids(UBound(GannGrids) - 1)
                        ForceRedraw(hWnd)
                    End If
                End If
                ' Supprimer aussi un Pentagramme proche (clic dans le cercle)
                If UBound(Pentagrams) >= 0 Then
                    Dim foundPT As Integer = -1
                    For i As Integer = 0 To UBound(Pentagrams)
                        Dim ptex1 As Single = g_oriX + (Pentagrams(i).bar1 - QChart.ViewStart) * g_stepX + g_stepX * 0.5
                        Dim ptey1 As Single = ValueToScreenY(Pentagrams(i).price1, 0)
                        Dim ptex2 As Single = g_oriX + (Pentagrams(i).bar2 - QChart.ViewStart) * g_stepX + g_stepX * 0.5
                        Dim ptey2 As Single = ValueToScreenY(Pentagrams(i).price2, 0)
                        Dim pteDx As Single = ptex2 - ptex1 : Dim pteDy As Single = ptey2 - ptey1
                        Dim pteRad As Single = CSng(Sqr(pteDx*pteDx + pteDy*pteDy))
                        Dim pteDist As Single = Abs(CSng(Sqr((mx-ptex1)^2 + (my-ptey1)^2)) - pteRad)
                        If pteDist < 10.0 Then foundPT = i : Exit For
                    Next
                    If foundPT > -1 Then
                        For j As Integer = foundPT To UBound(Pentagrams) - 1 : Pentagrams(j) = Pentagrams(j+1) : Next
                        If UBound(Pentagrams) = 0 Then ReDim Pentagrams(-1) Else ReDim Preserve Pentagrams(UBound(Pentagrams) - 1)
                        ForceRedraw(hWnd)
                    End If
                End If
                ' Supprimer aussi une Parallel Lines proche
                If UBound(ParaLinesArr) >= 0 Then
                    Dim foundPL As Integer = -1
                    For i As Integer = 0 To UBound(ParaLinesArr)
                        Dim plex1 As Single = g_oriX + (ParaLinesArr(i).bar1 - QChart.ViewStart) * g_stepX + g_stepX * 0.5
                        Dim pley1 As Single = ValueToScreenY(ParaLinesArr(i).price1, 0)
                        Dim plex2 As Single = g_oriX + (ParaLinesArr(i).bar2 - QChart.ViewStart) * g_stepX + g_stepX * 0.5
                        Dim pley2 As Single = ValueToScreenY(ParaLinesArr(i).price2, 0)
                        Dim plex3 As Single = g_oriX + (ParaLinesArr(i).bar3 - QChart.ViewStart) * g_stepX + g_stepX * 0.5
                        Dim pley3 As Single = ValueToScreenY(ParaLinesArr(i).price3, 0)
                        Dim pledx As Single = plex2 - plex1 : Dim pledy As Single = pley2 - pley1
                        If DistToSegment(CSng(mx), CSng(my), plex1, pley1, plex2, pley2) < 7.0 Then foundPL = i : Exit For
                        If DistToSegment(CSng(mx), CSng(my), plex3, pley3, plex3+pledx, pley3+pledy) < 7.0 Then foundPL = i : Exit For
                    Next
                    If foundPL > -1 Then
                        For j As Integer = foundPL To UBound(ParaLinesArr) - 1 : ParaLinesArr(j) = ParaLinesArr(j+1) : Next
                        If UBound(ParaLinesArr) = 0 Then ReDim ParaLinesArr(-1) Else ReDim Preserve ParaLinesArr(UBound(ParaLinesArr) - 1)
                        ForceRedraw(hWnd)
                    End If
                End If
            End If

        Case WM_RBUTTONDOWN
            Dim rmx As Integer = Loword(lParam)
            Dim rmy As Integer = Hiword(lParam)

            ' Annuler un tracé en cours
            If isDrawing = 1 Then
                isDrawing = 0 : ForceRedraw(hWnd) : Return 0
            End If
            If circleClickNb > 0 Then
                circleClickNb = 0 : ForceRedraw(hWnd) : Return 0
            End If
            If fiboFanClickNb > 0 Then
                fiboFanClickNb = 0 : ForceRedraw(hWnd) : Return 0
            End If
            If gannFanClickNb > 0 Then
                gannFanClickNb = 0 : ForceRedraw(hWnd) : Return 0
            End If
            If fiboRetClickNb > 0 Then
                fiboRetClickNb = 0 : ForceRedraw(hWnd) : Return 0
            End If
            If gannGridClickNb > 0 Then
                gannGridClickNb = 0 : ForceRedraw(hWnd) : Return 0
            End If
            If pentaClickNb > 0 Then
                pentaClickNb = 0 : ForceRedraw(hWnd) : Return 0
            End If
            If paraClickNb > 0 Then
                paraClickNb = 0 : ForceRedraw(hWnd) : Return 0
            End If

            ' Détecter si le clic droit est sur un label d'overlay OU dans un panel séparé
            Dim hitIndicator As Integer = HitTestOverlayLabel(rmx, rmy)
            If hitIndicator < 0 Then
                hitIndicator = HitTestPanelArea(rmx, rmy)
            End If

            If hitIndicator >= 0 Then
                rightClickedOverlayIdx = hitIndicator

                ' Construire le popup menu
                Dim hPopup As HMENU = CreatePopupMenu()
                Dim def2 As IndicatorDef = indRegistry.defs(ActivePanels(hitIndicator).defIndex)
                Dim menuLabel As String = "Parametres " & def2.labelPrefix & _
                    "(" & ActivePanels(hitIndicator).period & ")..."
                Dim zMenuLabel As ZString * 64 : zMenuLabel = menuLabel
                AppendMenu(hPopup, MF_STRING, ID_POPUP_PARAMS, @zMenuLabel)

                ' Convertir coords client → écran pour TrackPopupMenu
                Dim pt As POINT : pt.x = rmx : pt.y = rmy
                ClientToScreen(hWnd, @pt)
                TrackPopupMenu(hPopup, TPM_LEFTALIGN Or TPM_RIGHTBUTTON, _
                    pt.x, pt.y, 0, hWnd, NULL)
                DestroyMenu(hPopup)
                Return 0
            End If

        Case WM_MOUSEWHEEL
            ' Rediriger vers le graphe actif (le WM_MOUSEWHEEL peut arriver au parent)
            If hCharts(activeChartIdx) <> 0 Then
                SendMessage(hCharts(activeChartIdx), WM_MOUSEWHEEL, wParam, lParam)
            End If
            Return 0

        Case WM_HSCROLL
            Dim pCDSc As ChartWinData Ptr = GetChartData(hCharts(activeChartIdx))
            If pCDSc = NULL Or pCDSc->Chart.IsLoaded = 0 Then Exit Select
            Dim si As SCROLLINFO : si.cbSize = SizeOf(SCROLLINFO) : si.fMask = SIF_ALL : GetScrollInfo(hScroll, SB_CTL, @si)
            Dim cp As Integer = si.nPos
            Select Case Loword(wParam)
                Case SB_THUMBTRACK, SB_THUMBPOSITION : cp = si.nTrackPos
                Case SB_LINELEFT : cp -= 1
                Case SB_LINERIGHT : cp += 1
            End Select
            Dim ms As Integer = (UBound(pCDSc->Chart.History) + 1) - pCDSc->Chart.ViewCount
            If cp < 0 Then cp = 0 : If cp > ms Then cp = ms
            pCDSc->Chart.ViewStart = cp : SetScrollPos(hScroll, SB_CTL, cp, TRUE)
            InvalidateRect(hCharts(activeChartIdx), NULL, FALSE)

        Case WM_TIMER
            If wParam = ID_DS_TIMER And dsTimerActive = 1 Then
                TiingoCheckDone(hWnd)
            End If

        Case WM_SIZE
            winW = Loword(lParam) : winH = Hiword(lParam)
            Dim tbSize As SIZE
            SendMessage(hToolbar, TB_GETMAXSIZE, 0, Cast(LPARAM, @tbSize))
            If tbSize.cx > 0 Then toolbarW = tbSize.cx
            MoveWindow(hToolbar, 0, 0, toolbarW, winH - 80, TRUE)
            MoveWindow(hBtnIndicators, 0, winH - 75, toolbarW, 30, TRUE)
            MoveWindow(hZoomBar, toolbarW, 0, winW - toolbarW, ZOOM_BAR_H, TRUE)
            MoveWindow(hScroll, toolbarW + 65, winH - SCROLL_H, winW - 130 - toolbarW, 20, TRUE)
            ArrangeChartWindows(hWnd)

        Case WM_ERASEBKGND
            Return 1

        Case WM_PAINT
            ' Les graphes enfants gèrent leur propre WM_PAINT.
            ' On peint uniquement le fond de la zone de la toolbar.
            Dim ps As PAINTSTRUCT
            Dim hDCp As HDC = BeginPaint(hWnd, @ps)
            EndPaint(hWnd, @ps)
            Return 0

        Case WM_DESTROY : PostQuitMessage(0) : Return 0
    End Select
    Return DefWindowProc(hWnd, uMsg, wParam, lParam)
End Function

' ── Data Source (Tiingo) ──────────────────────────────────────────────────────

Sub OpenDataSourceWindow(hWndParent As HWND)
    If hDSWin <> 0 Then
        ShowWindow(hDSWin, SW_RESTORE)
        SetForegroundWindow(hDSWin)
        Return
    End If

    ' Créer une fenêtre simple non-modale
    Dim wcDS As WNDCLASS
    wcDS.lpfnWndProc   = @DataSourceProc
    wcDS.hInstance     = GetModuleHandle(NULL)
    wcDS.hCursor       = LoadCursor(NULL, IDC_ARROW)
    wcDS.hbrBackground = Cast(HBRUSH, COLOR_BTNFACE + 1)
    wcDS.lpszClassName = StrPtr("DSWin")
    RegisterClass(@wcDS)
    hDSWin = CreateWindowEx(WS_EX_TOOLWINDOW, "DSWin", "Data Source", _
        WS_OVERLAPPED Or WS_CAPTION Or WS_SYSMENU Or WS_VISIBLE, _
        200, 150, 420, 290, hWndParent, NULL, GetModuleHandle(NULL), NULL)
End Sub

Function DataSourceProc(hWnd As HWND, uMsg As UINT, wParam As WPARAM, lParam As LPARAM) As LRESULT
    Select Case uMsg
        Case WM_CREATE
            ' Source combobox
            CreateWindowEx(0,"STATIC","Source:",WS_CHILD Or WS_VISIBLE,8,10,55,18,hWnd,NULL,GetModuleHandle(NULL),NULL)
            hDSSource = CreateWindowEx(0,"COMBOBOX","",WS_CHILD Or WS_VISIBLE Or CBS_DROPDOWNLIST Or WS_VSCROLL,68,8,300,200,hWnd,Cast(HMENU,ID_DS_SOURCE),GetModuleHandle(NULL),NULL)
            SendMessage(hDSSource, CB_ADDSTRING, 0, Cast(LPARAM, StrPtr("Tiingo Cryptocurrencies")))
            SendMessage(hDSSource, CB_ADDSTRING, 0, Cast(LPARAM, StrPtr("Yahoo Finance")))
            SendMessage(hDSSource, CB_ADDSTRING, 0, Cast(LPARAM, StrPtr("Stooq")))
            SendMessage(hDSSource, CB_ADDSTRING, 0, Cast(LPARAM, StrPtr("Alpha Vantage Stocks")))
            SendMessage(hDSSource, CB_ADDSTRING, 0, Cast(LPARAM, StrPtr("Alpha Vantage Forex")))
            SendMessage(hDSSource, CB_ADDSTRING, 0, Cast(LPARAM, StrPtr("Alpha Vantage Crypto")))
            SendMessage(hDSSource, CB_ADDSTRING, 0, Cast(LPARAM, StrPtr("Tiingo IEX")))
            SendMessage(hDSSource, CB_ADDSTRING, 0, Cast(LPARAM, StrPtr("Finnhub Stocks")))
            SendMessage(hDSSource, CB_ADDSTRING, 0, Cast(LPARAM, StrPtr("Finnhub Crypto")))
            SendMessage(hDSSource, CB_ADDSTRING, 0, Cast(LPARAM, StrPtr("Twelvedata")))
            SendMessage(hDSSource, CB_ADDSTRING, 0, Cast(LPARAM, StrPtr("QChartist Exchange")))
            SendMessage(hDSSource, CB_SETCURSEL, 0, 0)   ' défaut : Tiingo Cryptocurrencies
            ' Symbol
            CreateWindowEx(0,"STATIC","Symbol:",WS_CHILD Or WS_VISIBLE,8,34,55,18,hWnd,NULL,GetModuleHandle(NULL),NULL)
            hDSSymbol = CreateWindowEx(WS_EX_CLIENTEDGE,"EDIT","btcusdt",WS_CHILD Or WS_VISIBLE Or ES_UPPERCASE,68,32,120,20,hWnd,Cast(HMENU,ID_DS_SYMBOL),GetModuleHandle(NULL),NULL)
            ' Start date
            CreateWindowEx(0,"STATIC","Start date:",WS_CHILD Or WS_VISIBLE,8,58,60,18,hWnd,NULL,GetModuleHandle(NULL),NULL)
            hDSStartDate = CreateWindowEx(WS_EX_CLIENTEDGE,"EDIT","2025-01-01",WS_CHILD Or WS_VISIBLE,68,56,120,20,hWnd,Cast(HMENU,ID_DS_STARTDATE),GetModuleHandle(NULL),NULL)
            ' End date
            CreateWindowEx(0,"STATIC","End date:",WS_CHILD Or WS_VISIBLE,8,82,60,18,hWnd,NULL,GetModuleHandle(NULL),NULL)
            hDSEndDate = CreateWindowEx(WS_EX_CLIENTEDGE,"EDIT","2026-03-25",WS_CHILD Or WS_VISIBLE,68,80,120,20,hWnd,Cast(HMENU,ID_DS_ENDDATE),GetModuleHandle(NULL),NULL)
            ' Timeframe combobox
            CreateWindowEx(0,"STATIC","Timeframe:",WS_CHILD Or WS_VISIBLE,8,106,65,18,hWnd,NULL,GetModuleHandle(NULL),NULL)
            hDSTF = CreateWindowEx(0,"COMBOBOX","",WS_CHILD Or WS_VISIBLE Or CBS_DROPDOWNLIST Or WS_VSCROLL,68,104,80,160,hWnd,Cast(HMENU,ID_DS_TF),GetModuleHandle(NULL),NULL)
            SendMessage(hDSTF, CB_ADDSTRING, 0, Cast(LPARAM, StrPtr("1M")))
            SendMessage(hDSTF, CB_ADDSTRING, 0, Cast(LPARAM, StrPtr("5M")))
            SendMessage(hDSTF, CB_ADDSTRING, 0, Cast(LPARAM, StrPtr("15M")))
            SendMessage(hDSTF, CB_ADDSTRING, 0, Cast(LPARAM, StrPtr("30M")))
            SendMessage(hDSTF, CB_ADDSTRING, 0, Cast(LPARAM, StrPtr("60M")))
            SendMessage(hDSTF, CB_ADDSTRING, 0, Cast(LPARAM, StrPtr("240M")))
            SendMessage(hDSTF, CB_ADDSTRING, 0, Cast(LPARAM, StrPtr("1440M")))
            SendMessage(hDSTF, CB_ADDSTRING, 0, Cast(LPARAM, StrPtr("10080M")))
            SendMessage(hDSTF, CB_ADDSTRING, 0, Cast(LPARAM, StrPtr("43200M")))
            SendMessage(hDSTF, CB_SETCURSEL, 6, 0)   ' défaut 1440M
            ' Boutons Get chart + API Keys
            hDSGetChart = CreateWindowEx(0,"BUTTON","Get chart",WS_CHILD Or WS_VISIBLE Or BS_PUSHBUTTON,8,134,90,24,hWnd,Cast(HMENU,ID_DS_GETCHART),GetModuleHandle(NULL),NULL)
            CreateWindowEx(0,"BUTTON","API keys",WS_CHILD Or WS_VISIBLE Or BS_PUSHBUTTON,108,134,80,24,hWnd,Cast(HMENU,ID_DS_APIKEYS_BTN),GetModuleHandle(NULL),NULL)
            hDSStatus = CreateWindowEx(0,"STATIC","Ready",WS_CHILD Or WS_VISIBLE,8,168,370,36,hWnd,Cast(HMENU,ID_DS_STATUS),GetModuleHandle(NULL),NULL)

        Case WM_COMMAND
            Dim dsId As Integer = Loword(wParam)
            If dsId = ID_DS_GETCHART Then
                Dim srcIdx As Integer = 0
                If hDSSource <> 0 Then srcIdx = SendMessage(hDSSource, CB_GETCURSEL, 0, 0)
                Select Case srcIdx
                    Case 0 : TiingoGetChart(hWndMain)         ' Tiingo Cryptocurrencies
                    Case 1 : YahooFinanceGetChart(hWndMain)   ' Yahoo Finance
                    Case Else
                        If hDSStatus <> 0 Then SetWindowText(hDSStatus, "Source not yet implemented.")
                End Select
            ElseIf dsId = ID_DS_APIKEYS_BTN Then
                OpenApiKeysWindow(hWnd)
            End If

        Case WM_DESTROY
            hDSWin = 0
            Return 0
    End Select
    Return DefWindowProc(hWnd, uMsg, wParam, lParam)
End Function

' ── Retourne la chaîne de fréquence Tiingo selon l'index combobox ─────────────
Function TiingoFreq(tfIdx As Integer) As String
    Select Case tfIdx
        Case 0 : Return "1min"
        Case 1 : Return "5min"
        Case 2 : Return "15min"
        Case 3 : Return "30min"
        Case 4 : Return "60min"
        Case 5 : Return "240min"
        Case 6 : Return "1440min"
        Case 7 : Return "10080min"
        Case 8 : Return "43200min"
    End Select
    Return "60min"
End Function

Function TiingoTFMin(tfIdx As Integer) As Integer
    Dim mins(8) As Integer = {1,5,15,30,60,240,1440,10080,43200}
    If tfIdx >= 0 And tfIdx <= 8 Then Return mins(tfIdx)
    Return 60
End Function

Sub TiingoGetChart(hWndParent As HWND)
    If hDSWin = 0 Then Return
    If gKeyTiingo = "" Then
        If hDSStatus <> 0 Then SetWindowText(hDSStatus, "Please enter your Tiingo API key (API keys button).")
        Return
    End If

    ' Lire les champs
    Dim zSym   As ZString * 64  : GetWindowText(hDSSymbol,    @zSym,    64)
    Dim zStart As ZString * 32  : GetWindowText(hDSStartDate, @zStart,  32)
    Dim tfIdx As Integer = SendMessage(hDSTF, CB_GETCURSEL, 0, 0)

    Dim sym   As String = Trim(zSym)
    Dim sdate As String = Trim(zStart)
    Dim key   As String = Trim(gKeyTiingo)   ' clé Tiingo depuis la fenêtre API Keys
    Dim freq  As String = TiingoFreq(tfIdx)
    Dim tfMin As Integer = TiingoTFMin(tfIdx)

    If sym = "" Or key = "" Then
        SetWindowText(hDSStatus, "Please enter a symbol and API key.")
        Return
    End If

    ' Préparer le dossier tiingo
    Dim zTiingoDir As ZString * 32 = "tiingo"
    CreateDirectory(@zTiingoDir, NULL)

    dsBusyFile   = "tiingo\isbusy.txt"
    dsPendingCSV = "tiingo\" & UCase(sym) & Str(tfMin) & ".csv"
    dsActiveSource = 0

    ' Supprimer t1.txt s'il existe (évite faux positif du timer)
    Dim t1Old As String = "tiingo\t1.txt"
    If FileLen(t1Old) > 0 Then Kill t1Old

    ' Écrire isbusy = 1
    Dim fb As Integer = FreeFile
    Open dsBusyFile For Output As #fb : Print #fb, "1" : Close #fb

    ' Écrire un .bat temporaire dans tiingo\ pour éviter les pb de guillemets
    ' Le bat fait : curl ... && echo 0 > isbusy.txt
    Dim batPath As String = "tiingo\_fetch.bat"
    Dim fw As Integer = FreeFile
    Open batPath For Output As #fw
    Print #fw, "@echo off"
    ' Essayer curl d'abord (dossier local puis PATH), sinon PowerShell (Windows 7+)
    Print #fw, "if exist curl.exe set CURL=curl.exe"
    Print #fw, "if not exist curl.exe set CURL=curl"
    Print #fw, "%CURL% --version >nul 2>&1"
    Print #fw, "if %errorlevel% equ 0 goto USE_CURL"
    Print #fw, ":USE_POWERSHELL"
    ' PowerShell fallback pour Windows 7 sans curl
    Dim psUrl As String = "https://api.tiingo.com/tiingo/crypto/prices?tickers=" & _
        UCase(sym) & "&startDate=" & sdate & "&resampleFreq=" & freq & "&token=" & key
    Print #fw, "powershell -Command ""(New-Object Net.WebClient).DownloadFile('" & _
        psUrl & "', 't1.txt')"""
    Print #fw, "goto DONE"
    Print #fw, ":USE_CURL"
    ' curl avec token dans header Authorization (méthode recommandée Tiingo)
    Print #fw, "%CURL% --connect-timeout 30 -m 120 -k " & _
        "-H " & Chr(34) & "Authorization: Token " & key & Chr(34) & _
        " -o t1.txt " & _
        Chr(34) & "https://api.tiingo.com/tiingo/crypto/prices?tickers=" & _
        UCase(sym) & "&startDate=" & sdate & "&resampleFreq=" & freq & Chr(34)
    Print #fw, ":DONE"
    Print #fw, "echo 0 > isbusy.txt"
    Close #fw

    ' Lancer via cmd.exe /c
    Dim zCmd  As ZString * 16  = "cmd.exe"
    Dim zArgs As ZString * 128
    zArgs = "/c _fetch.bat"
    Dim zDir  As ZString * 64  = "tiingo"
    Dim zVerb As ZString * 8   = "open"
    ShellExecute(hWndParent, @zVerb, @zCmd, @zArgs, @zDir, 0)

    SetWindowText(hDSStatus, "Downloading " & UCase(sym) & " " & freq & "...")

    ' Démarrer le timer de polling (vérifie isbusy.txt toutes les 1s)
    dsTimerActive = 1
    dsTimerCount  = 0
    SetTimer(hWndParent, ID_DS_TIMER, 1000, NULL)
End Sub

Sub TiingoCheckDone(hWnd As HWND)
    dsTimerCount += 1
    ' Le fichier à surveiller dépend de la source active
    Dim t1Path As String
    Select Case dsActiveSource
        Case 0  : t1Path = "tiingo\t1.txt"
        Case 1  : t1Path = "yahoo\yf1.txt"
        Case Else : t1Path = "tiingo\t1.txt"
    End Select
    Dim fi As Integer = FreeFile
    Dim fsize As Long = 0
    If Open(t1Path For Input As #fi) = 0 Then
        fsize = LOF(fi)
        Close #fi
    End If

    If fsize > 100 Then
        KillTimer(hWnd, ID_DS_TIMER)
        dsTimerActive = 0
        If hDSStatus <> 0 Then SetWindowText(hDSStatus, "Parsing and loading...")
        Select Case dsActiveSource
            Case 0 : TiingoParseAndLoad(t1Path, hWnd)
            Case 1 : YahooFinanceParseAndLoad(t1Path, hWnd)
            Case Else : TiingoParseAndLoad(t1Path, hWnd)
        End Select
    ElseIf dsTimerCount > 120 Then
        ' Timeout après 120 secondes
        KillTimer(hWnd, ID_DS_TIMER)
        dsTimerActive = 0
        If hDSStatus <> 0 Then SetWindowText(hDSStatus, "Error: timeout - check API key and connection.")
    Else
        ' Afficher progression (dots animés)
        Dim dots As String = String(dsTimerCount Mod 4, ".")
        If hDSStatus <> 0 Then SetWindowText(hDSStatus, "Downloading" & dots & " (" & Str(dsTimerCount) & "s)")
    End If
End Sub

' ── Parser JSON Tiingo et écriture CSV ───────────────────────────────────────
' Format Tiingo : [{"ticker":"...","priceData":[{"date":"2026-03-09T16:00:00+00:00",
'   "open":...,"high":...,"low":...,"close":...,"volume":...},...]}]
Sub TiingoParseAndLoad(ByVal jsonPath As String, hWnd As HWND)
    ' Lire tout le JSON en mémoire
    Dim fi As Integer = FreeFile
    If Open(jsonPath For Input As #fi) <> 0 Then Return
    Dim json As String = ""
    Dim ln  As String
    Do While Not EOF(fi)
        Line Input #fi, ln
        json &= ln
    Loop
    Close #fi

    ' Trouver priceData array
    Dim pdStart As Long = InStr(json, """priceData"":[")
    If pdStart = 0 Then
        If hDSStatus <> 0 Then SetWindowText(hDSStatus, "Error: no priceData in response.")
        Return
    End If
    pdStart += Len("""priceData"":[")
    Dim pdEnd As Long = InStr(pdStart, json, "]}")
    If pdEnd = 0 Then pdEnd = Len(json)

    Dim priceSection As String = Mid(json, pdStart, pdEnd - pdStart)

    ' Parser chaque objet { ... }
    Dim tfIdx As Integer = 0
    If hDSTF <> 0 Then tfIdx = SendMessage(hDSTF, CB_GETCURSEL, 0, 0)
    Dim tfMin As Integer = TiingoTFMin(tfIdx)

    ' Écrire directement dans le CSV pendant le parsing
    Dim fo As Integer = FreeFile
    If Open(dsPendingCSV For Output As #fo) <> 0 Then
        If hDSStatus <> 0 Then SetWindowText(hDSStatus, "Error: cannot write CSV.")
        Return
    End If

    Dim barCount As Integer = 0
    Dim parsePos As Long = 1

    Do
        Dim objStart As Integer = InStr(parsePos, priceSection, "{")
        If objStart = 0 Then Exit Do
        Dim objEnd As Integer = InStr(objStart, priceSection, "}")
        If objEnd = 0 Then Exit Do
        Dim obj As String = Mid(priceSection, objStart, objEnd - objStart + 1)
        parsePos = objEnd + 1

        ' Extraire date
        Dim dateStr As String = ExtractJsonStr(obj, "date")
        ' Format: 2026-03-09T16:00:00+00:00
        Dim dtDate As String = Left(dateStr, 10)   ' YYYY-MM-DD
        Dim dtTime As String = Mid(dateStr, 12, 5)  ' HH:MM

        Dim openV  As String = ExtractJsonNum(obj, "open")
        Dim highV  As String = ExtractJsonNum(obj, "high")
        Dim lowV   As String = ExtractJsonNum(obj, "low")
        Dim closeV As String = ExtractJsonNum(obj, "close")
        Dim volV   As String = ExtractJsonNum(obj, "volume")

        If dtDate <> "" And openV <> "" Then
            Print #fo, dtDate & "," & dtTime & "," & openV & "," & highV & "," & lowV & "," & closeV & "," & volV
            barCount += 1
        End If
    Loop

    Close #fo

    If barCount = 0 Then
        If hDSStatus <> 0 Then SetWindowText(hDSStatus, "Error: no bars parsed.")
        Return
    End If
    LoadCSV(dsPendingCSV, hWnd)

    Dim zSym As ZString * 64
    If hDSSymbol <> 0 Then GetWindowText(hDSSymbol, @zSym, 64)
    Dim statusMsg As String = "Loaded " & Str(barCount) & " bars for " & Trim(zSym)
    If hDSStatus <> 0 Then SetWindowText(hDSStatus, statusMsg)
End Sub

' ── Helpers extraction JSON minimaliste ──────────────────────────────────────
Function ExtractJsonStr(ByVal obj As String, ByVal key As String) As String
    Dim srchKey As String = Chr(34) & key & Chr(34) & ":"
    Dim p As Integer = InStr(obj, srchKey)
    If p = 0 Then Return ""
    p += Len(srchKey)
    ' Sauter espaces
    Do While p <= Len(obj) And Mid(obj, p, 1) = " " : p += 1 : Loop
    If Mid(obj, p, 1) = Chr(34) Then
        p += 1
        Dim q As Integer = InStr(p, obj, Chr(34))
        If q = 0 Then Return ""
        Return Mid(obj, p, q - p)
    End If
    Return ""
End Function

Function ExtractJsonNum(ByVal obj As String, ByVal key As String) As String
    Dim srchKey As String = Chr(34) & key & Chr(34) & ":"
    Dim p As Integer = InStr(obj, srchKey)
    If p = 0 Then Return ""
    p += Len(srchKey)
    Do While p <= Len(obj) And Mid(obj, p, 1) = " " : p += 1 : Loop
    Dim result As String = ""
    Do While p <= Len(obj)
        Dim c As String = Mid(obj, p, 1)
        If c >= "0" And c <= "9" Or c = "." Or c = "-" Or c = "e" Or c = "E" Or c = "+" Then
            result &= c : p += 1
        Else
            Exit Do
        End If
    Loop
    Return result
End Function

' ── API Keys window ───────────────────────────────────────────────────────────
Sub OpenApiKeysWindow(hWndParent As HWND)
    If hAKWin <> 0 Then
        ShowWindow(hAKWin, SW_RESTORE)
        SetForegroundWindow(hAKWin)
        Return
    End If
    Dim wcAK As WNDCLASS
    wcAK.lpfnWndProc   = @ApiKeysProc
    wcAK.hInstance     = GetModuleHandle(NULL)
    wcAK.hCursor       = LoadCursor(NULL, IDC_ARROW)
    wcAK.hbrBackground = Cast(HBRUSH, COLOR_BTNFACE + 1)
    wcAK.lpszClassName = StrPtr("AKWin")
    RegisterClass(@wcAK)
    hAKWin = CreateWindowEx(WS_EX_TOOLWINDOW, "AKWin", "API Keys", _
        WS_OVERLAPPED Or WS_CAPTION Or WS_SYSMENU Or WS_VISIBLE, _
        250, 180, 400, 230, hWndParent, NULL, GetModuleHandle(NULL), NULL)
End Sub

Function ApiKeysProc(hWnd As HWND, uMsg As UINT, wParam As WPARAM, lParam As LPARAM) As LRESULT
    Dim lw As Integer = 180   ' largeur label
    Dim fw As Integer = 180   ' largeur champ edit
    Dim ex As Integer = 8     ' x départ label
    Dim fx As Integer = 190   ' x départ edit
    Select Case uMsg
        Case WM_CREATE
            CreateWindowEx(0,"STATIC","Enter your Tiingo API key:",    WS_CHILD Or WS_VISIBLE, ex,12, lw,18,hWnd,NULL,GetModuleHandle(NULL),NULL)
            hAKTiingo  = CreateWindowEx(WS_EX_CLIENTEDGE,"EDIT","",WS_CHILD Or WS_VISIBLE Or ES_AUTOHSCROLL, fx,10, fw,20,hWnd,Cast(HMENU,ID_AK_TIINGO),   GetModuleHandle(NULL),NULL)
            CreateWindowEx(0,"STATIC","Enter your Finnhub API key:",   WS_CHILD Or WS_VISIBLE, ex,42, lw,18,hWnd,NULL,GetModuleHandle(NULL),NULL)
            hAKFinnhub = CreateWindowEx(WS_EX_CLIENTEDGE,"EDIT","",WS_CHILD Or WS_VISIBLE Or ES_AUTOHSCROLL, fx,40, fw,20,hWnd,Cast(HMENU,ID_AK_FINNHUB),   GetModuleHandle(NULL),NULL)
            CreateWindowEx(0,"STATIC","Enter your Alpha Vantage API key:", WS_CHILD Or WS_VISIBLE, ex,72, lw,18,hWnd,NULL,GetModuleHandle(NULL),NULL)
            hAKAlpha   = CreateWindowEx(WS_EX_CLIENTEDGE,"EDIT","",WS_CHILD Or WS_VISIBLE Or ES_AUTOHSCROLL, fx,70, fw,20,hWnd,Cast(HMENU,ID_AK_ALPHAVANTAGE),GetModuleHandle(NULL),NULL)
            CreateWindowEx(0,"STATIC","Enter your Twelvedata API key:", WS_CHILD Or WS_VISIBLE, ex,102,lw,18,hWnd,NULL,GetModuleHandle(NULL),NULL)
            hAKTwelve  = CreateWindowEx(WS_EX_CLIENTEDGE,"EDIT","",WS_CHILD Or WS_VISIBLE Or ES_AUTOHSCROLL, fx,100,fw,20,hWnd,Cast(HMENU,ID_AK_TWELVEDATA), GetModuleHandle(NULL),NULL)
            ' Bouton Save
            CreateWindowEx(0,"BUTTON","Save",WS_CHILD Or WS_VISIBLE Or BS_PUSHBUTTON, 160,140,70,24,hWnd,Cast(HMENU,ID_AK_SAVE),GetModuleHandle(NULL),NULL)
            ' Pré-remplir depuis les variables globales
            If gKeyTiingo    <> "" Then SetWindowText(hAKTiingo,  gKeyTiingo)
            If gKeyFinnhub   <> "" Then SetWindowText(hAKFinnhub, gKeyFinnhub)
            If gKeyAlpha     <> "" Then SetWindowText(hAKAlpha,   gKeyAlpha)
            If gKeyTwelvedata <> "" Then SetWindowText(hAKTwelve, gKeyTwelvedata)

        Case WM_COMMAND
            If Loword(wParam) = ID_AK_SAVE Then
                ' Lire les champs
                Dim z1 As ZString*512 : GetWindowText(hAKTiingo,  @z1, 512) : gKeyTiingo     = Trim(z1)
                Dim z2 As ZString*512 : GetWindowText(hAKFinnhub, @z2, 512) : gKeyFinnhub    = Trim(z2)
                Dim z3 As ZString*512 : GetWindowText(hAKAlpha,   @z3, 512) : gKeyAlpha      = Trim(z3)
                Dim z4 As ZString*512 : GetWindowText(hAKTwelve,  @z4, 512) : gKeyTwelvedata = Trim(z4)
                SaveIniFile()
                DestroyWindow(hWnd)
            End If

        Case WM_DESTROY
            ' Sauvegarder aussi à la fermeture (croix)
            If hAKTiingo <> 0 Then
                Dim z1c As ZString*512 : GetWindowText(hAKTiingo,  @z1c, 512) : gKeyTiingo     = Trim(z1c)
                Dim z2c As ZString*512 : GetWindowText(hAKFinnhub, @z2c, 512) : gKeyFinnhub    = Trim(z2c)
                Dim z3c As ZString*512 : GetWindowText(hAKAlpha,   @z3c, 512) : gKeyAlpha      = Trim(z3c)
                Dim z4c As ZString*512 : GetWindowText(hAKTwelve,  @z4c, 512) : gKeyTwelvedata = Trim(z4c)
                SaveIniFile()
            End If
            hAKWin = 0
            Return 0
    End Select
    Return DefWindowProc(hWnd, uMsg, wParam, lParam)
End Function

' ── Lecture/écriture QChartist2.ini ──────────────────────────────────────────
Sub LoadIniFile()
    Dim fi As Integer = FreeFile
    If Open("QChartist2.ini" For Input As #fi) <> 0 Then Return
    Dim ln As String
    Do While Not EOF(fi)
        Line Input #fi, ln
        ln = Trim(ln)
        Dim eq As Integer = InStr(ln, "=")
        If eq = 0 Then Continue Do
        Dim k As String = Trim(Left(ln, eq - 1))
        Dim v As String = Trim(Mid(ln, eq + 1))
        Select Case LCase(k)
            Case "tiingo_apikey"    : gKeyTiingo     = v
            Case "finnhub_apikey"   : gKeyFinnhub    = v
            Case "alpha_apikey"     : gKeyAlpha      = v
            Case "twelvedata_apikey": gKeyTwelvedata = v
        End Select
    Loop
    Close #fi
End Sub

Sub SaveIniFile()
    Dim fo As Integer = FreeFile
    If Open("QChartist2.ini" For Output As #fo) <> 0 Then Return
    Print #fo, "tiingo_apikey="     & gKeyTiingo
    Print #fo, "finnhub_apikey="    & gKeyFinnhub
    Print #fo, "alpha_apikey="      & gKeyAlpha
    Print #fo, "twelvedata_apikey=" & gKeyTwelvedata
    Close #fo
End Sub

' ── Yahoo Finance ─────────────────────────────────────────────────────────────
Sub YahooFinanceGetChart(hWndParent As HWND)
    If hDSWin = 0 Then Return

    Dim zSym   As ZString * 64  : GetWindowText(hDSSymbol,    @zSym,   64)
    Dim zStart As ZString * 32  : GetWindowText(hDSStartDate, @zStart, 32)
    Dim zEnd   As ZString * 32  : GetWindowText(hDSEndDate,   @zEnd,   32)
    Dim tfIdx  As Integer = SendMessage(hDSTF, CB_GETCURSEL, 0, 0)

    Dim sym    As String = UCase(Trim(zSym))
    Dim tfMin  As Integer = TiingoTFMin(tfIdx)

    If sym = "" Then
        If hDSStatus <> 0 Then SetWindowText(hDSStatus, "Please enter a symbol.")
        Return
    End If

    ' Convertir les dates en Unix timestamps
    ' Format attendu : YYYY-MM-DD
    Dim sdate As String = Trim(zStart)
    Dim edate As String = Trim(zEnd)

    Dim syr As Integer = CInt(Mid(sdate,1,4))
    Dim smo As Integer = CInt(Mid(sdate,6,2))
    Dim sdy As Integer = CInt(Mid(sdate,9,2))
    Dim eyr As Integer = CInt(Mid(edate,1,4))
    Dim emo As Integer = CInt(Mid(edate,6,2))
    Dim edy As Integer = CInt(Mid(edate,9,2))

    Dim tsStart As Long = CLng((CDbl(DateSerial(syr,smo,sdy)) - 25569.0) * 86400.0)
    Dim tsEnd   As Long = CLng((CDbl(DateSerial(eyr,emo,edy)) - 25569.0) * 86400.0) + 86400

    ' Intervalle YF
    Dim yfInterval As String
    Select Case tfMin
        Case 1    : yfInterval = "1m"
        Case 5    : yfInterval = "5m"
        Case 15   : yfInterval = "15m"
        Case 30   : yfInterval = "30m"
        Case 60   : yfInterval = "1h"
        Case 240  : yfInterval = "1h"   ' YF n'a pas de 4h natif
        Case 1440 : yfInterval = "1d"
        Case 10080: yfInterval = "1wk"
        Case 43200: yfInterval = "1mo"
        Case Else : yfInterval = "1d"
    End Select

    ' Préparer dossier
    Dim zYFDir As ZString * 32 = "yahoo"
    CreateDirectory(@zYFDir, NULL)

    dsBusyFile   = "yahoo\isbusy.txt"
    dsPendingCSV = "yahoo\" & sym & Str(tfMin) & ".csv"
    dsActiveSource = 1

    ' Supprimer yf1.txt pour éviter faux positif
    Dim yfJson As String = "yahoo\yf1.txt"
    If FileLen(yfJson) > 0 Then Kill yfJson

    ' Générer le .bat
    Dim batPath As String = "yahoo\_fetch.bat"
    Dim fw As Integer = FreeFile
    Open batPath For Output As #fw
    Print #fw, "@echo off"
    Print #fw, "if exist curl.exe (set CURL=curl.exe) else (set CURL=curl)"
    ' User-Agent Mozilla pour éviter le blocage YF
    Dim yfUrl As String = "https://query1.finance.yahoo.com/v8/finance/chart/" & sym & _
        "?interval=" & yfInterval & "&period1=" & Str(tsStart) & "&period2=" & Str(tsEnd)
    Print #fw, "%CURL% -A " & Chr(34) & "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" & Chr(34) & _
        " --connect-timeout 30 -m 60 -k -o yf1.txt " & Chr(34) & yfUrl & Chr(34)
    Print #fw, "echo 0 > isbusy.txt"
    Close #fw

    Dim zCmd  As ZString * 16  = "cmd.exe"
    Dim zArgs As ZString * 128 : zArgs = "/c _fetch.bat"
    Dim zDir  As ZString * 64  = "yahoo"
    Dim zVerb As ZString * 8   = "open"
    ShellExecute(hWndParent, @zVerb, @zCmd, @zArgs, @zDir, 0)

    ' Rediriger le timer vers yahoo\yf1.txt
    dsBusyFile = "yahoo\yf1.txt"  ' CheckDone regarde ce fichier
    SetWindowText(hDSStatus, "Downloading " & sym & " from Yahoo Finance...")

    dsTimerActive = 1
    dsTimerCount  = 0
    SetTimer(hWndParent, ID_DS_TIMER, 1000, NULL)
End Sub

' ── Parser JSON Yahoo Finance ─────────────────────────────────────────────────
' Format : {"chart":{"result":[{"timestamp":[...],"indicators":{"quote":[{
'   "open":[...],"high":[...],"low":[...],"close":[...],"volume":[...]}]}}]}}
Sub YahooFinanceParseAndLoad(ByVal jsonPath As String, hWnd As HWND)
    ' Parser via yf_parse.py (Python embarqué) — évite tout problème InStr/Long/Integer
    ' Le script Python utilise json.load() natif → parsing correct garanti

    ' Chercher python dans : dossier local embarqué, puis PATH
    Dim pyExe As String
    If FileLen("python-3.13.12-embed-amd64\python.exe") > 0 Then
        pyExe = "python-3.13.12-embed-amd64\python.exe"
    Else
        pyExe = "python"
    End If

    ' Copier yf_parse.py dans le dossier yahoo si besoin
    If FileLen("yahoo\yf_parse.py") <= 0 Then
        If FileLen("yf_parse.py") > 0 Then
            FileCopy "yf_parse.py", "yahoo\yf_parse.py"
        End If
    End If

    ' Générer le bat qui lance le parser
    Dim batPath As String = "yahoo\_parse.bat"
    Dim fw As Integer = FreeFile
    Open batPath For Output As #fw
    Print #fw, "@echo off"
    ' Chemin absolu vers python et le script
    Dim absPy  As String = CurDir & "\" & pyExe
    Dim absSc  As String = CurDir & "\yahoo\yf_parse.py"
    Dim absIn  As String = CurDir & "\yahoo\yf1.txt"
    Dim absOut As String = CurDir & "\" & dsPendingCSV
    Print #fw, Chr(34) & absPy & Chr(34) & " " & Chr(34) & absSc & Chr(34) & _
        " " & Chr(34) & absIn & Chr(34) & " " & Chr(34) & absOut & Chr(34)
    Print #fw, "echo 0 > isbusy.txt"
    Close #fw

    ' Supprimer le CSV destination pour détecter la fin
    If FileLen(dsPendingCSV) > 0 Then Kill dsPendingCSV

    ' Lancer le bat
    Dim zCmd  As ZString * 16 = "cmd.exe"
    Dim zArgs As ZString * 32 : zArgs = "/c _parse.bat"
    Dim zDir  As ZString * 64 = "yahoo"
    Dim zVerb As ZString * 8  = "open"
    ShellExecute(hWnd, @zVerb, @zCmd, @zArgs, @zDir, 0)

    ' Attendre que le CSV soit créé (max 15s, check toutes les 500ms)
    Dim waited As Integer = 0
    Do
        Sleep 500
        waited += 1
        If FileLen(dsPendingCSV) > 10 Then Exit Do
    Loop Until waited > 30

    If FileLen(dsPendingCSV) < 10 Then
        If hDSStatus <> 0 Then SetWindowText(hDSStatus, "Error: Python parser failed. Check yf_parse.py is present.")
        Return
    End If

    LoadCSV(dsPendingCSV, hWnd)
    Dim zSym2 As ZString * 64
    If hDSSymbol <> 0 Then GetWindowText(hDSSymbol, @zSym2, 64)
    ' Compter les barres
    Dim fc As Integer = FreeFile, barCount As Integer = 0
    If Open(dsPendingCSV For Input As #fc) = 0 Then
        Dim tmp As String
        Do While Not EOF(fc) : Line Input #fc, tmp : barCount += 1 : Loop
        Close #fc
    End If
    If hDSStatus <> 0 Then SetWindowText(hDSStatus, "Loaded " & Str(barCount) & " bars from Yahoo Finance.")
End Sub

' ── Extraire le prochain token d'un tableau CSV ───────────────────────────────
Function YFNextToken(ByVal arr As String, ByRef scanPos As Integer) As String
    If scanPos > Len(arr) Then Return ""
    ' Sauter espaces/virgules
    Do While scanPos <= Len(arr)
        Dim sc As String = Mid(arr, scanPos, 1)
        If sc <> "," And sc <> " " Then Exit Do
        scanPos += 1
    Loop
    If scanPos > Len(arr) Then Return ""
    Dim result As String = ""
    Do While scanPos <= Len(arr)
        Dim c As String = Mid(arr, scanPos, 1)
        If c = "," Then Exit Do
        result &= c
        scanPos += 1
    Loop
    Return Trim(result)
End Function

' ── Unix timestamp → "YYYY-MM-DD,HH:MM" ──────────────────────────────────────
Function UnixToCSVDate(ByVal ts As Double) As String
    ' Calcul direct depuis timestamp Unix sans CDate
    Dim totalSec As Long = CLng(ts)
    Dim hr As Integer    = (totalSec Mod 86400) \ 3600
    Dim mn As Integer    = (totalSec Mod 3600)  \ 60

    ' Jours depuis l'epoch Unix (01/01/1970) = jour julien modifié
    Dim days As Long = totalSec \ 86400

    ' Algorithme de conversion jours Unix → YYYY-MM-DD
    Dim z As Long = days + 719468
    Dim era As Long = IIf(z >= 0, z, z - 146096) \ 146097
    Dim doe As Long = z - era * 146097
    Dim yoe As Long = (doe - doe \ 1460 + doe \ 36524 - doe \ 146096) \ 365
    Dim yr  As Integer = CInt(yoe + era * 400)
    Dim doy As Long = doe - (365 * yoe + yoe \ 4 - yoe \ 100)
    Dim mp  As Long = (5 * doy + 2) \ 153
    Dim dy  As Integer = CInt(doy - (153 * mp + 2) \ 5 + 1)
    Dim mo  As Integer = CInt(IIf(mp < 10, mp + 3, mp - 9))
    If mo <= 2 Then yr += 1

    Dim yrS As String = Right("0000" & Str(yr), 4)
    Dim moS As String = Right("00"   & Str(mo), 2)
    Dim dyS As String = Right("00"   & Str(dy), 2)
    Dim hrS As String = Right("00"   & Str(hr), 2)
    Dim mnS As String = Right("00"   & Str(mn), 2)

    Return yrS & "-" & moS & "-" & dyS & "," & hrS & ":" & mnS
End Function

' --- Main ---
Dim appName As String = "QChartGDI"
Dim wcl As WNDCLASS
With wcl
    .lpfnWndProc = @WndProc
    .hInstance = GetModuleHandle(NULL)
    .hCursor = LoadCursor(NULL, IDC_ARROW)
    .hbrBackground = NULL
    .lpszClassName = StrPtr(appName)
End With
RegisterClass(@wcl)
CreateWindowEx(0, appName, "QChart Pro", WS_OVERLAPPEDWINDOW Or WS_VISIBLE, _
    CW_USEDEFAULT, CW_USEDEFAULT, 1000, 600, NULL, NULL, GetModuleHandle(NULL), NULL)
Dim gsi As GdiplusStartupInput : gsi.GdiplusVersion = 1
GdiplusStartup(@gdiplusToken, @gsi, NULL)
Dim wMsg As MSG
Do While GetMessage(@wMsg, NULL, 0, 0)
    TranslateMessage(@wMsg)
    DispatchMessage(@wMsg)
Loop
GdiplusShutdown(gdiplusToken)
