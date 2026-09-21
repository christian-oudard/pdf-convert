#!/usr/bin/env bash
# Prepare a PDF for conversion. Everything before the model reads anything.
#
#   prepare.sh <pdf> <output-dir> [pages-per-batch]
#
# Decides scan or born-digital per page, picks the pages worth a page image,
# renders those, and writes per-batch reference text. Prints what the caller
# needs for the subagent prompts. Run again freely: it is a few seconds and
# rewrites everything identically.
set -u

if [ $# -lt 2 ]; then
  echo "usage: prepare.sh <pdf> <output-dir> [pages-per-batch]" >&2; exit 2
fi
[ -r "$1" ] || { echo "prepare.sh: cannot read $1" >&2; exit 2; }
command -v pdfinfo >/dev/null 2>&1 ||
  { echo "prepare.sh: poppler is not installed" >&2; exit 2; }

PDF=$(realpath "$1"); OUT="$2"; BATCH="${3:-4}"
NAME=$(basename "$PDF" .pdf); WORK=/tmp/pdf-convert/$NAME
mkdir -p "$WORK"

FIRST=${FIRST:-1}
LAST=${LAST:-$(pdfinfo "$PDF" | awk '/^Pages:/{print $2}')}
NPAGES=$(( LAST - FIRST + 1 ))

# A scanned page is one covered by a page-sized raster. Word count cannot tell:
# a journal scan usually carries an OCR layer, and those words are guesses.
PW=$(pdfinfo "$PDF" | awk '/^Page size:/{print $3}')
pdfimages -list "$PDF" |
  awk -v pw="$PW" 'NR>2 && $13>0 && ($4/$13*72) > pw*0.9 {print $1}' |
  sort -un > "$WORK/scanpages.txt"
NSCAN=$(wc -l < "$WORK/scanpages.txt")

# Which pages need an image. A scan needs all of them; a typeset page only when
# the text layer loses something - an equation, a table, a figure.
: > "$WORK/selected.txt"
if [ "$NSCAN" -gt $(( NPAGES / 2 )) ]; then
  seq "$FIRST" "$LAST" > "$WORK/selected.txt"
else
  RASTER=" $(pdfimages -list "$PDF" | awk 'NR>2{print $1}' | sort -un | tr '\n' ' ') "
  for n in $(seq "$FIRST" "$LAST"); do
    txt=$(pdftotext -layout -f "$n" -l "$n" "$PDF" -)
    mf=$(pdffonts -f "$n" -l "$n" "$PDF" | tail -n +3 |
         grep -ciE 'math|cmmi|cmsy|cmex|msam|msbm|rsfs|euclid')
    gap=$(echo "$txt" | grep -cE '[^ ] {2,}[^ ].* {2,}[^ ]')
    cap=$(echo "$txt" |
      grep -ciE '^[[:space:]]*(figure|fig\.|table|chart|plate|scheme|algorithm)[[:space:]]*[0-9]')
    img=$(echo "$RASTER" | grep -c " $n ")
    if [ "$mf" -ge 4 ] || [ "$gap" -ge 5 ] || [ "$cap" -ge 1 ] || [ "$img" -ge 1 ]; then
      echo "$n" >> "$WORK/selected.txt"
    fi
  done
fi

while read -r n; do
  pdftoppm -png -r 144 -f "$n" -l "$n" "$PDF" "$WORK/page"
done < "$WORK/selected.txt"

# As few batches as possible, all within one page of each other, so no call
# runs long while the others idle.
COUNT=$(( (NPAGES + BATCH - 1) / BATCH ))
BASE=$(( NPAGES / COUNT )); EXTRA=$(( NPAGES % COUNT ))
start=$FIRST
: > "$WORK/batches.txt"
for i in $(seq 1 "$COUNT"); do
  size=$BASE; [ "$i" -le "$EXTRA" ] && size=$(( BASE + 1 ))
  end=$(( start + size - 1 ))
  : > "$WORK/text_$start-$end.md"
  for n in $(seq "$start" "$end"); do
    printf '<!-- page %s -->\n' "$n" >> "$WORK/text_$start-$end.md"
    if grep -qx "$n" "$WORK/scanpages.txt"; then
      printf 'SCANNED PAGE: no reliable text. Read this page from its image.\n' \
        >> "$WORK/text_$start-$end.md"
    else
      pdftotext -f "$n" -l "$n" "$PDF" - >> "$WORK/text_$start-$end.md"
    fi
  done
  echo "$start-$end" >> "$WORK/batches.txt"
  start=$(( end + 1 ))
done

printf 'PDF    %s\n'    "$PDF"
printf 'OUT    %s/%s.md\n' "$OUT" "$NAME"
printf 'WORK   %s\n'    "$WORK"
printf 'pages  %s (%s to %s)   scanned %s   imaged %s\n' \
  "$NPAGES" "$FIRST" "$LAST" "$NSCAN" "$(wc -l < "$WORK/selected.txt")"
pdfinfo "$PDF" |
  awk '/^Page size:/{printf "zoom   %d by %d pixels at 400 DPI\n", $3/72*400, $5/72*400}'
pdfinfo -f "$FIRST" -l "$LAST" "$PDF" |
  awk '/rot:/ && $4 != 0 {print "ROTATED page " $2 ": rot " $4}'
printf 'batches %s\n' "$(tr '\n' ' ' < "$WORK/batches.txt")"

# Per-batch prompt fragments: the images each batch has, and the pages it does
# not. A subagent cannot tell a prose page from one whose image was forgotten.
while read -r r; do
  a=${r%-*}; b=${r#*-}
  echo
  echo "--- batch $r ---"
  echo "text: $WORK/text_$r.md"
  find "$WORK" -name 'page-*.png' | sort | while read -r f; do
    n=$((10#$(basename "$f" .png | sed 's/page-//')))
    [ "$n" -ge "$a" ] && [ "$n" -le "$b" ] && echo "- page $n: $f"
  done
  printf 'no image:'
  for n in $(seq "$a" "$b"); do
    grep -qx "$n" "$WORK/selected.txt" || printf ' %s' "$n"
  done
  echo
done < "$WORK/batches.txt"
