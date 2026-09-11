#!/bin/bash
set -euo pipefail

if [ ! -f ZZFilterPlugin.dylib ]; then
  echo "ZZFilterPlugin.dylib not found"
  exit 1
fi

file ZZFilterPlugin.dylib
lipo -info ZZFilterPlugin.dylib
echo "=== Overlay symbols ==="
nm -gU ZZFilterPlugin.dylib | grep -E \
  'ZZOverlayController|ZZOverlayBootstrap|ZZFilterMakeSessionConfiguration|ZZFilterSetEnabled|ZZFilterSetTextRange|ZZFilterSetVersionRange' || true
echo "=== SHA-256 ==="
shasum -a 256 ZZFilterPlugin.dylib
