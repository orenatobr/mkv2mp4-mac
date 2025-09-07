#!/usr/bin/env bash
set -euo pipefail

# img2boxart.sh — Resize/convert covers for PSX/PS2/PS3
#
# Usage:
#   ./img2boxart.sh <PSX|PS2|PS3> <input_file|input_dir> [output_file_or_dir] [--mode pad|crop|stretch] [--bg <color>]
#
# Examples:
#   ./img2boxart.sh PSX ~/covers/ffvii.jpg
#   ./img2boxart.sh PS2 ~/covers_dir ~/out_dir --mode crop --bg black
#   ./img2boxart.sh PS3 "~/in/God of War.jpg" "~/out/God of War.png"

# -------- Helpers (Bash 3.2 safe) --------
to_lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

is_image_ext() {
	local f_lc
	f_lc="$(to_lower "$1")"
	case "$f_lc" in
	*.jpg | *.jpeg | *.png | *.bmp | *.gif | *.tif | *.tiff | *.webp | *.jfif | *.heic | *.avif) return 0 ;;
	*) return 1 ;;
	esac
}

basename_noext() {
	local p="$1"
	local b
	b="$(basename "$p")"
	printf '%s' "${b%.*}"
}

dir_exists() { [ -d "$1" ]; }
file_exists() { [ -f "$1" ]; }

ensure_png_path_or_dir() {
	local p="$1"
	# If ends with '/', treat as dir
	if [[ "$p" == */ ]]; then return 0; fi
	if dir_exists "$p"; then return 0; fi
	# Otherwise must be a .png file path
	if [[ "$(to_lower "$p")" != *.png ]]; then
		echo "[ERROR] Output file must end with .png (or be a directory): $p" >&2
		exit 1
	fi
}

# -------- Parse required args --------
if [[ $# -lt 2 ]]; then
	echo "Usage: $0 <PSX|PS2|PS3> <input_file|input_dir> [output_file_or_dir] [--mode pad|crop|stretch] [--bg <color>]" >&2
	exit 1
fi

PROFILE_RAW="$1"
shift
PROFILE="$(to_lower "$PROFILE_RAW")"
INPUT="$1"
shift
OUTPUT="${1:-}"
if [[ $# -ge 1 && "$1" != --* ]]; then shift; fi

# Defaults
MODE="pad" # pad|crop|stretch
BG="none"  # none|white|black|#RRGGBBAA

# Optional flags after the 3 positionals
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
		echo "Unexpected extra argument: $1" >&2
		exit 1
		;;
	esac
done

# -------- Profile sizes --------
WIDTH=0
HEIGHT=0
case "$PROFILE" in
psx | ps1)
	WIDTH=512
	HEIGHT=512
	;;
ps2)
	WIDTH=342
	HEIGHT=512
	;;
ps3)
	WIDTH=342
	HEIGHT=512
	;;
*)
	echo "[ERROR] Unknown profile '$PROFILE_RAW'. Use PSX | PS2 | PS3." >&2
	exit 1
	;;
esac

# -------- Backends --------
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

# -------- Processors --------
process_file_im() {
	local in="$1" out="$2"
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
	local in="$1" out="$2"
	sips -s format png "$in" --out "$out" >/dev/null
	sips -z "$HEIGHT" "$WIDTH" "$out" >/dev/null
}

process_single_file() {
	local in="$1" out="$2"
	if $have_magick; then process_file_im "$in" "$out"; else process_file_sips "$in" "$out"; fi
	echo "[OK] $in -> $out"
}

# Given IN_FILE and optional OUT_ROOT (file or dir), compute OUT_FILE (.png)
# Behavior:
# - If OUT_ROOT empty: same dir as IN_FILE, same basename, .png
# - If OUT_ROOT is dir (exists or ends with '/'): put inside dir, same basename, .png
# - If OUT_ROOT is file: use exactly that (must .png)
resolve_output_for_file() {
	local in_file="$1" out_root="${2:-}"
	local base out_dir out_file
	base="$(basename_noext "$in_file")"

	if [[ -z "$out_root" ]]; then
		printf '%s/%s.png\n' "$(dirname "$in_file")" "$base"
		return
	fi

	if [[ "$out_root" == */ ]] || dir_exists "$out_root"; then
		mkdir -p "$out_root"
		printf '%s/%s.png\n' "$out_root" "$base"
		return
	fi

	# file path
	ensure_png_path_or_dir "$out_root"
	mkdir -p "$(dirname "$out_root")"
	printf '%s\n' "$out_root"
}

# When INPUT is a directory and OUTPUT is a directory (or empty), keep relative structure
# If OUTPUT is a file while INPUT is a dir -> error (ambiguous)
process_dir_recursive() {
	local in_dir="$1" out_root="${2:-}"
	if [[ -n "$out_root" ]] && [[ "$out_root" != */ ]] && ! dir_exists "$out_root"; then
		# Looks like a file path
		if [[ "$(to_lower "$out_root")" == *.png ]]; then
			echo "[ERROR] Output cannot be a single file when input is a directory. Provide an output directory." >&2
			exit 1
		fi
	fi

	# Ensure out_root dir if provided
	if [[ -n "$out_root" ]]; then mkdir -p "$out_root"; fi

	while IFS= read -r -d '' f; do
		if is_image_ext "$f"; then
			local rel base out_dir out_file
			rel="${f#$in_dir/}" # keep subdirs
			base="$(basename_noext "$rel")"
			out_dir="$(dirname "$rel")"
			if [[ -z "$out_root" ]]; then
				# same directory as the file
				out_file="$(dirname "$f")/$base.png"
			else
				mkdir -p "$out_root/$out_dir"
				out_file="$out_root/$out_dir/$base.png"
			fi
			process_single_file "$f" "$out_file"
		fi
	done < <(find "$in_dir" -type f -print0)
}

# -------- Main flow --------
if [[ -d "$INPUT" ]]; then
	# Directory mode
	if [[ -n "${OUTPUT:-}" ]]; then ensure_png_path_or_dir "$OUTPUT"; fi
	process_dir_recursive "$INPUT" "${OUTPUT:-}"
else
	# Single file mode
	if ! file_exists "$INPUT"; then
		echo "[ERROR] Input file not found: $INPUT" >&2
		exit 1
	fi
	if ! is_image_ext "$INPUT"; then
		echo "[ERROR] Input is not an image: $INPUT" >&2
		exit 1
	fi
	if [[ -n "${OUTPUT:-}" ]]; then ensure_png_path_or_dir "$OUTPUT"; fi
	OUT_FILE="$(resolve_output_for_file "$INPUT" "${OUTPUT:-}")"
	process_single_file "$INPUT" "$OUT_FILE"
fi

echo "Done."
