#!/bin/bash
# Artwork (icon/Crocini-art.png, generato con Codex) → icon/Crocini-1024.png → Resources/AppIcon.icns
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
swift Scripts/compose_icon.swift icon/Crocini-art.png icon/Crocini-1024.png
rm -rf AppIcon.iconset && mkdir AppIcon.iconset
for s in 16 32 128 256 512; do
    sips -z $s $s icon/Crocini-1024.png --out AppIcon.iconset/icon_${s}x${s}.png >/dev/null
    sips -z $((s*2)) $((s*2)) icon/Crocini-1024.png --out AppIcon.iconset/icon_${s}x${s}@2x.png >/dev/null
done
iconutil -c icns AppIcon.iconset -o Resources/AppIcon.icns
echo "==> Resources/AppIcon.icns"
