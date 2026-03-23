#!/usr/bin/env python3
"""
gen_registry.py
- Scanne indicators/*.cpp pour trouver les marqueurs //QCHART_REGISTER:
- Genere indicators_registry.bas
- Compile incrementalement les .cpp dont le .o est absent ou perime
"""
import os, sys, glob, subprocess

script_dir = os.path.dirname(os.path.abspath(__file__))
indicators_dir = os.path.join(script_dir, "indicators")
cpp_files = sorted(glob.glob(os.path.join(indicators_dir, "*.cpp")))

GXX      = os.path.join(script_dir,
    r"winlibs-x86_64-posix-seh-gcc-15.2.0-mingw-w64msvcrt-13.0.0-r1"
    r"\mingw64\bin\g++.exe")
GXXFLAGS = ["-m64", "-O2", "-std=c++17"]

# Fichiers headers dont le changement force la recompilation de tous les .cpp
COMMON_HEADERS = [
    os.path.join(indicators_dir, "indicator_api.h"),
    os.path.join(indicators_dir, "chartctx.h"),
]

def mtime(path):
    try:    return os.path.getmtime(path)
    except: return 0.0

def needs_rebuild(cpp_path, obj_path):
    if not os.path.exists(obj_path):
        return True
    obj_t = mtime(obj_path)
    if mtime(cpp_path) > obj_t:
        return True
    for h in COMMON_HEADERS:
        if mtime(h) > obj_t:
            return True
    return False

# ── Etape 1 : compilation incrementale ───────────────────────────────────────
print("[1] Compilation des indicateurs (incrementale)...")
objs = []
error = False
for cpp in cpp_files:
    name = os.path.splitext(os.path.basename(cpp))[0]
    obj  = os.path.join(script_dir, name + ".o")
    objs.append(obj)
    if needs_rebuild(cpp, obj):
        print(f"    [compile] {os.path.relpath(cpp)}")
        cmd = [GXX] + GXXFLAGS + ["-c", cpp, "-o", obj, f"-I{indicators_dir}"]
        ret = subprocess.run(cmd)
        if ret.returncode != 0:
            print(f"ERREUR : {cpp}")
            error = True
    else:
        print(f"    [  skip ] {os.path.relpath(cpp)}")

if error:
    sys.exit(1)

# ── Etape 2 : generer indicators_registry.bas ────────────────────────────────
print("[2] Generation de indicators_registry.bas...")
funcs = []
for path in cpp_files:
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            line = line.strip()
            if line.startswith("//QCHART_REGISTER:"):
                name = line.split(":", 1)[1].strip()
                if name:
                    funcs.append(name)

out = []
out.append("' indicators_registry.bas - GENERE AUTOMATIQUEMENT")
out.append("' Ne pas modifier manuellement.")
out.append("")
out.append('Extern "C"')
for fn in funcs:
    out.append(f'    Declare Sub {fn} Alias "{fn}" (reg As Any Ptr)')
out.append("End Extern")
out.append("")
out.append("Sub RegisterAllIndicators(reg As Any Ptr)")
for fn in funcs:
    out.append(f"    {fn}(reg)")
out.append("End Sub")

registry_path = os.path.join(script_dir, "indicators_registry.bas")
with open(registry_path, "w", encoding="utf-8") as f:
    f.write("\n".join(out) + "\n")

print(f"    Indicateurs detectes ({len(funcs)}) :")
for fn in funcs:
    print(f"      - {fn}")
if not funcs:
    print("    ATTENTION : aucun indicateur trouve !")
    sys.exit(1)

# ── Etape 3 : afficher la liste des .o pour build.bat ────────────────────────
# Ecrire les .o dans un fichier temporaire que build.bat lira
objs_file = os.path.join(script_dir, "_objs.txt")
with open(objs_file, "w") as f:
    f.write(" ".join(f'"{o}"' for o in objs))
