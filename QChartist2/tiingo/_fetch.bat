@echo off
if exist curl.exe set CURL=curl.exe
if not exist curl.exe set CURL=curl
%CURL% --version >nul 2>&1
if %errorlevel% equ 0 goto USE_CURL
:USE_POWERSHELL
powershell -Command "(New-Object Net.WebClient).DownloadFile('https://api.tiingo.com/tiingo/crypto/prices?tickers=TAOUSDT&startDate=2025-01-01&resampleFreq=1440min&token=', 't1.txt')"
goto DONE
:USE_CURL
%CURL% --connect-timeout 30 -m 120 -k -H "Authorization: Token " -o t1.txt "https://api.tiingo.com/tiingo/crypto/prices?tickers=TAOUSDT&startDate=2025-01-01&resampleFreq=1440min"
:DONE
echo 0 > isbusy.txt
