#!/bin/bash
# Turn a flat-background PNG into a real transparent asset for assets/onboarding/.
#
#   tools/cutout.sh ~/Downloads/robot.png robot
#
# Works on flat backgrounds — magenta (#FF00FF), white, or the grey checkerboard
# some tools paint in instead of real transparency. For a subject with white or
# silver edges, use Finder → Quick Actions → Remove Background instead: that uses
# Apple's subject detection and will not eat light-coloured parts of the subject.

set -euo pipefail

SRC="${1:?usage: cutout.sh <source.png> <name>}"
NAME="${2:?usage: cutout.sh <source.png> <name>}"
OUT_DIR="$(cd "$(dirname "$0")/.." && pwd)/assets/onboarding"
OUT="$OUT_DIR/$NAME.png"
SIZE=800          # never drawn larger than ~340pt on a phone; 800 is plenty at 2x

command -v magick >/dev/null || { echo "ImageMagick is missing: brew install imagemagick"; exit 1; }
[ -f "$SRC" ] || { echo "No such file: $SRC"; exit 1; }

W=$(magick identify -format '%w' "$SRC")
H=$(magick identify -format '%h' "$SRC")
CORNER=$(magick "$SRC" -format '%[pixel:p{2,2}]' info:)
echo "source   ${W}x${H}, corner colour $CORNER"

# Flood-fill the background in from all four corners, so colours that also occur
# inside the subject (white cards, silver dial) are left alone.
magick "$SRC" -alpha set -fuzz 12% \
  -fill none -floodfill +0+0                "$CORNER" \
  -fill none -floodfill +$((W-1))+0         "$CORNER" \
  -fill none -floodfill +0+$((H-1))         "$CORNER" \
  -fill none -floodfill +$((W-1))+$((H-1))  "$CORNER" \
  -trim +repage \
  -resize "${SIZE}x${SIZE}>" \
  -background none -gravity center -extent "${SIZE}x${SIZE}" \
  "$OUT"

# Verify rather than assume: the file must have alpha, transparent corners, and
# an opaque middle. A subject that fills the whole frame means the key failed.
HAS_ALPHA=$(sips -g hasAlpha "$OUT" | awk '/hasAlpha/{print $2}')
A_CORNER=$(magick "$OUT" -format '%[fx:round(255*p{4,4}.a)]' info:)
A_MID=$(magick "$OUT" -format "%[fx:round(255*p{$((SIZE/2)),$((SIZE/2))}.a)]" info:)
OPAQUE=$(magick "$OUT" -format '%[fx:round(100*mean.a)]' info:)

echo "result   $(sips -g pixelWidth -g pixelHeight "$OUT" | awk '/pixelWidth|pixelHeight/{printf "%s ", $2}')· $(( $(stat -f%z "$OUT") / 1024 )) KB"
echo "alpha    $HAS_ALPHA · corner $A_CORNER · centre $A_MID · ${OPAQUE}% opaque"

FAIL=0
[ "$HAS_ALPHA" = "yes" ] || { echo "FAIL: no alpha channel"; FAIL=1; }
[ "$A_CORNER" -lt 10 ]   || { echo "FAIL: corner is not transparent — background was not flat"; FAIL=1; }
[ "$A_MID" -gt 200 ]     || { echo "WARN: centre is transparent — the subject may not be centred"; }
[ "$OPAQUE" -lt 90 ]     || { echo "FAIL: ${OPAQUE}% opaque — nothing was removed"; FAIL=1; }

if [ "$FAIL" = 1 ]; then
  rm -f "$OUT"
  echo
  echo "Deleted the output. Use Finder → Quick Actions → Remove Background instead,"
  echo "or regenerate the artwork on a solid #FF00FF background."
  exit 1
fi

echo
echo "OK  → assets/onboarding/$NAME.png"
