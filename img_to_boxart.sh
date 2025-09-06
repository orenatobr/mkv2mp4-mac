#!/usr/bin/env bash
set -euo pipefail

# img2boxart.sh — Converts images to PNG resized for TWiLight Menu++ (or general use)
# Default size: 250x288 (can override with first two arguments)
#
# Usage:
#   ./img2boxart.sh [WIDTH] [HEIGHT] <files|folders>... [--mode pad|crop|stretch] [--bg <color>] [--out <file.png>]
#
# Examples:
#   ./img2boxart.sh 128 115 cover.jpg
#   ./img2boxart.sh 250 288 ./my_images --mode crop --bg black
#   ./img2boxart.sh --out ~/out.png ~/in.jpg
#
# Output:
#   Same folder as input, with "-resized.png" suffix (unless --out is used).
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
OUT_FILE=""

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
	--out)
		OUT_FILE="${2:-}"
		shift 2
		;;
	-h | --help)
		sed -n '1,160p' "$0"
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

if [[ -n "$OUT_FILE" && ${#inputs[@]} -ne 1 ]]; then
	echo "When using --out, provide exactly one input file." >&2
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

# --- Helpers ---
to_lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

is_image_ext() {
	local f_lc
	f_lc="$(to_lower "$1")"
	case "$f_lc" in
	*.jpg | *.jpeg | *.png | *.bmp | *.gif | *.tif | *.tiff | *.webp | *.jfif | *.heic | *.avif) return 0 ;;
	*) return 1 ;;
	esac
}

require_existing_file() {
	local p="$1"
	if [ ! -f "$p" ]; then
		echo "[ERROR] Input file not found: $p" >&2
		return 1
	fi
}

ensure_png_ext() {
	local p="$1"
	if [[ "$(to_lower "$p")" != *.png ]]; then
		echo "[ERROR] --out must point to a .png file: $p" >&2
		exit 1
	fi
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
		echo "Invalid mode: $MODE (use pad|crop|stretch)" >&2
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

process_single_file() {
	local in="$1"
	local out="$2"
	if $have_magick; then
		process_file_im "$in" "$out"
	else
		process_file_sips "$in" "$out"
	fi
	echo "[OK] $in -> $out"
}

process_path() {
	local p="$1"
	if [ -d "$p" ]; then
		while IFS= read -r -d '' f; do
			if is_image_ext "$f"; then
				local dir base out
				dir="$(dirname "$f")"
				base="$(basename "${f%.*}")"
				out="$dir/${base}-resized.png"
				process_single_file "$f" "$out"
			fi
		done < <(find "$p" -type f -print0)
	else
		if ! is_image_ext "$p"; then
			echo "[SKIP] Not an image: $p"
			return
		fi
		require_existing_file "$p"
		local dir base out
		dir="$(dirname "$p")"
		base="$(basename "${p%.*}")"
		out="$dir/${base}-resized.png"
		process_single_file "$p" "$out"
	fi
}

# --- Main flow ---
if [[ -n "$OUT_FILE" ]]; then
	ensure_png_ext "$OUT_FILE"
	in="${inputs[0]}"
	if ! is_image_ext "$in"; then
		echo "[ERROR] Input must be an image file when using --out." >&2
		exit 1
	fi
	require_existing_file "$in"
	mkdir -p "$(dirname "$OUT_FILE")"
	process_single_file "$in" "$OUT_FILE"
else
	for item in "${inputs[@]}"; do
		if [[ ! -e "$item" && "$(to_lower "$item")" == *.png ]]; then
			echo "[WARN] '$item' parece um .png de saída. Use --out <arquivo.png> para definir a saída." >&2
			continue
		fi
		process_path "$item"
	done
fi

echo "Done."
