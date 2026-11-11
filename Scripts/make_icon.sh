#!/bin/bash
# Artwork (icon/Crocini-art.png, generato con Codex) → crocini ricolorati → icon/Crocini-1024.png → Resources/AppIcon.icns
# I segni di taglio dell'artwork sono neri: sul magenta si vedevano poco, quindi vengono ricolorati (giallo di default).
# Uso: MARK_COLOR=FFFFFF ./Scripts/make_icon.sh   (RRGGBB)
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
MARK_COLOR="${MARK_COLOR:-FFF200}"
swift Scripts/recolor_marks.swift icon/Crocini-art.png icon/Crocini-art-marks.png "$MARK_COLOR"
swift Scripts/compose_icon.swift icon/Crocini-art-marks.png icon/Crocini-1024.png
rm -rf AppIcon.iconset && mkdir AppIcon.iconset
for s in 16 32 128 256 512; do
    sips -z $s $s icon/Crocini-1024.png --out AppIcon.iconset/icon_${s}x${s}.png >/dev/null
    sips -z $((s*2)) $((s*2)) icon/Crocini-1024.png --out AppIcon.iconset/icon_${s}x${s}@2x.png >/dev/null
done
iconutil -c icns AppIcon.iconset -o Resources/AppIcon.icns
echo "==> Resources/AppIcon.icns (crocini #$MARK_COLOR)"
