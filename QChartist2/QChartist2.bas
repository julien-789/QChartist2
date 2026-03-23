#define WIN_INCLUDEALL
#include once "windows.bi"
#include once "win/commdlg.bi"
#include once "win/commctrl.bi"
#include once "vbcompat.bi"
#include once "win/gdiplus.bi"

#inclib "gdiplus"
#inclib "comctl32"

Using GDIPLUS

' --- Constantes ---
Const SCROLL_H = 40
#define ID_MENU_OPEN      1001
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
Declare Function IndicatorsDlgProc(hWnd As HWND, uMsg As UINT, wParam As WPARAM, lParam As LPARAM) As LRESULT
Declare Function ParamsDlgProc(hWnd As HWND, uMsg As UINT, wParam As WPARAM, lParam As LPARAM) As LRESULT
Declare Sub RenderChartGDIPlus(hWnd As HWND, hDC As HDC, w As Integer, h As Integer)
Declare Sub ForceRedraw(hWnd As HWND)
Declare Sub LoadCSV(ByVal filename As String, hWnd As HWND)
Declare Function File_GetName(ByVal hWndParent As HWND) As String
Declare Function DistToSegment(px As Single, py As Single, x1 As Single, y1 As Single, x2 As Single, y2 As Single) As Single
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
    ' QChart1440 : copie directe si le fichier est daily, sinon agrégation
    ' QChart10080 : agrégation weekly (7 barres daily → 1 barre weekly)
    ' QChart43200 : agrégation monthly
    Dim totalBarsLoaded As Long = UBound(QChart.History) + 1

    ' QChart1440 : toujours rempli avec les données du fichier courant
    ' (même si ce n'est pas du daily — sert de fallback)
    ' QChart1440 : copie directe depuis QChart en ordre croissant (0=plus ancien)
    ' avec calcul du timestamp Unix pour chaque barre
    ReDim QChart1440.History(totalBarsLoaded - 1)
    For bi As Long = 0 To totalBarsLoaded - 1
        QChart1440.History(bi).Dt   = QChart.History(bi).Dt
        QChart1440.History(bi).Tm   = QChart.History(bi).Tm
        QChart1440.History(bi).O    = QChart.History(bi).O
        QChart1440.History(bi).H    = QChart.History(bi).H
        QChart1440.History(bi).L    = QChart.History(bi).L
        QChart1440.History(bi).C    = QChart.History(bi).C
        QChart1440.History(bi).V    = QChart.History(bi).V
        QChart1440.History(bi).Unix = QChart.History(bi).Unix
    Next bi
    QChart1440.IsLoaded = 1

    ' QChart10080 (Weekly) : agréger les barres par semaine
    ' On groupe les barres par numéro de semaine ISO (lundi au dimanche)
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

    ' QChart43200 (Monthly) : agréger les barres par mois
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
    ' ── Avertissement si timeframe non standard ───────────────────────────────
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

