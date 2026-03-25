@echo off
if exist curl.exe (set CURL=curl.exe) else (set CURL=curl)
%CURL% -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" --connect-timeout 30 -m 60 -k -o yf1.txt "https://query1.finance.yahoo.com/v8/finance/chart/GC=F?interval=1h&period1=1767225600&period2=1774483200"
echo 0 > isbusy.txt
