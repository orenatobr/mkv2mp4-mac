#!/usr/bin/env bash
set -euo pipefail

# img2boxart.sh — Converte imagens para PNG 128x115 para uso no TWiLight Menu++
# Default: preserva aspecto e preenche (padding) com transparência até 128x115.
#
# Uso:
#   ./img2boxart.sh <arquivos|pastas>... [-o <saida>] [--mode pad|crop|stretch] [--bg <cor>]
#
# Exemplos:
#   ./img2boxart.sh "capa.jpg" -o out/
#   ./img2boxart.sh ./minhas_imagens -o boxart/ --mode pad --bg none
#   ./img2boxart.sh *.webp --mode crop -o out/
#
# Dicas TWiLight:
#   Coloque as saídas em: sd:/_nds/TWiLightMenu/boxart/

WIDTH=128
HEIGHT=115
MODE="pad" # pad | crop | stretch
BG="none"  # cor de fundo para padding (ex.: none, white, black, "#00000000")
OUTDIR="./out"

# --- Parse de argumentos simples ---
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
        echo "Opção desconhecida: $1" >&2
        exit 1
        ;;
    *)
        inputs+=("$1")
        shift
        ;;
    esac
done

if [ "${#inputs[@]}" -eq 0 ]; then
    echo "Nenhuma entrada informada. Use -h para ajuda." >&2
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
    echo "Erro: nem ImageMagick (magick/convert) nem sips encontrados." >&2
    exit 1
fi

shopt -s nullglob

# --- Compatível com bash 3.x (sem ${var,,}) ---
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
        # Ajusta para caber e preenche até 128x115 (sem cortar)
        "$IM_CMD" "$in" -alpha on -background "$BG" \
            -resize "${WIDTH}x${HEIGHT}" \
            -gravity center -extent "${WIDTH}x${HEIGHT}" \
            -define png:color-type=6 "png32:$out"
        ;;
    crop)
        # Preenche completamente 128x115 e corta excesso (sem deformar)
        "$IM_CMD" "$in" -alpha on -background "$BG" \
            -resize "${WIDTH}x${HEIGHT}^" \
            -gravity center -extent "${WIDTH}x${HEIGHT}" \
            -define png:color-type=6 "png32:$out"
        ;;
    stretch)
        # Deforma para exatamente 128x115
        "$IM_CMD" "$in" -alpha on -resize "${WIDTH}x${HEIGHT}!" \
            -define png:color-type=6 "png32:$out"
        ;;
    *)
        echo "Modo inválido: $MODE (use pad|crop|stretch)"
        exit 1
        ;;
    esac
}

process_file_sips() {
    # Fallback: sips só faz stretch simples
    local in="$1"
    local out="$2"
    sips -s format png "$in" --out "$out" >/dev/null
    sips -z "$HEIGHT" "$WIDTH" "$out" >/dev/null
}

process_path() {
    local p="$1"
    if [ -d "$p" ]; then
        # Itera recursivamente
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
            echo "[SKIP] Não é imagem: $p"
        fi
    fi
}

for item in "${inputs[@]}"; do
    process_path "$item"
done

echo "Concluído. Saídas em: $OUTDIR"