Sub LoadCSV(ByVal filename As String, hWnd As HWND)
    Dim As Integer f = FreeFile, count = 0
    Dim As String lineStr
    If Open(filename For Input As #f) <> 0 Then Exit Sub
    Do While Not Eof(f)
        Line Input #f, lineStr
        If Len(Trim(lineStr)) > 10 Then count += 1
    Loop
    Close #f
    If count = 0 Then Exit Sub
    ReDim QChart.History(count - 1)
    Open filename For Input As #f
    For i As Integer = 0 To count - 1
        Input #f, QChart.History(i).Dt, QChart.History(i).Tm, QChart.History(i).O, QChart.History(i).H, QChart.History(i).L, QChart.History(i).C, QChart.History(i).V
        ' Calculer le timestamp Unix pour chaque barre (nécessaire pour IBarShift)
        QChart.History(i).Unix = DateToUnix(QChart.History(i).Dt, QChart.History(i).Tm)
    Next
    Close #f
    QChart.IsLoaded = 1
    Dim As Integer maxStart = count - QChart.ViewCount
    If maxStart < 0 Then maxStart = 0
    QChart.ViewStart = maxStart
    SetScrollRange(hScroll, SB_CTL, 0, maxStart, TRUE)
    SetScrollPos(hScroll, SB_CTL, maxStart, TRUE)
    DetectTimeframe()
    ForceRedraw(hWnd)
End Sub

Sub ForceRedraw(hWnd As HWND)
    InvalidateRect(hWnd, NULL, FALSE)
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

Sub RenderChartGDIPlus(hWnd As HWND, hDC As HDC, w As Integer, h As Integer)
    Dim rc As RECT
    rc.Left = 0 : rc.Top = 0 : rc.Right = w : rc.Bottom = h
    FillRect(hDC, @rc, GetStockObject(WHITE_BRUSH))

    Dim g As GpGraphics Ptr
    If GdipCreateFromHDC(hDC, @g) <> 0 Then Exit Sub
    GdipSetSmoothingMode(g, SmoothingModeAntiAlias)

    If QChart.IsLoaded = 0 Then
        Dim msgText As String = "Fichier > Ouvrir pour charger les donnees"
        TextOut(hDC, (w + toolbarW)\2 - 150, h\2, msgText, Len(msgText))
        GdipDeleteGraphics(g) : Exit Sub
    End If

    ' Compter les panneaux séparés (isPanel=1) pour la hauteur
    Dim panelCount As Long = 0
    For i As Integer = 0 To ActiveCount - 1
        If indRegistry.defs(ActivePanels(i).defIndex).isPanel = 1 Then panelCount += 1
    Next
    Dim As Integer rsiAreaH = panelCount * (RSI_PANEL_H + RSI_PANEL_GAP)
    Dim As Integer mainChartH = h - rsiAreaH - 40 - ZOOM_BAR_H

    ' 1. Echelle
    g_vMin = 1e30 : g_vMax = -1e30
    Dim As Integer lastIdx = QChart.ViewStart + QChart.ViewCount - 1
    If lastIdx > UBound(QChart.History) Then lastIdx = UBound(QChart.History)
    For i As Integer = QChart.ViewStart To lastIdx
        If QChart.History(i).L < g_vMin Then g_vMin = QChart.History(i).L
        If QChart.History(i).H > g_vMax Then g_vMax = QChart.History(i).H
    Next
    g_vMin *= 0.999 : g_vMax *= 1.001

    g_oriX = 65 + toolbarW : g_oriY = mainChartH + ZOOM_BAR_H
    Dim As Single lenX = w - 120 - toolbarW
    g_lenY = mainChartH - 40
    g_scaleY = IIf(g_vMax - g_vMin <> 0, g_lenY / (g_vMax - g_vMin), 1)
    g_stepX = lenX / QChart.ViewCount

    ' 1a. Grille + labels axe Y
    Dim nYTicks As Integer = 6
    Dim yRange As Double = g_vMax - g_vMin
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
    Dim firstTick As Double = Int(g_vMin / niceStep + 1) * niceStep
    Dim pGrid As GpPen Ptr : GdipCreatePen1(&HFFEEEEEE, 1.0, UnitPixel, @pGrid)
    Dim pAxis As GpPen Ptr : GdipCreatePen1(&HFFAAAAAA, 1.0, UnitPixel, @pAxis)
    SetBkMode(hDC, TRANSPARENT)
    SetTextColor(hDC, &H444444)
    Dim tick As Double = firstTick
    Do While tick <= g_vMax
        Dim yTick As Single = g_oriY - CSng((tick - g_vMin) * g_scaleY)
        If yTick >= ZOOM_BAR_H + 40 And yTick <= g_oriY Then
            GdipDrawLine(g, pGrid, g_oriX, yTick, g_oriX + lenX, yTick)
            GdipDrawLine(g, pAxis, g_oriX - 4, yTick, g_oriX, yTick)
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
            TextOut(hDC, CInt(g_oriX) - txtW - 6, CInt(yTick) - 7, priceStr, Len(priceStr))
        End If
        tick += niceStep
    Loop
    GdipDrawLine(g, pAxis, g_oriX, ZOOM_BAR_H + 40, g_oriX, g_oriY)
    GdipDeletePen(pGrid) : GdipDeletePen(pAxis)

    ' 1b. Labels axe X
    Dim minSpacePx As Single = 70.0
    Dim xStep As Integer = CInt(minSpacePx / g_stepX)
    If xStep < 1 Then xStep = 1
    Dim pAxisX As GpPen Ptr : GdipCreatePen1(&HFFAAAAAA, 1.0, UnitPixel, @pAxisX)
    GdipDrawLine(g, pAxisX, g_oriX, g_oriY, g_oriX + lenX, g_oriY)
    SetTextColor(hDC, &H444444)
    Dim xi As Integer = QChart.ViewStart
    Do While xi <= lastIdx
        Dim P As PriceData = QChart.History(xi)
        Dim xPos As Single = g_oriX + (xi - QChart.ViewStart) * g_stepX + (g_stepX / 2)
        GdipDrawLine(g, pAxisX, xPos, g_oriY, xPos, g_oriY + 4)
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
        TextOut(hDC, CInt(xPos) - lw \ 2, g_oriY + 6, xLbl, Len(xLbl))
        xi += xStep
    Loop
    GdipDeletePen(pAxisX)
    SetTextColor(hDC, 0)

    ' 2. Bougies
    For i As Integer = QChart.ViewStart To lastIdx
        Dim Pb As PriceData = QChart.History(i)
        Dim As Single x = g_oriX + (i - QChart.ViewStart) * g_stepX + (g_stepX/2)
        Dim As Single yO = g_oriY - (Pb.O - g_vMin) * g_scaleY
        Dim As Single yC = g_oriY - (Pb.C - g_vMin) * g_scaleY
        Dim As Single yH = g_oriY - (Pb.H - g_vMin) * g_scaleY
        Dim As Single yL = g_oriY - (Pb.L - g_vMin) * g_scaleY
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
    Dim totalBars As Long = UBound(QChart.History) + 1
    Dim Closes     (totalBars - 1) As Double
    Dim Opens      (totalBars - 1) As Double
    Dim Highs      (totalBars - 1) As Double
    Dim Lows       (totalBars - 1) As Double
    Dim Volumes    (totalBars - 1) As Double
    Dim Weekdays   (totalBars - 1) As Long
    Dim CurUnixTs  (totalBars - 1) As Double   ' timestamps Unix du TF courant
    For ci As Long = 0 To totalBars - 1
        Closes  (ci) = QChart.History(ci).C
        Opens   (ci) = QChart.History(ci).O
        Highs   (ci) = QChart.History(ci).H
        Lows    (ci) = QChart.History(ci).L
        Volumes (ci) = CDbl(QChart.History(ci).V)
        CurUnixTs(ci) = QChart.History(ci).Unix
        Dim dtStr2 As String = Trim(QChart.History(ci).Dt)
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
    mainChartH_cached = mainChartH
    PanelGeomCount = 0

    ' Contexte graphique partagé
    Dim ctx As ChartCtx
    ctx.oriX       = g_oriX
    ctx.oriY       = g_oriY
    ctx.stepX      = g_stepX
    ctx.lenX       = lenX
    ctx.vMin       = g_vMin
    ctx.scaleY     = g_scaleY
    ctx.mainChartH = CLng(mainChartH)
    ctx.viewStart  = CLng(QChart.ViewStart)
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
    For i As Integer = 0 To ActiveCount - 1
        Dim defIdx As Long = ActivePanels(i).defIndex
        Dim def As IndicatorDef = indRegistry.defs(defIdx)
        If def.isPanel = 0 And def.drawOverlay <> 0 Then

            ctx.refHighs      = NULL : ctx.refLows    = NULL : ctx.refOpens      = NULL
            ctx.refTimestamps = NULL : ctx.refCount   = 0    : ctx.refTFMinutes  = 0

            If Len(Trim(def.param2Label)) > 0 Then
                Dim refTF As Long = 0
                Select Case ActivePanels(i).param2
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
                            ActivePanels(i).period, ActivePanels(i).param2, globalOverlayIdx, @ctx, CLng(RSI_CLOSE_BTN), @MA_Colors(0))
                        globalOverlayIdx += 1
                        ctx.refHighs = NULL : ctx.refLows = NULL : ctx.refOpens = NULL
                        ctx.refTimestamps = NULL : ctx.refCount = 0 : ctx.refTFMinutes = 0
                        Continue For
                    End If
                End If
            End If

            ' Indicateur sans TF de référence — appel direct
            def.drawOverlay(g, hDC, @Closes(0), @Opens(0), @Highs(0), @Lows(0), @Volumes(0), @Weekdays(0), totalBars, _
                ActivePanels(i).period, ActivePanels(i).param2, globalOverlayIdx, @ctx, CLng(RSI_CLOSE_BTN), @MA_Colors(0))
            globalOverlayIdx += 1
        End If
    Next

    ' Réinitialiser les champs ref après la boucle overlay
    ctx.refHighs = NULL : ctx.refLows = NULL : ctx.refOpens = NULL : ctx.refCount = 0

    ' Deuxième passe : panels séparés (sous le graphe principal)
    ' ctx.mainChartH inclut RSI_PANEL_MARGIN pour que le cpp n'ait pas à connaître cette constante.
    ' Le cpp calcule : rTop = ctx.mainChartH + panelIndex * (panelH + panelGap)
    ctx.mainChartH = CLng(mainChartH) + RSI_PANEL_MARGIN
    For i As Integer = 0 To ActiveCount - 1
        Dim defIdx As Long = ActivePanels(i).defIndex
        Dim def As IndicatorDef = indRegistry.defs(defIdx)
        If def.isPanel = 1 And def.drawPanel <> 0 Then
            Dim totalPanelCount As Long = CountPanels(defIdx)
            Dim pVMin As Double = 0.0, pVMax As Double = 100.0
            def.drawPanel(g, hDC, @Closes(0), @Opens(0), @Highs(0), @Lows(0), @Volumes(0), @Weekdays(0), totalBars, _
                ActivePanels(i).period, ActivePanels(i).param2, panelIdx, totalPanelCount, _
                @ctx, CLng(RSI_PANEL_H), CLng(RSI_PANEL_GAP), CLng(RSI_CLOSE_BTN), _
                @pVMin, @pVMax)
            ' Mémoriser la géométrie + espace de valeurs pour les trendlines
            Dim pInnerH As Integer = RSI_PANEL_H - 20
            PanelGeoms(PanelGeomCount).rTop           = mainChartH + RSI_PANEL_MARGIN + panelIdx * (RSI_PANEL_H + RSI_PANEL_GAP)
            PanelGeoms(PanelGeomCount).rBottom        = PanelGeoms(PanelGeomCount).rTop + pInnerH
            PanelGeoms(PanelGeomCount).innerH         = pInnerH
            PanelGeoms(PanelGeomCount).vMin           = pVMin
            PanelGeoms(PanelGeomCount).vMax           = pVMax
            PanelGeoms(PanelGeomCount).activePanelIdx = i
            PanelGeomCount += 1
            panelIdx += 1
        End If
    Next

    ' 4. Trendlines — rendu dans le bon canvas selon canvasType
    Dim pL As GpPen Ptr : GdipCreatePen1(&HFF444444, 2.0, UnitPixel, @pL)
    For i As Integer = 0 To UBound(Lines)
        Dim x1 As Single = g_oriX + (Lines(i).bar1 - QChart.ViewStart) * g_stepX + (g_stepX/2)
        Dim y1 As Single = ValueToScreenY(Lines(i).price1, Lines(i).canvasType)
        Dim x2 As Single = g_oriX + (Lines(i).bar2 - QChart.ViewStart) * g_stepX + (g_stepX/2)
        Dim y2 As Single = ValueToScreenY(Lines(i).price2, Lines(i).canvasType)
        GdipDrawLine(g, pL, x1, y1, x2, y2)
    Next
    If isDrawing = 1 Then
        Dim mP As POINT : GetCursorPos(@mP) : ScreenToClient(hWnd, @mP)
        ' Le snap ne s'applique que dans le graphe principal (canvasType=0)
        If tmpCanvasType = 0 Then
            SnapToCandle(mP.x, mP.y)
        Else
            g_snapX = mP.x : g_snapY = mP.y
        End If
        Dim x1snap As Single = g_oriX + (tmpBar - QChart.ViewStart) * g_stepX + (g_stepX/2)
        Dim y1snap As Single = ValueToScreenY(tmpPrice, tmpCanvasType)
        GdipDrawLine(g, pL, x1snap, y1snap, g_snapX, g_snapY)
        Dim pSnap As GpPen Ptr : GdipCreatePen1(&HFF0088FF, 1.5, UnitPixel, @pSnap)
        GdipDrawEllipse(g, pSnap, g_snapX - 5, g_snapY - 5, 10, 10)
        GdipDeletePen(pSnap)
    End If
    GdipDeletePen(pL)

    ' Dessiner les cercles sauvegardés (recalculés en pixels à chaque rendu)
    If UBound(Circles) >= 0 Then
        Dim pC As GpPen Ptr : GdipCreatePen1(&HFF444444, 2.0, UnitPixel, @pC)
        For i As Integer = 0 To UBound(Circles)
            ' Convertir les 3 points bar/price → pixels
            Dim px1 As Single = g_oriX + (Circles(i).bar1 - QChart.ViewStart) * g_stepX + g_stepX * 0.5
            Dim py1 As Single = ValueToScreenY(Circles(i).price1, 0)
            Dim px2 As Single = g_oriX + (Circles(i).bar2 - QChart.ViewStart) * g_stepX + g_stepX * 0.5
            Dim py2 As Single = ValueToScreenY(Circles(i).price2, 0)
            Dim px3 As Single = g_oriX + (Circles(i).bar3 - QChart.ViewStart) * g_stepX + g_stepX * 0.5
            Dim py3 As Single = ValueToScreenY(Circles(i).price3, 0)
            ' Calcul du centre par intersection des médiatrices (algorithme original)
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

    ' Aperçu cercle en cours (points déjà cliqués en pixels courants)
    If currentTool = ID_TOOL_CIRCLE And circleClickNb > 0 Then
        Dim pDot As GpPen Ptr : GdipCreatePen1(&HFF0088FF, 1.5, UnitPixel, @pDot)
        For i As Integer = 1 To circleClickNb
            ' Recalculer position pixel depuis bar/price stockés
            Dim dotX As Single = g_oriX + (circleBar(i) - QChart.ViewStart) * g_stepX + g_stepX * 0.5
            Dim dotY As Single = ValueToScreenY(circlePrice(i), 0)
            GdipDrawEllipse(g, pDot, dotX - 4, dotY - 4, 8, 8)
        Next
        GdipDeletePen(pDot)
    End If

    ' ── Fibonacci Fans ────────────────────────────────────────────────────
    ' Algorithme standard (mode fibofanstandard) :
    '   P1 = pivot, P2 = fin de ligne de base
    '   dx = P2x - P1x  (pixels)
    '   Rayon r : de P1 vers (P2x + dx*ratio, P2y)  → prolongé au bord
    ' Ratios : 23.6=0.618*0.5, 38.2=0.618, 50=1.0, 61.8=1.618, 78.6=1.618²*1.382
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

    Dim chartRightX As Single = g_oriX + (winW - 120 - toolbarW)

    If UBound(FiboFans) >= 0 Then
        For i As Integer = 0 To UBound(FiboFans)
            Dim ffx1 As Single = g_oriX + (FiboFans(i).bar1 - QChart.ViewStart) * g_stepX + g_stepX * 0.5
            Dim ffy1 As Single = ValueToScreenY(FiboFans(i).price1, 0)
            Dim ffx2 As Single = g_oriX + (FiboFans(i).bar2 - QChart.ViewStart) * g_stepX + g_stepX * 0.5
            Dim ffy2 As Single = ValueToScreenY(FiboFans(i).price2, 0)
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
    If currentTool = ID_TOOL_FIBOFAN And fiboFanClickNb = 1 Then
        Dim mPF As POINT : GetCursorPos(@mPF) : ScreenToClient(hWnd, @mPF)
        Dim fpx1 As Single = g_oriX + (fiboFanBar1 - QChart.ViewStart) * g_stepX + g_stepX * 0.5
        Dim fpy1 As Single = ValueToScreenY(fiboFanPrice1, 0)
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
    Dim gannChartRight As Single = g_oriX + (winW - 120 - toolbarW)
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

    For gfPass = 0 To (UBound(GannFans) + 1) + 1
        ' gfPass 0..UBound = fans définitifs, dernier pass = aperçu si actif
        If gfPass <= UBound(GannFans) Then
            gfRenderX1 = g_oriX + (GannFans(gfPass).bar1 - QChart.ViewStart) * g_stepX + g_stepX * 0.5
            gfRenderY1 = ValueToScreenY(GannFans(gfPass).price1, 0)
            gfRenderX2 = g_oriX + (GannFans(gfPass).bar2 - QChart.ViewStart) * g_stepX + g_stepX * 0.5
            gfRenderY2 = ValueToScreenY(GannFans(gfPass).price2, 0)
            gfRenderAlpha = 255
        ElseIf currentTool = ID_TOOL_GANNFAN And gannFanClickNb = 1 Then
            Dim mPG As POINT : GetCursorPos(@mPG) : ScreenToClient(hWnd, @mPG)
            gfRenderX1 = g_oriX + (gannFanBar1 - QChart.ViewStart) * g_stepX + g_stepX * 0.5
            gfRenderY1 = ValueToScreenY(gannFanPrice1, 0)
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

    For frPass = 0 To (UBound(FiboRets) + 1) + 1
        If frPass <= UBound(FiboRets) Then
            frRX1    = g_oriX + (FiboRets(frPass).bar1 - QChart.ViewStart) * g_stepX + g_stepX * 0.5
            frRY1    = ValueToScreenY(FiboRets(frPass).price1, 0)
            frRX2    = g_oriX + (FiboRets(frPass).bar2 - QChart.ViewStart) * g_stepX + g_stepX * 0.5
            frRY2    = ValueToScreenY(FiboRets(frPass).price2, 0)
            frRAlpha = 255
        ElseIf currentTool = ID_TOOL_FIBORET And fiboRetClickNb = 1 Then
            Dim mPFR As POINT : GetCursorPos(@mPFR) : ScreenToClient(hWnd, @mPFR)
            frRX1    = g_oriX + (fiboRetBar1 - QChart.ViewStart) * g_stepX + g_stepX * 0.5
            frRY1    = ValueToScreenY(fiboRetPrice1, 0)
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

    For ggPass = 0 To (UBound(GannGrids) + 1) + 1
        If ggPass <= UBound(GannGrids) Then
            ggRX1    = g_oriX + (GannGrids(ggPass).bar1 - QChart.ViewStart) * g_stepX + g_stepX * 0.5
            ggRY1    = ValueToScreenY(GannGrids(ggPass).price1, 0)
            ggRX2    = g_oriX + (GannGrids(ggPass).bar2 - QChart.ViewStart) * g_stepX + g_stepX * 0.5
            ggRY2    = ValueToScreenY(GannGrids(ggPass).price2, 0)
            ggRAlpha = 255
        ElseIf currentTool = ID_TOOL_GANNGRID And gannGridClickNb = 1 Then
            Dim mPGG As POINT : GetCursorPos(@mPGG) : ScreenToClient(hWnd, @mPGG)
            ggRX1    = g_oriX + (gannGridBar1 - QChart.ViewStart) * g_stepX + g_stepX * 0.5
            ggRY1    = ValueToScreenY(gannGridPrice1, 0)
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

    For ptPass = 0 To (UBound(Pentagrams) + 1) + 1
        If ptPass <= UBound(Pentagrams) Then
            ptRX1    = g_oriX + (Pentagrams(ptPass).bar1 - QChart.ViewStart) * g_stepX + g_stepX * 0.5
            ptRY1    = ValueToScreenY(Pentagrams(ptPass).price1, 0)
            ptRX2    = g_oriX + (Pentagrams(ptPass).bar2 - QChart.ViewStart) * g_stepX + g_stepX * 0.5
            ptRY2    = ValueToScreenY(Pentagrams(ptPass).price2, 0)
            ptRAlpha = 255
        ElseIf currentTool = ID_TOOL_PENTAGRAM And pentaClickNb = 1 Then
            Dim mPPT As POINT : GetCursorPos(@mPPT) : ScreenToClient(hWnd, @mPPT)
            ptRX1    = g_oriX + (pentaBar1 - QChart.ViewStart) * g_stepX + g_stepX * 0.5
            ptRY1    = ValueToScreenY(pentaPrice1, 0)
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

    Dim plChartRight As Single = g_oriX + (winW - 120 - toolbarW)
    Dim plChartLeft  As Single = g_oriX

    Dim As Single plRX1, plRY1, plRX2, plRY2, plRX3, plRY3
    Dim plRAlpha As Integer
    Dim plPass   As Integer

    For plPass = 0 To (UBound(ParaLinesArr) + 1) + 2
        If plPass <= UBound(ParaLinesArr) Then
            plRX1    = g_oriX + (ParaLinesArr(plPass).bar1 - QChart.ViewStart) * g_stepX + g_stepX * 0.5
            plRY1    = ValueToScreenY(ParaLinesArr(plPass).price1, 0)
            plRX2    = g_oriX + (ParaLinesArr(plPass).bar2 - QChart.ViewStart) * g_stepX + g_stepX * 0.5
            plRY2    = ValueToScreenY(ParaLinesArr(plPass).price2, 0)
            plRX3    = g_oriX + (ParaLinesArr(plPass).bar3 - QChart.ViewStart) * g_stepX + g_stepX * 0.5
            plRY3    = ValueToScreenY(ParaLinesArr(plPass).price3, 0)
            plRAlpha = 255
        ElseIf currentTool = ID_TOOL_PARALINES And paraClickNb >= 1 Then
            Dim mPPL As POINT : GetCursorPos(@mPPL) : ScreenToClient(hWnd, @mPPL)
            plRX1    = g_oriX + (paraBar1 - QChart.ViewStart) * g_stepX + g_stepX * 0.5
            plRY1    = ValueToScreenY(paraPrice1, 0)
            If paraClickNb >= 2 Then
                plRX2 = g_oriX + (paraBar2 - QChart.ViewStart) * g_stepX + g_stepX * 0.5
                plRY2 = ValueToScreenY(paraPrice2, 0)
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

    If currentTool = ID_TOOL_CROSSHAIR And crosshairX >= 0 And QChart.IsLoaded Then
        Dim cx As Single = crosshairX
        Dim cy As Single = crosshairY

        Dim chartLeft  As Single = g_oriX
        Dim chartRight As Single = g_oriX + lenX
        Dim chartTop   As Single = ZOOM_BAR_H + 40
        Dim chartBot   As Single = g_oriY

        ' Barre pointée par X (commune à tous les canvas)
        Dim barUnder As Integer = QChart.ViewStart + CInt((cx - g_oriX) / g_stepX)
        If barUnder < QChart.ViewStart Then barUnder = QChart.ViewStart
        If barUnder > lastIdx Then barUnder = lastIdx

        If cx >= chartLeft And cx <= chartRight Then

            ' Créer le stylo pointillé une seule fois pour tous les canvas
            Dim pCross As GpPen Ptr
            GdipCreatePen1(&HFF555555, 1.0, UnitPixel, @pCross)
            GdipSetPenDashStyle(pCross, 2)   ' DashStyleDot

            SetBkMode(hDC, TRANSPARENT)

            ' ── Graphe principal ─────────────────────────────────────────────
            If cy >= chartTop And cy <= chartBot Then
                ' Ligne horizontale dans le graphe principal
                GdipDrawLine(g, pCross, chartLeft, cy, chartRight, cy)

                ' Label prix sur la droite
                Dim crossPrice As Double = g_vMin + (g_oriY - cy) / g_scaleY
                Dim priceStr As String
                Dim priceRange As Double = g_vMax - g_vMin
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

            ' Ligne verticale couvrant le graphe principal
            GdipDrawLine(g, pCross, cx, chartTop, cx, chartBot)

            ' ── Panels séparés ───────────────────────────────────────────────
            For pi As Integer = 0 To PanelGeomCount - 1
                Dim pTop    As Single = PanelGeoms(pi).rTop
                Dim pBot    As Single = PanelGeoms(pi).rBottom
                Dim pInnerH As Integer = PanelGeoms(pi).innerH
                Dim pVMin   As Double  = PanelGeoms(pi).vMin
                Dim pVMax   As Double  = PanelGeoms(pi).vMax

                ' Ligne verticale dans ce panel
                GdipDrawLine(g, pCross, cx, pTop, cx, pBot)

                ' Valeur Y sous le curseur dans ce panel
                ' Si le curseur est dans ce panel, utiliser cy ; sinon interpoler depuis la barre
                Dim panelCy As Single
                If cy >= pTop And cy <= pBot Then
                    panelCy = cy
                Else
                    ' Pas de ligne horizontale si la souris n'est pas dans ce panel
                    Continue For
                End If

                ' Ligne horizontale dans ce panel
                GdipDrawLine(g, pCross, chartLeft, panelCy, chartRight, panelCy)

                ' Valeur dans l'espace du panel
                Dim panelVal As Double = 0
                If pInnerH > 0 And pVMax <> pVMin Then
                    panelVal = pVMin + (pBot - panelCy) * (pVMax - pVMin) / pInnerH
                End If

                ' Label valeur sur la droite
                Dim valStr As String
                Dim valRange As Double = pVMax - pVMin
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

            ' ── Label Date/Heure (sous le dernier panel ou sous le graphe) ───
            Dim dtLbl As String = ""
            If barUnder >= 0 And barUnder <= UBound(QChart.History) Then
                Dim dtS As String = Trim(QChart.History(barUnder).Dt)
                Dim tmS As String = Trim(QChart.History(barUnder).Tm)
                If Len(tmS) >= 4 And tmS <> "00:00" Then
                    dtLbl = dtS & " " & tmS
                Else
                    dtLbl = dtS
                End If
            End If

            If Len(dtLbl) > 0 Then
                ' Positionner sous le canvas le plus bas (dernier panel ou graphe principal)
                Dim dtBaseY As Single = chartBot
                If PanelGeomCount > 0 Then
                    dtBaseY = PanelGeoms(PanelGeomCount - 1).rBottom
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
Function ParamsDlgProc(hWnd As HWND, uMsg As UINT, wParam As WPARAM, lParam As LPARAM) As LRESULT
    Static hLbl  As HWND
    Static hEdit As HWND
    Static hOK   As HWND

    Select Case uMsg
        Case WM_CREATE
            ' Label
            hLbl = CreateWindowEx(0, "STATIC", "Nouvelle periode :", _
                WS_CHILD Or WS_VISIBLE, _
                10, 14, 120, 20, hWnd, NULL, GetModuleHandle(NULL), NULL)
            ' EditBox numérique pré-rempli avec la période actuelle
            hEdit = CreateWindowEx(WS_EX_CLIENTEDGE, "EDIT", "", _
                WS_CHILD Or WS_VISIBLE Or ES_NUMBER, _
                135, 12, 60, 22, hWnd, Cast(HMENU, ID_EDT_PERIOD), _
                GetModuleHandle(NULL), NULL)
            SendMessage(hEdit, EM_SETLIMITTEXT, 4, 0)
            If rightClickedOverlayIdx >= 0 And rightClickedOverlayIdx < ActiveCount Then
                Dim curPer As ZString * 8
                curPer = Str(ActivePanels(rightClickedOverlayIdx).period)
                SetWindowText(hEdit, @curPer)
                SendMessage(hEdit, EM_SETSEL, 0, -1)   ' sélectionner tout
            End If
            ' Bouton OK
            hOK = CreateWindowEx(0, "BUTTON", "OK", _
                WS_CHILD Or WS_VISIBLE Or BS_DEFPUSHBUTTON, _
                75, 46, 70, 26, hWnd, Cast(HMENU, IDOK), _
                GetModuleHandle(NULL), NULL)
            SetFocus(hEdit)

        Case WM_COMMAND
            Dim cmdId As Integer = Loword(wParam)
            Dim cmdEvt As Integer = Hiword(wParam)
            ' OK cliqué, ou Entrée dans l'EditBox (EN_DEFAULT = notification 1)
            If cmdId = IDOK Or (cmdId = ID_EDT_PERIOD And cmdEvt = 1) Then
                Dim eBuf As ZString * 8
                GetWindowText(hEdit, @eBuf, 8)
                Dim newPer As Long = Val(eBuf)
                If newPer < 2   Then newPer = 2
                If newPer > 999 Then newPer = 999
                If rightClickedOverlayIdx >= 0 And rightClickedOverlayIdx < ActiveCount Then
                    ActivePanels(rightClickedOverlayIdx).period = newPer
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
    Static hList      As HWND
    Static hLblParams As HWND
    Static hLbl1      As HWND
    Static hEdt1      As HWND
    Static hLbl2      As HWND
    Static hEdt2      As HWND
    Static hBtnApply  As HWND

    Select Case uMsg
        Case WM_CREATE
            hList = CreateWindowEx(WS_EX_CLIENTEDGE, "LISTBOX", "", _
                WS_CHILD Or WS_VISIBLE Or WS_VSCROLL Or LBS_NOTIFY, _
                10, 10, 200, 100, hWnd, Cast(HMENU, ID_LST_INDICATORS), _
                GetModuleHandle(NULL), NULL)
            ' Peupler la liste depuis le registre
            For i As Integer = 0 To indRegistry.count - 1
                Dim nm As String = indRegistry.defs(i).name
                SendMessage(hList, LB_ADDSTRING, 0, Cast(LPARAM, StrPtr(nm)))
            Next
            hLblParams = CreateWindowEx(0, "STATIC", "-- Parametres --", _
                WS_CHILD Or WS_VISIBLE Or SS_CENTER, 10, 120, 200, 16, hWnd, _
                Cast(HMENU, ID_LBL_PARAMS), GetModuleHandle(NULL), NULL)
            hLbl1 = CreateWindowEx(0, "STATIC", "Periode :", _
                WS_CHILD Or WS_VISIBLE, 10, 144, 80, 20, hWnd, _
                Cast(HMENU, ID_LBL_PERIOD), GetModuleHandle(NULL), NULL)
            hEdt1 = CreateWindowEx(WS_EX_CLIENTEDGE, "EDIT", "20", _
                WS_CHILD Or WS_VISIBLE Or ES_NUMBER, 95, 142, 60, 22, hWnd, _
                Cast(HMENU, ID_EDT_PERIOD), GetModuleHandle(NULL), NULL)
            SendMessage(hEdt1, EM_SETLIMITTEXT, 4, 0)
            hLbl2 = CreateWindowEx(0, "STATIC", "", WS_CHILD, _
                10, 172, 80, 20, hWnd, Cast(HMENU, ID_LBL_PERIOD2), GetModuleHandle(NULL), NULL)
            hEdt2 = CreateWindowEx(WS_EX_CLIENTEDGE, "EDIT", "", WS_CHILD Or ES_NUMBER, _
                95, 170, 60, 22, hWnd, Cast(HMENU, ID_EDT_PERIOD2), GetModuleHandle(NULL), NULL)
            hBtnApply = CreateWindowEx(0, "BUTTON", "Appliquer", _
                WS_CHILD Or WS_VISIBLE, 45, 202, 130, 30, hWnd, _
                Cast(HMENU, ID_BTN_APPLY), GetModuleHandle(NULL), NULL)
            SendMessage(hList, LB_SETCURSEL, 0, 0)
            If indRegistry.count > 0 Then
                Dim defPer As Long = indRegistry.defs(0).defaultPeriod
                Dim buf0 As ZString * 8 : buf0 = Str(defPer)
                SetWindowText(hEdt1, @buf0)
                Dim lbl0 As String = "Periode " & indRegistry.defs(0).labelPrefix & " :"
                Dim zlbl0 As ZString * 32 : zlbl0 = lbl0
                SetWindowText(hLbl1, @zlbl0)
                ' Param2 : afficher si défini
                Dim p2lbl0 As String = Trim(indRegistry.defs(0).param2Label)
                If Len(p2lbl0) > 0 Then
                    Dim zp2lbl0 As ZString * 32 : zp2lbl0 = p2lbl0
                    SetWindowText(hLbl2, @zp2lbl0)
                    Dim buf2 As ZString * 8 : buf2 = Str(indRegistry.defs(0).defaultParam2)
                    SetWindowText(hEdt2, @buf2)
                    ShowWindow(hLbl2, SW_SHOW)
                    ShowWindow(hEdt2, SW_SHOW)
                Else
                    ShowWindow(hLbl2, SW_HIDE)
                    ShowWindow(hEdt2, SW_HIDE)
                End If
            End If

        Case WM_COMMAND
            Dim cmdId  As Integer = Loword(wParam)
            Dim cmdEvt As Integer = Hiword(wParam)

            If cmdId = ID_LST_INDICATORS And cmdEvt = LBN_SELCHANGE Then
                Dim selIdx As Integer = SendMessage(hList, LB_GETCURSEL, 0, 0)
                If selIdx >= 0 And selIdx < indRegistry.count Then
                    ' Paramètre 1 (période)
                    Dim defPer As Long = indRegistry.defs(selIdx).defaultPeriod
                    Dim buf As ZString * 8 : buf = Str(defPer)
                    SetWindowText(hEdt1, @buf)
                    Dim lbl As String = "Periode " & indRegistry.defs(selIdx).labelPrefix & " :"
                    Dim zlbl As ZString * 32 : zlbl = lbl
                    SetWindowText(hLbl1, @zlbl)
                    ' Paramètre 2 : visible seulement si param2Label est renseigné
                    Dim p2lbl As String = Trim(indRegistry.defs(selIdx).param2Label)
                    If Len(p2lbl) > 0 Then
                        Dim zp2lbl As ZString * 32 : zp2lbl = p2lbl
                        SetWindowText(hLbl2, @zp2lbl)
                        Dim buf2 As ZString * 8 : buf2 = Str(indRegistry.defs(selIdx).defaultParam2)
                        SetWindowText(hEdt2, @buf2)
                        ShowWindow(hLbl2, SW_SHOW)
                        ShowWindow(hEdt2, SW_SHOW)
                    Else
                        ShowWindow(hLbl2, SW_HIDE)
                        ShowWindow(hEdt2, SW_HIDE)
                    End If
                End If
            End If

            If cmdId = ID_BTN_APPLY Then
                Dim selIdx2 As Integer = SendMessage(hList, LB_GETCURSEL, 0, 0)
                If selIdx2 = LB_ERR Or selIdx2 >= indRegistry.count Then Return 0
                ' Lire période
                Dim eBuf As ZString * 8
                GetWindowText(hEdt1, @eBuf, 8)
                Dim per As Long = Val(eBuf)
                If per < 1   Then per = 1
                If per > 999 Then per = 999
                ' Lire param2 si visible
                Dim p2 As Long = 0
                Dim p2lbl2 As String = Trim(indRegistry.defs(selIdx2).param2Label)
                If Len(p2lbl2) > 0 Then
                    Dim eBuf2 As ZString * 8
                    GetWindowText(hEdt2, @eBuf2, 8)
                    p2 = Val(eBuf2)
                End If
                ActiveCount += 1
                ReDim Preserve ActivePanels(ActiveCount - 1)
                ActivePanels(ActiveCount - 1).defIndex = selIdx2
                ActivePanels(ActiveCount - 1).period   = per
                ActivePanels(ActiveCount - 1).param2   = p2
                ForceRedraw(GetWindow(hWnd, GW_OWNER))
                DestroyWindow(hWnd)
            End If

        Case WM_CLOSE : DestroyWindow(hWnd)
    End Select
    Return DefWindowProc(hWnd, uMsg, wParam, lParam)
