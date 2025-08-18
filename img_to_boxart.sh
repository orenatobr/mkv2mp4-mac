#!/usr/bin/env bash
set -euo pipefail

# img2boxart.sh — Converts images to PNG 128x115 for use in TWiLight Menu++
# Default: preserves aspect ratio and pads with transparency up to 128x115.
#
# Usage:
#   ./img2boxart.sh <files|folders>... [-o <output>] [--mode pad|crop|stretch] [--bg <color>]
#
# Examples:
#   ./img2boxart.sh "cover.jpg" -o out/
#   ./img2boxart.sh ./my_images -o boxart/ --mode pad --bg none
#   ./img2boxart.sh *.webp --mode crop -o out/
#
# TWiLight tips:
#   Place outputs in: sd:/_nds/TWiLightMenu/boxart/

WIDTH=128
HEIGHT=115
MODE="pad" # pad | crop | stretch
BG="none"  # background color for padding (e.g., none, white, black, "#00000000")
OUTDIR="./out"

# --- Simple argument parsing ---
inputs=()
while (("$#")); do
    case "$1" in
    -o | --out | -out | --output)
        OUTDIR="${2:-}"
        shift 2
        ;;
    --mode)
        MODE="${2:-}"
        shift 2
        ;;
    --bg | --background)
        BG="${2:-}"
        shift 2
        ;;
    -h | --help)
        sed -n '1,60p' "$0"
        exit 0
        ;;
    --)
        shift
        break
        ;;
    -*)
        echo "Unknown option: $1" >&2
        exit 1
        ;;
    *)
        inputs+=("$1")
        shift
        ;;
    esac
done

if [ "${#inputs[@]}" -eq 0 ]; then
    echo "No input provided. Use -h for help." >&2
    exit 1
fi

mkdir -p "$OUTDIR"

have_magick=false
if command -v magick >/dev/null 2>&1; then
    IM_CMD="magick"
    have_magick=true
elif command -v convert >/dev/null 2>&1; then
    IM_CMD="convert"
    have_magick=true
fi

if ! $have_magick && ! command -v sips >/dev/null 2>&1; then
    echo "Error: neither ImageMagick (magick/convert) nor sips found." >&2
    exit 1
fi

shopt -s nullglob

# --- Compatible with bash 3.x (no ${var,,}) ---
is_image() {
    local f="$1"
    case "$(printf '%s' "$f" | tr '[:upper:]' '[:lower:]')" in
    *.jpg | *.jpeg | *.png | *.bmp | *.gif | *.tif | *.tiff | *.webp | *.jfif | *.heic | *.avif) return 0 ;;
    *) return 1 ;;
    esac
}

process_file_im() {
    local in="$1"
    local out="$2"
    case "$MODE" in
    pad)
        # Fit inside 128x115 and pad with background (no crop)
        "$IM_CMD" "$in" -alpha on -background "$BG" \
            -resize "${WIDTH}x${HEIGHT}" \
            -gravity center -extent "${WIDTH}x${HEIGHT}" \
            -define png:color-type=6 "png32:$out"
        ;;
    crop)
        # Fill 128x115 completely and crop overflow (no stretch)
        "$IM_CMD" "$in" -alpha on -background "$BG" \
            -resize "${WIDTH}x${HEIGHT}^" \
            -gravity center -extent "${WIDTH}x${HEIGHT}" \
            -define png:color-type=6 "png32:$out"
        ;;
    stretch)
        # Stretch to exactly 128x115
        "$IM_CMD" "$in" -alpha on -resize "${WIDTH}x${HEIGHT}!" \
            -define png:color-type=6 "png32:$out"
        ;;
    *)
        echo "Invalid mode: $MODE (use pad|crop|stretch)"
        exit 1
        ;;
    esac
}

process_file_sips() {
    # Fallback: sips only supports simple stretch
    local in="$1"
    local out="$2"
    sips -s format png "$in" --out "$out" >/dev/null
    sips -z "$HEIGHT" "$WIDTH" "$out" >/dev/null
}

process_path() {
    local p="$1"
    if [ -d "$p" ]; then
        # Iterate recursively
        while IFS= read -r -d '' f; do
            if is_image "$f"; then
                local base
                base="$(basename "${f%.*}")"
                local out="$OUTDIR/$base.png"
                if $have_magick; then
                    process_file_im "$f" "$out"
                else
                    process_file_sips "$f" "$out"
                fi
                echo "[OK] $f -> $out"
            fi
        done < <(find "$p" -type f -print0)
    else
        if is_image "$p"; then
            local base
            base="$(basename "${p%.*}")"
            local out="$OUTDIR/$base.png"
            if $have_magick; then
                process_file_im "$p" "$out"
            else
                process_file_sips "$p" "$out"
            fi
            echo "[OK] $p -> $out"
        else
            echo "[SKIP] Not an image: $p"
        fi
    fi
}

for item in "${inputs[@]}"; do
    process_path "$item"
done

echo "Done. Outputs saved in: $OUTDIR"
