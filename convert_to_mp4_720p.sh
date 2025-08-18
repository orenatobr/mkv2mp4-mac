#!/usr/bin/env bash
set -euo pipefail

# Video Converter (MKV/MP4 -> MP4 720p, Apple Silicon optimized)
# - MKV: keep only Portuguese (pt/pt-BR) audio if available; otherwise first audio.
#        include Portuguese subtitles if text-based (ass/ssa/srt/subrip) -> mov_text.
# - MP4: simple re-encode to <=720p, no track filtering.
# - Uses h264_videotoolbox for fast hardware encoding on Apple Silicon.
# - Processes files in alphanumeric order (portable on macOS).
#
# Usage:
#   ./convert_videos_720p.sh "/path/to/input" ["/path/to/output"]
#
# Optional env vars:
#   VBITS=2500k      # target video bitrate (default 2.5 Mbps)
#   VMAX=3000k       # VBV maxrate
#   VBUF=5000k       # VBV bufsize
#   ABITS=160k       # audio bitrate (default 160 kbps)
#   IN_OPTS="..."    # extra input opts (defaults include corruption handling)
#   HWDEC="..."      # hw decode opts; set empty to disable (HWDEC=)
#
# Examples:
#   VBITS=3000k VMAX=3500k VBUF=7000k ./convert_videos_720p.sh "Bleach" "/Volumes/Renato/Animes/Bleach"
#   HWDEC= ./convert_videos_720p.sh "Bleach" "/Volumes/Renato/Animes/Bleach"   # disable hardware decode

VBITS="${VBITS:-2500k}"
VMAX="${VMAX:-3000k}"
VBUF="${VBUF:-5000k}"
ABITS="${ABITS:-160k}"

# No upscaling to >1280x720, keep aspect ratio, normalize SAR to 1:1
SCALE_FILTER="scale='min(iw,1280)':'min(ih,720)':force_original_aspect_ratio=decrease,setsar=1"

# Input robustness (drop/ignore corrupt packets)
IN_OPTS="${IN_OPTS:--fflags +discardcorrupt -err_detect ignore_err}"

# Optional hardware decode (unset HWDEC= to disable)
HWDEC="${HWDEC:--hwaccel videotoolbox}"

if ! command -v ffmpeg >/dev/null 2>&1; then
	echo "Error: ffmpeg not found. Install via: brew install ffmpeg"
	exit 1
fi
if ! command -v ffprobe >/dev/null 2>&1; then
	echo "Error: ffprobe not found. Install via: brew install ffmpeg"
	exit 1
fi

IN_DIR="${1:-.}"
OUT_DIR="${2:-$IN_DIR/converted_720p_mp4}"
mkdir -p "$OUT_DIR"

found_any=false

# Build a temp sorted list (newline-delimited for macOS portability)
TMP_LIST="$(mktemp)"
trap 'rm -f "$TMP_LIST"' EXIT
find "$IN_DIR" -type f \( -iname "*.mkv" -o -iname "*.mp4" \) -print | LC_ALL=C sort >"$TMP_LIST"

while IFS= read -r SRC; do
	found_any=true
	BASENAME="$(basename "$SRC")"
	STEM="${BASENAME%.*}"
	EXT="${BASENAME##*.}"
	EXT_LOWER="$(printf '%s' "$EXT" | tr '[:upper:]' '[:lower:]')"
	DST="$OUT_DIR/$STEM.mp4"

	echo "------------------------------------------------------------"
	echo "[SOURCE] $SRC"
	echo "[OUTPUT] $DST"

	case "$EXT_LOWER" in
	mkv)
		MAP_AUDIO_OPT=""
		AUDIO_META_OPT=""
		MAP_SUB_OPT=""
		SUB_CODEC_OPTS=""
		SUB_DISABLE_OPT=""

		# Audio: Portuguese if available; else first audio
		AIDX_POR="$(ffprobe -v error -select_streams a -show_entries stream=index:stream_tags=language -of csv=p=0 "$SRC" |
			awk -F',' 'BEGIN{IGNORECASE=1} $2 ~ /^(por|pt|pt-br)$/ {print $1; exit}' || true)"

		if [[ -n "${AIDX_POR:-}" ]]; then
			echo "Portuguese audio found at index $AIDX_POR."
			MAP_AUDIO_OPT="-map 0:$AIDX_POR"
			AUDIO_META_OPT="-metadata:s:a:0 language=por -disposition:a:0 default"
		else
			AIDX_FALLBACK="$(ffprobe -v error -select_streams a:0 -show_entries stream=index -of csv=p=0 "$SRC" 2>/dev/null || true)"
			if [[ -n "${AIDX_FALLBACK:-}" ]]; then
				echo "No Portuguese audio found. Using first audio track ($AIDX_FALLBACK)."
				MAP_AUDIO_OPT="-map 0:$AIDX_FALLBACK"
			else
				echo "No audio streams detected."
			fi
		fi

		# Subtitles: include PT if text-based (skip PGS image subs)
		SUB_PICK="$(ffprobe -v error -select_streams s -show_entries stream=index,codec_name:stream_tags=language -of csv=p=0 "$SRC" |
			awk -F',' 'BEGIN{IGNORECASE=1} {i=$1;c=$2;l=$3; if (l ~ /^(por|pt|pt-br)$/ && c ~ /^(ass|ssa|subrip|srt|text)$/) {print i; exit}}' || true)"

		if [[ -n "${SUB_PICK:-}" ]]; then
			echo "Portuguese subtitle (text) found at index $SUB_PICK."
			MAP_SUB_OPT="-map 0:$SUB_PICK"
			SUB_CODEC_OPTS="-c:s mov_text -metadata:s:s:0 language=por"
		else
			SUB_DISABLE_OPT="-sn"
		fi

		# shellcheck disable=SC2086
		ffmpeg -nostdin -y $HWDEC $IN_OPTS -i "$SRC" \
			-map 0:v:0 ${MAP_AUDIO_OPT} ${MAP_SUB_OPT} ${SUB_DISABLE_OPT} \
			-c:v h264_videotoolbox -b:v "$VBITS" -maxrate "$VMAX" -bufsize "$VBUF" -vf "$SCALE_FILTER" -pix_fmt yuv420p \
			-colorspace bt709 -color_primaries bt709 -color_trc bt709 -color_range tv \
			-c:a aac -b:a "$ABITS" -ac 2 \
			${SUB_CODEC_OPTS} \
			-movflags +faststart -map_metadata 0 \
			${AUDIO_META_OPT} \
			"$DST"
		;;
	mp4)
		echo "Simple MP4 re-encode (no track filtering)."
		# shellcheck disable=SC2086
		ffmpeg -nostdin -y $HWDEC $IN_OPTS -i "$SRC" \
			-vf "$SCALE_FILTER" -c:v h264_videotoolbox -b:v "$VBITS" -maxrate "$VMAX" -bufsize "$VBUF" -pix_fmt yuv420p \
			-colorspace bt709 -color_primaries bt709 -color_trc bt709 -color_range tv \
			-c:a aac -b:a "$ABITS" -ac 2 \
			-movflags +faststart -map_metadata 0 \
			"$DST"
		;;
	*)
		echo "Skipping unsupported file: $SRC"
		;;
	esac

	echo "Done: $DST"
done <"$TMP_LIST"

if ! $found_any; then
	echo "No MKV or MP4 files found in: $IN_DIR"
	exit 2
fi

echo "All conversions finished. Output folder: $OUT_DIR"