End Function

Function WndProc(hWnd As HWND, uMsg As UINT, wParam As WPARAM, lParam As LPARAM) As LRESULT
    Select Case uMsg
        Case WM_CREATE
            Dim hM As HMENU = CreateMenu(), hF As HMENU = CreatePopupMenu()
            AppendMenu(hF, MF_STRING, ID_MENU_OPEN, "&Open CSV")
            AppendMenu(hM, MF_POPUP, Cast(UINT_PTR, hF), "&File") : SetMenu(hWnd, hM)
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
            Return 0

        Case WM_COMMAND
            Dim id As Integer = Loword(wParam)
            If id = ID_MENU_OPEN Then
                Dim f As String = File_GetName(hWnd) : If f <> "" Then LoadCSV(f, hWnd)
            ElseIf id >= ID_TOOL_SELECT And id <= ID_TOOL_PARALINES Then
                currentTool = id : isDrawing = 0 : circleClickNb = 0 : fiboFanClickNb = 0 : gannFanClickNb = 0 : fiboRetClickNb = 0 : gannGridClickNb = 0 : pentaClickNb = 0 : paraClickNb = 0
                ' Réinitialiser le crosshair quand on change d'outil
                If id <> ID_TOOL_CROSSHAIR Then
                    crosshairX = -1 : crosshairY = -1
                End If
            ElseIf id = ID_BTN_INDICATORS Then
                Dim wc As WNDCLASS : wc.lpfnWndProc = @IndicatorsDlgProc : wc.hInstance = GetModuleHandle(NULL) : wc.hCursor = LoadCursor(NULL, IDC_ARROW) : wc.hbrBackground = GetStockObject(WHITE_BRUSH) : wc.lpszClassName = StrPtr("IndWin")
                RegisterClass(@wc) : CreateWindowEx(0, "IndWin", "Technicals", WS_OVERLAPPED Or WS_CAPTION Or WS_SYSMENU Or WS_VISIBLE, CW_USEDEFAULT, CW_USEDEFAULT, 240, 280, hWnd, NULL, GetModuleHandle(NULL), NULL)

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
                If QChart.IsLoaded = 0 Then Return 0
                Dim totalH As Integer = UBound(QChart.History) + 1
                ' Centre visible actuel (en index de barre)
                Dim centerBar As Integer = QChart.ViewStart + QChart.ViewCount \ 2
                ' Nouveau ViewCount
                Dim newCount As Integer = QChart.ViewCount
                If id = ID_BTN_ZOOM_IN Then
                    newCount = newCount - ZOOM_STEP
                Else
                    newCount = newCount + ZOOM_STEP
                End If
                If newCount < ZOOM_MIN_BARS Then newCount = ZOOM_MIN_BARS
                If newCount > ZOOM_MAX_BARS Then newCount = ZOOM_MAX_BARS
                If newCount > totalH Then newCount = totalH
                QChart.ViewCount = newCount
                ' Recentrer sur la même barre
                Dim newStart As Integer = centerBar - newCount \ 2
                If newStart < 0 Then newStart = 0
                Dim maxStart As Integer = totalH - newCount
                If maxStart < 0 Then maxStart = 0
                If newStart > maxStart Then newStart = maxStart
                QChart.ViewStart = newStart
                SetScrollRange(hScroll, SB_CTL, 0, maxStart, TRUE)
                SetScrollPos(hScroll, SB_CTL, newStart, TRUE)
                ForceRedraw(hWnd)
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
            Dim globalOverlayHitIdx As Long = 0   ' miroir de globalOverlayIdx du rendu
            For i As Integer = 0 To ActiveCount - 1
                Dim defIdx As Long = ActivePanels(i).defIndex
                Dim def As IndicatorDef = indRegistry.defs(defIdx)
                If def.isPanel = 0 Then
                    ' Overlay : bouton X — position Y identique à celle du rendu
                    Dim rsiAreaH2 As Long = panelCount2 * (RSI_PANEL_H + RSI_PANEL_GAP)
                    Dim lenX2 As Single = winW - 120 - toolbarW
                    Dim maPer2 As Long = ActivePanels(i).period
                    Dim maLbl2 As String = def.labelPrefix & "(" & maPer2 & ")"
                    Dim lblX2 As Long = g_oriX + 4
                    Dim lblY2 As Long = ZOOM_BAR_H + 14 + globalOverlayHitIdx * (RSI_CLOSE_BTN + 4)
                    Dim bxMA As Single = lblX2 + Len(maLbl2) * 7 + 3
                    Dim byMA As Single = lblY2 - 1
                    If mx >= bxMA And mx <= bxMA + RSI_CLOSE_BTN And _
                       my >= byMA And my <= byMA + RSI_CLOSE_BTN Then
                        For j As Integer = i To ActiveCount - 2
                            ActivePanels(j) = ActivePanels(j + 1)
                        Next
                        ActiveCount -= 1
                        If ActiveCount = 0 Then ReDim ActivePanels(-1) Else ReDim Preserve ActivePanels(ActiveCount - 1)
                        ForceRedraw(hWnd) : Return 0
                    End If
                    globalOverlayHitIdx += 1
                Else
                    ' Panel séparé : bouton X coin supérieur droit
                    Dim rsiAreaH3 As Long = panelCount2 * (RSI_PANEL_H + RSI_PANEL_GAP)
                    Dim mainH3 As Long = (winH - SCROLL_H) - rsiAreaH3 - 40 - ZOOM_BAR_H
                    Dim lenX3 As Single = winW - 120 - toolbarW
                    Dim rTop3 As Long = mainH3 + RSI_PANEL_MARGIN + panelHitIdx * (RSI_PANEL_H + RSI_PANEL_GAP)
                    Dim bxRSI As Single = g_oriX + lenX3 - RSI_CLOSE_BTN - 2
                    Dim byRSI As Single = rTop3 + 2
                    If mx >= bxRSI And mx <= bxRSI + RSI_CLOSE_BTN And _
                       my >= byRSI And my <= byRSI + RSI_CLOSE_BTN Then
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
            If QChart.IsLoaded = 0 Then Return 0
            Dim delta As Short = HiWord(wParam)
            Dim cp As Integer = QChart.ViewStart
            If delta < 0 Then cp += 5 Else cp -= 5
            Dim ms As Integer = (UBound(QChart.History) + 1) - QChart.ViewCount
            If cp < 0 Then cp = 0
            If cp > ms Then cp = ms
            QChart.ViewStart = cp
            SetScrollPos(hScroll, SB_CTL, cp, TRUE)
            ForceRedraw(hWnd)
            Return 0

        Case WM_HSCROLL
            If QChart.IsLoaded = 0 Then Exit Select
            Dim si As SCROLLINFO : si.cbSize = SizeOf(SCROLLINFO) : si.fMask = SIF_ALL : GetScrollInfo(hScroll, SB_CTL, @si)
            Dim cp As Integer = si.nPos
            Select Case Loword(wParam)
                Case SB_THUMBTRACK, SB_THUMBPOSITION : cp = si.nTrackPos
                Case SB_LINELEFT : cp -= 1
                Case SB_LINERIGHT : cp += 1
            End Select
            Dim ms As Integer = (UBound(QChart.History) + 1) - QChart.ViewCount
            If cp < 0 Then cp = 0 : If cp > ms Then cp = ms
            QChart.ViewStart = cp : SetScrollPos(hScroll, SB_CTL, cp, TRUE) : ForceRedraw(hWnd)

        Case WM_SIZE
            winW = Loword(lParam) : winH = Hiword(lParam)
            ' Récupère la largeur réelle que la toolbar veut occuper
            Dim tbSize As SIZE
            SendMessage(hToolbar, TB_GETMAXSIZE, 0, Cast(LPARAM, @tbSize))
            If tbSize.cx > 0 Then toolbarW = tbSize.cx
            MoveWindow(hToolbar, 0, 0, toolbarW, winH - 80, TRUE)
            MoveWindow(hBtnIndicators, 0, winH - 75, toolbarW, 30, TRUE)
            ' Barre de zoom : commence au bord droit de la toolbar verticale, hauteur fixe
            MoveWindow(hZoomBar, toolbarW, 0, winW - toolbarW, ZOOM_BAR_H, TRUE)
            MoveWindow(hScroll, toolbarW + 65, winH - SCROLL_H, winW - 130 - toolbarW, 20, TRUE)
            ForceRedraw(hWnd)

        Case WM_ERASEBKGND
            Return 1

        Case WM_PAINT
            Dim ps As PAINTSTRUCT
            Dim hDC As HDC = BeginPaint(hWnd, @ps)
            Dim hMemDC  As HDC     = CreateCompatibleDC(hDC)
            Dim hBitmap As HBITMAP = CreateCompatibleBitmap(hDC, winW, winH - SCROLL_H)
            Dim hOld    As HBITMAP = SelectObject(hMemDC, hBitmap)
            RenderChartGDIPlus(hWnd, hMemDC, winW, winH - SCROLL_H)
            BitBlt(hDC, 0, 0, winW, winH - SCROLL_H, hMemDC, 0, 0, SRCCOPY)
            SelectObject(hMemDC, hOld)
            DeleteObject(hBitmap)
            DeleteDC(hMemDC)
            EndPaint(hWnd, @ps)
            Return 0

        Case WM_DESTROY : PostQuitMessage(0) : Return 0
    End Select
    Return DefWindowProc(hWnd, uMsg, wParam, lParam)
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
