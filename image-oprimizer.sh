#!/usr/bin/env bash
# image-oprimizer.sh
# Safe batch optimizer: creates optimized/ copies, optionally resizes, and converts to WebP

set -u

PROGNAME=$(basename "$0")

usage() {
  cat <<EOF
Usage: $PROGNAME [options] <folder>

Options:
  -o DIR      Output subfolder name under the target folder (default: optimized)
  -w WIDTH    Resize max width (pixels). Only shrink; keep aspect ratio.
  -q QUALITY  Target quality for lossy encoders (default: 80)
  -r          Recurse into subdirectories
  -c          Also create WebP copies (default: enabled)
  -n          Dry-run (no files written)
  -h          Show this help

Example:
  # dry-run, recursively resize to max width 800 and create webp versions
  $PROGNAME -n -r -w 800 -q 80 ./react-native/react-native-dating-app

This script tries to use best-available tools: pngquant, cwebp, jpegoptim/cjpeg, and ImageMagick's convert as a fallback.
It writes optimized files into <folder>/<outdir>/ preserving subdirectories.
EOF
}

OUTDIR='optimized'
MAX_WIDTH=''
QUALITY=80
RECURSIVE=0
CREATE_WEBP=1
DRY_RUN=0

while getopts ":o:w:q:rchn" opt; do
  case $opt in
    o) OUTDIR="$OPTARG" ;;
    w) MAX_WIDTH="$OPTARG" ;;
    q) QUALITY="$OPTARG" ;;
    r) RECURSIVE=1 ;;
    c) CREATE_WEBP=1 ;;
    n) DRY_RUN=1 ;;
    h) usage; exit 0 ;;
    :) echo "Missing argument for -$OPTARG"; usage; exit 2 ;;
    *) echo "Unknown option: -$OPTARG"; usage; exit 2 ;;
  esac
done
shift $((OPTIND-1))

