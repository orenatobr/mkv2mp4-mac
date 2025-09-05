#!/usr/bin/env bash
set -euo pipefail

# img2boxart.sh — Converts images to PNG resized for TWiLight Menu++ (or general use)
# Default size: 250x288 (can override with first two arguments)
#
# Usage:
#   ./img2boxart.sh [WIDTH] [HEIGHT] <files|folders>... [--mode pad|crop|stretch] [--bg <color>]
#
# Examples:
#   ./img2boxart.sh 128 115 cover.jpg
#   ./img2boxart.sh 250 288 ./my_images --mode crop --bg black
#
# Output:
#   Same folder as input, with "-resized.png" suffix.
#   Example: imagem.jpg → imagem-resized.png

# --- Defaults for size (positional args can override) ---
WIDTH=250
HEIGHT=288

if [[ $# -ge 2 && "$1" =~ ^[0-9]+$ && "$2" =~ ^[0-9]+$ ]]; then
    WIDTH="$1"
    HEIGHT="$2"
    shift 2
elif [[ $# -ge 1 && "$1" =~ ^[0-9]+$ ]]; then
    WIDTH="$1"
    shift
fi

MODE="pad" # pad | crop | stretch
BG="none"  # background color for padding (e.g., none, white, black, "#00000000")

# --- Simple argument parsing ---
inputs=()
while (("$#")); do
    case "$1" in
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

# --- Check extensions ---
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
        "$IM_CMD" "$in" -alpha on -background "$BG" \
            -resize "${WIDTH}x${HEIGHT}" \
            -gravity center -extent "${WIDTH}x${HEIGHT}" \
            -define png:color-type=6 "png32:$out"
        ;;
    crop)
        "$IM_CMD" "$in" -alpha on -background "$BG" \
            -resize "${WIDTH}x${HEIGHT}^" \
            -gravity center -extent "${WIDTH}x${HEIGHT}" \
            -define png:color-type=6 "png32:$out"
        ;;
    stretch)
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
    local in="$1"
    local out="$2"
    sips -s format png "$in" --out "$out" >/dev/null
    sips -z "$HEIGHT" "$WIDTH" "$out" >/dev/null
}

process_path() {
    local p="$1"
    if [ -d "$p" ]; then
        while IFS= read -r -d '' f; do
            if is_image "$f"; then
                local dir base out
                dir="$(dirname "$f")"
                base="$(basename "${f%.*}")"
                out="$dir/${base}-resized.png"
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
            local dir base out
            dir="$(dirname "$p")"
            base="$(basename "${p%.*}")"
            out="$dir/${base}-resized.png"
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

echo "Done."
