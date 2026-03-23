@echo off
setlocal enabledelayedexpansion
echo === Build QChart Pro ===

rem ── Etapes 1 et 2 : compilation incrementale + generation registry (Python) ─
.\python-3.13.12-embed-amd64\python gen_registry.py
if errorlevel 1 goto error

rem ── Lire la liste des .o generee par Python ──────────────────────────────────
set /p OBJS=<_objs.txt
del _objs.txt

rem ── Etape 3 : lier avec FreeBASIC ────────────────────────────────────────────
echo [3] Liaison FreeBASIC...
fbc64 -s gui QChartist2.bas %OBJS%
if errorlevel 1 goto error

echo.
echo === Build reussi : QChartist2.exe ===
goto end

:error
echo.
echo === ERREUR build echoue ===
exit /b 1

:end
endlocal
