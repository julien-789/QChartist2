"""
yf_parse.py - Parse Yahoo Finance JSON (yf1.txt) vers CSV
Usage: python yf_parse.py <input_json> <output_csv>
"""
import sys, json, datetime

if len(sys.argv) < 3:
    sys.exit(1)

json_path = sys.argv[1]
csv_path  = sys.argv[2]

try:
    with open(json_path, encoding='utf-8') as f:
        data = json.load(f)
except Exception as e:
    sys.exit(1)

try:
    r  = data['chart']['result'][0]
    ts = r['timestamp']
    q  = r['indicators']['quote'][0]
except Exception:
    sys.exit(1)

opens   = q.get('open',   [None]*len(ts))
highs   = q.get('high',   [None]*len(ts))
lows    = q.get('low',    [None]*len(ts))
closes  = q.get('close',  [None]*len(ts))
volumes = q.get('volume', [0]   *len(ts))

# Patcher les None : utiliser la valeur suivante non-None, sinon open
for i in range(len(ts)):
    if closes[i] is None:
        nxt = next((closes[j] for j in range(i+1,len(ts)) if closes[j] is not None), opens[i])
        closes[i] = nxt
    if opens[i]   is None: opens[i]   = closes[i]
    if highs[i]   is None: highs[i]   = closes[i]
    if lows[i]    is None: lows[i]    = closes[i]
    if volumes[i] is None: volumes[i] = 0

with open(csv_path, 'w', newline='') as f:
    for i in range(len(ts)):
        dt = datetime.datetime.utcfromtimestamp(ts[i])
        f.write(f"{dt.strftime('%Y-%m-%d')},{dt.strftime('%H:%M')},{opens[i]},{highs[i]},{lows[i]},{closes[i]},{volumes[i]}\n")

sys.exit(0)
