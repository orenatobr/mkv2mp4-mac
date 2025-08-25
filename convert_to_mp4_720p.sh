#!/usr/bin/env bash
set -euo pipefail

# Video Converter (MKV/MP4 -> MP4 720p, Apple Silicon optimized)
# - MKV: mantém apenas áudio PT/BR se disponível; senão, 1º áudio.
#        inclui legendas PT se textuais (ass/ssa/srt/subrip) -> mov_text.
# - MP4: re-encode simples para <=720p, sem filtragem de faixas.
# - Usa h264_videotoolbox para encode rápido por hardware no Apple Silicon.
# - Ordena e processa arquivos de forma portátil no macOS.
#
# Uso:
#   ./convert_to_mp4_720p.sh "/path/to/input" ["/path/to/output"]
#
# Variáveis de ambiente opcionais:
#   VBITS=2500k      # bitrate de vídeo alvo (padrão 2.5 Mbps)
#   VMAX=3000k       # VBV maxrate
#   VBUF=5000k       # VBV bufsize
#   ABITS=160k       # bitrate de áudio (padrão 160 kbps)
#   IN_OPTS="..."    # opções extras de entrada (padrão lida com corrupção)
#   HWDEC="..."      # opts de decodificação HW; defina vazio para desativar (HWDEC=)
#   LOGLEVEL=warning # nível de log do ffmpeg (warning|error|info); padrão: warning
#
# Exemplos:
#   VBITS=3000k VMAX=3500k VBUF=7000k ./convert_to_mp4_720p.sh "Bleach" "/Volumes/Renato/Animes/Bleach"
#   HWDEC= ./convert_to_mp4_720p.sh "Bleach" "/Volumes/Renato/Animes/Bleach"   # desativa HW decode

VBITS="${VBITS:-2500k}"
VMAX="${VMAX:-3000k}"
VBUF="${VBUF:-5000k}"
ABITS="${ABITS:-160k}"
LOGLEVEL="${LOGLEVEL:-warning}"

# Cadeia de filtros de vídeo:
# - Força formato NV12 antes do scale (ótimo p/ videotoolbox),
# - Faz o scale com aspect ratio (largura par) sem upscaling além de 720 de altura,
# - Normaliza SAR para 1:1,
# - Retorna para yuv420p (compatível amplo) no final.
VF_CHAIN="format=nv12,scale=-2:720,setsar=1,format=yuv420p"

# Robustez de entrada (descarta/ignora pacotes corrompidos)
IN_OPTS="${IN_OPTS:--fflags +discardcorrupt -err_detect ignore_err}"

# Decodificação por hardware opcional (desative com HWDEC=)
HWDEC_DEFAULT="-hwaccel videotoolbox"
HWDEC="${HWDEC:-$HWDEC_DEFAULT}"

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

# Lista temporária ordenada (portabilidade no macOS) — caminhos RELATIVOS
TMP_LIST="$(mktemp)"
trap 'rm -f "$TMP_LIST"' EXIT
(
	cd "$IN_DIR"
	find . -type f \( -iname "*.mkv" -o -iname "*.mp4" \) -print | LC_ALL=C sort
) >"$TMP_LIST"

while IFS= read -r REL; do
	found_any=true

	# Caminho absoluto de origem e componentes
	SRC="$IN_DIR/$REL"
	BASENAME="$(basename "$REL")"
	STEM="${BASENAME%.*}"
	EXT="${BASENAME##*.}"
	EXT_LOWER="$(printf '%s' "$EXT" | tr '[:upper:]' '[:lower:]')"

	# Diretório relativo (ex.: ./1a temp) -> remover prefixo "./"
	REL_DIR="$(dirname "$REL")"
	REL_DIR="${REL_DIR#./}"
	# Se for ".", queremos vazio (arquivos na raiz)
	[[ "$REL_DIR" == "." ]] && REL_DIR=""

	# Diretório de destino preservando a mesma hierarquia
	DST_DIR="$OUT_DIR"
	[[ -n "$REL_DIR" ]] && DST_DIR="$OUT_DIR/$REL_DIR"
	mkdir -p "$DST_DIR"

	DST="$DST_DIR/$STEM.mp4"

	echo "------------------------------------------------------------"
	echo "[SOURCE] $SRC"
	echo "[OUTPUT] $DST"

	# Detecta codec de vídeo para decidir uso de HW decode
	VCODEC="$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$SRC" || true)"
	DEC_OPTS=""

	# Só usa -hwaccel videotoolbox quando faz sentido (H.264/HEVC) e se não foi desativado
	if [[ -n "${HWDEC}" ]]; then
		case "$VCODEC" in
		h264 | hevc | h265) DEC_OPTS="$HWDEC" ;;
		*) DEC_OPTS="" ;; # força SW decode para mpeg2video, vp9, etc.
		esac
	fi

	case "$EXT_LOWER" in
	mkv)
		MAP_AUDIO_OPT=""
		AUDIO_META_OPT=""
		MAP_SUB_OPT=""
		SUB_CODEC_OPTS=""
		SUB_DISABLE_OPT=""

		# Áudio: PT/BR se disponível; senão, primeiro áudio
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

		# Legendas: inclui PT se for textual (evita PGS)
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
		ffmpeg -nostdin -loglevel "$LOGLEVEL" -stats -y $DEC_OPTS $IN_OPTS -i "$SRC" \
			-map 0:v:0 ${MAP_AUDIO_OPT} ${MAP_SUB_OPT} ${SUB_DISABLE_OPT} \
			-c:v h264_videotoolbox -b:v "$VBITS" -maxrate "$VMAX" -bufsize "$VBUF" \
			-vf "$VF_CHAIN" \
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
		ffmpeg -nostdin -loglevel "$LOGLEVEL" -stats -y $DEC_OPTS $IN_OPTS -i "$SRC" \
			-vf "$VF_CHAIN" -c:v h264_videotoolbox -b:v "$VBITS" -maxrate "$VMAX" -bufsize "$VBUF" \
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