if [ $# -lt 1 ]; then
  usage
  exit 2
fi

TARGET="$1"
if [ ! -d "$TARGET" ]; then
  echo "Target folder not found: $TARGET"
  exit 1
fi

which_pngquant=$(command -v pngquant || true)
which_cwebp=$(command -v cwebp || true)
which_jpegoptim=$(command -v jpegoptim || true)
which_cjpeg=$(command -v cjpeg || true)
which_convert=$(command -v convert || true)

echo "Tools: pngquant=${which_pngquant:-none} cwebp=${which_cwebp:-none} jpegoptim=${which_jpegoptim:-none} cjpeg=${which_cjpeg:-none} convert=${which_convert:-none}"
echo "Target: $TARGET -> out subfolder: $OUTDIR (dry-run=$DRY_RUN recursive=$RECURSIVE webp=$CREATE_WEBP)"

shopt -s nullglob 2>/dev/null || true

find_expr=()
if [ "$RECURSIVE" -eq 1 ]; then
  find_expr=("$(printf '%s\n' "$TARGET" | sed 's/[].[^$*]/\\&/g')")
  # we'll use find to enumerate files
  LIST_CMD=(find "$TARGET" -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.gif' -o -iname '*.svg' -o -iname '*.webp' \))
else
  LIST_CMD=(bash -c "printf '%s\n' $TARGET/*.{png,jpg,jpeg,gif,svg,webp} 2>/dev/null || true")
fi

mkdir -p "$TARGET/$OUTDIR"

files=()
if [ "$RECURSIVE" -eq 1 ]; then
  while IFS= read -r f; do files+=("$f"); done < <(find "$TARGET" -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.gif' -o -iname '*.svg' -o -iname '*.webp' \))
else
  # non-recursive glob
  for ext in png jpg jpeg gif svg webp; do
    for f in "$TARGET"/*.$ext; do
      [ -f "$f" ] || continue
      files+=("$f")
    done
  done
fi

if [ ${#files[@]} -eq 0 ]; then
  echo "No images found in $TARGET"
  exit 0
fi

bytes_to_human() {
  local b=$1
  if [ $b -lt 1024 ]; then printf "%dB" "$b"; return; fi
  if [ $b -lt $((1024*1024)) ]; then printf "%.1fkB" "$(awk -v b=$b 'BEGIN{printf b/1024}')"; return; fi
  printf "%.2fMB" "$(awk -v b=$b 'BEGIN{printf b/1024/1024}')"
}

count=0
total_before=0
total_after=0

optimize_png() {
  local src="$1" dst="$2"
  if [ -n "$which_pngquant" ]; then
    # pngquant writes to stdout or file; use --skip-if-larger to avoid growth
    if [ "$DRY_RUN" -eq 1 ]; then
      echo "DRY: pngquant --quality=${QUALITY-65}-${QUALITY} --strip --skip-if-larger --output '$dst' -- '$src'"
    else
      mkdir -p "$(dirname "$dst")"
      pngquant --quality=${QUALITY-20}-${QUALITY} --strip --skip-if-larger --output "$dst" -- "$src" 2>/dev/null || cp "$src" "$dst"
    fi
  elif [ -n "$which_convert" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      echo "DRY: convert '$src' -strip -quality $QUALITY '$dst'"
    else
      mkdir -p "$(dirname "$dst")"
      convert "$src" -strip -quality $QUALITY "$dst"
    fi
  else
    if [ "$DRY_RUN" -eq 1 ]; then
      echo "DRY: copy $src -> $dst (no optimizer available)"
    else
      mkdir -p "$(dirname "$dst")"; cp "$src" "$dst"
    fi
  fi
}

optimize_jpg() {
  local src="$1" dst="$2"
  if [ -n "$which_cjpeg" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      echo "DRY: cjpeg -quality $QUALITY -outfile '$dst' '$src'"
    else
      mkdir -p "$(dirname "$dst")"
      cjpeg -quality "$QUALITY" -outfile "$dst" "$src" 2>/dev/null || cp "$src" "$dst"
    fi
  elif [ -n "$which_jpegoptim" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      echo "DRY: copy $src -> $dst; jpegoptim --strip-all --max=$QUALITY '$dst'"
    else
      mkdir -p "$(dirname "$dst")"; cp "$src" "$dst"; jpegoptim --strip-all --max="$QUALITY" --all-progressive "$dst" 2>/dev/null || true
    fi
  elif [ -n "$which_convert" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      echo "DRY: convert '$src' -strip -quality $QUALITY '$dst'"
    else
      mkdir -p "$(dirname "$dst")"; convert "$src" -strip -quality "$QUALITY" "$dst"
    fi
  else
    if [ "$DRY_RUN" -eq 1 ]; then
      echo "DRY: copy $src -> $dst (no jpg optimizer)"
    else
      mkdir -p "$(dirname "$dst")"; cp "$src" "$dst"
    fi
  fi
}

convert_webp() {
  local src="$1" dst="$2"
  if [ -n "$which_cwebp" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      echo "DRY: cwebp -q $QUALITY '$src' -o '$dst'"
    else
      mkdir -p "$(dirname "$dst")"; cwebp -q "$QUALITY" "$src" -o "$dst" >/dev/null 2>&1 || true
    fi
  elif [ -n "$which_convert" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      echo "DRY: convert '$src' -quality $QUALITY '$dst'"
    else
      mkdir -p "$(dirname "$dst")"; convert "$src" -quality "$QUALITY" "$dst" >/dev/null 2>&1 || true
    fi
  else
    if [ "$DRY_RUN" -eq 1 ]; then
      echo "DRY: would create webp $dst (no tool)"
    else
      echo "(no webp tool available to create $dst)" >&2
    fi
  fi
}

process_one() {
  local src="$1"
  local rel=${src#"$TARGET"/}
  local subdir=$(dirname "$rel")
  local base=$(basename "$src")
  local outdir_full="$TARGET/$OUTDIR/$subdir"
  local outpath="$outdir_full/$base"

  mkdir -p "$outdir_full"

  # optionally resize first into a temp file if MAX_WIDTH specified
  local proc_src="$src"
  local tmpf=''
  if [ -n "$MAX_WIDTH" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      echo "DRY: would resize $src to max width $MAX_WIDTH"
    else
      tmpf=$(mktemp -t imgopt-XXXX)
      if [ -n "$which_convert" ]; then
        convert "$src" -resize "${MAX_WIDTH}x>" "$tmpf"
        proc_src="$tmpf"
      else
        proc_src="$src"
      fi
    fi
  fi

  local ext="${base##*.}"
  # portable lowercase for macOS bash 3
  ext="$(echo "$ext" | tr '[:upper:]' '[:lower:]')"

  # record sizes
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "DRY: processing $src -> $outpath"
  else
    before=$(stat -f%z "$src" 2>/dev/null || stat -c%s "$src")
    total_before=$((total_before + before))
  fi

  case "$ext" in
    png)
      optimize_png "$proc_src" "$outpath"
      ;;
    jpg|jpeg)
      optimize_jpg "$proc_src" "$outpath"
      ;;
    gif|svg|webp)
      # for non-png/jpg, just copy (or use convert if available)
      if [ "$DRY_RUN" -eq 1 ]; then
        echo "DRY: copy $src -> $outpath"
      else
        cp "$proc_src" "$outpath"
      fi
      ;;
    *)
      if [ "$DRY_RUN" -eq 1 ]; then
        echo "DRY: skip unknown ext $src"
      fi
      ;;
  esac

  # webp
  if [ "$CREATE_WEBP" -eq 1 ]; then
    webp_out="$outdir_full/${base%.*}.webp"
    convert_webp "$outpath" "$webp_out"
  fi

  if [ -n "${tmpf:-}" ] && [ -f "${tmpf:-}" ]; then
    rm -f "${tmpf}" 2>/dev/null || true
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    :
  else
    after=$(stat -f%z "$outpath" 2>/dev/null || stat -c%s "$outpath" 2>/dev/null || echo 0)
    total_after=$((total_after + after))
  fi

  count=$((count+1))
}

echo "Found ${#files[@]} image(s). Starting optimization..."

for f in "${files[@]}"; do
  process_one "$f"
done

if [ "$DRY_RUN" -eq 1 ]; then
  echo "Dry-run complete. No files were written."
else
  echo "Processed $count files. Total before: $(bytes_to_human $total_before) after: $(bytes_to_human $total_after)"
  savings=$((total_before - total_after))
  echo "Estimated savings: $(bytes_to_human $savings)"
fi

exit 0
