#!/bin/bash
# Rebuild the Ruffle-compatible Ninja Saga client from the original AIR SWF.
#
#  1. Neutralise the AIR-only flash.filesystem.* class references so Ruffle's
#     AVM2 verifier can load the client (Error #1014 otherwise).
#  2. Replace id.ninjasage.Util.url() so asset paths resolve against the local
#     HTTP server instead of AIR's File.applicationDirectory (which Ruffle
#     does not implement).
#
# Requirements: python3 + FFDec (tools/ffdec) + Java.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ORIG="$ROOT/ns-server/Custom Client/NS Custom Client V1/NinjaSage.swf"
FFDEC="$ROOT/tools/ffdec/FFDec.app/Contents/Resources/ffdec.jar"
OUT="$ROOT/runtime/NinjaSage_patched3.swf"
TMP="$ROOT/runtime/NinjaSage_stage1.swf"

[ -f "$ORIG" ] || { echo "No encuentro el cliente original: $ORIG"; exit 1; }
[ -f "$FFDEC" ] || { echo "No encuentro FFDec: $FFDEC"; exit 1; }

echo "[1/2] Quitando referencias a flash.filesystem…"
python3 "$ROOT/tools/patch_air_stubs.py" "$ORIG" "$TMP"

echo "[2/2] Recompilando id.ninjasage.Util.url…"
java -jar "$FFDEC" -air -replace "$TMP" "$OUT" id.ninjasage.Util "$ROOT/patches/Util_fixed.as"

rm -f "$TMP"
echo "OK -> $OUT"
