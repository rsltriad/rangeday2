#!/usr/bin/env bash
# Full rebuild: exe + pck, zipped and split into dist/ parts (<15 MB each for jsDelivr).
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-$HOME/.local/bin/godot}"
rm -f build/RangeDay2.exe build/RangeDay2.pck
"$GODOT" --headless --path . --export-release "Windows Desktop" build/RangeDay2.exe > /tmp/make-base.log 2>&1
mkdir -p base && cp build/RangeDay2.pck base/RangeDay2.pck
python3 - <<'PY'
import zipfile
with zipfile.ZipFile('RangeDay2.zip','w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
    z.write('build/RangeDay2.exe','RangeDay2.exe'); z.write('build/RangeDay2.pck','RangeDay2.pck')
PY
rm -f dist/RangeDay2.zip.part* patches/update.pck
N=$(( ($(stat -c%s RangeDay2.zip) + 15000000 - 1) / 15000000 ))
split -n "$N" -d -a 2 RangeDay2.zip dist/RangeDay2.zip.part
mkdir -p ~/public-dl && cp RangeDay2.zip ~/public-dl/ && rm -f ~/public-dl/RangeDay2.zip.part* && cp dist/RangeDay2.zip.part* ~/public-dl/
rm RangeDay2.zip; ls -la dist/
