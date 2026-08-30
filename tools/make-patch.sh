#!/usr/bin/env bash
# Build an update pack containing only the files changed since the shipped base.
# Usage: tools/make-patch.sh            -> patches/update.pck
# Rebase (new full download) with tools/make-base.sh when project.godot/autoloads change
# or when the patch grows past ~20 MB.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-$HOME/.local/bin/godot}"
[ -f base/RangeDay2.pck ] || { echo "base/RangeDay2.pck missing - run tools/make-base.sh first"; exit 1; }
mkdir -p patches
"$GODOT" --headless --path . --export-patch "Windows Desktop" patches/update.pck --patches "$PWD/base/RangeDay2.pck" > /tmp/make-patch.log 2>&1
python3 - <<'PY'
import struct
d=open('patches/update.pck','rb').read()
magic,ver=struct.unpack('<4sI',d[:8]); assert magic==b'GDPC', magic
off=24; file_base=struct.unpack('<Q',d[off:off+8])[0]; off+=8
dir_off=struct.unpack('<Q',d[off:off+8])[0] if ver>=3 else 0
if ver>=3: off=dir_off
else: off+=16*4
n=struct.unpack('<I',d[off:off+4])[0]; off+=4
print(f"patches/update.pck: {len(d)/1e6:.2f} MB, {n} files")
for i in range(n):
    l=struct.unpack('<I',d[off:off+4])[0]; off+=4; name=d[off:off+l].rstrip(b'\0').decode(); off+=l
    o,sz=struct.unpack('<QQ',d[off:off+16]); off+=16+16+4
    print(f"  {name} ({sz} B)")
PY
