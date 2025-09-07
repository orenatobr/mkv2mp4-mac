#!/usr/bin/env bash
set -euo pipefail

KEEP_SOURCES="no"
DRY_RUN="no"
TARGET_DIRS=()

# --- Parse flags ---
while (("$#")); do
	case "$1" in
	--keep)
		KEEP_SOURCES="yes"
		shift
		;;
	--dry-run)
		DRY_RUN="yes"
		shift
		;;
	-*)
		echo "Unknown option: $1" >&2
		exit 1
		;;
	*)
		TARGET_DIRS+=("$1")
		shift
		;;
	esac
done

if ! command -v chdman >/dev/null 2>&1; then
	echo "Error: 'chdman' not found in PATH." >&2
	exit 1
fi

if [ "${#TARGET_DIRS[@]}" -eq 0 ]; then
	TARGET_DIRS=(".")
fi

run() {
	echo "+ $*"
	[ "$DRY_RUN" = "no" ] && "$@"
}

FOUND_ANY="no"

# Use find + sort + while loop (portable, no mapfile)
find "${TARGET_DIRS[@]}" -type f -iname '*.cue' -print0 | sort -z |
	while IFS= read -r -d '' CUE_PATH; do
		FOUND_ANY="yes"

		DIR="$(dirname "$CUE_PATH")"
		BASE="$(basename "$CUE_PATH")"
		NAME="${BASE%.*}"
		CHD_PATH="$DIR/$NAME.chd"
		ISO_PATH="$DIR/$NAME.iso"

		if [ -f "$ISO_PATH" ]; then
			echo "[SKIP] ISO already exists: $ISO_PATH"
			continue
		fi

		echo "========================================"
		echo "[CUE] $CUE_PATH"
		echo "[CHD] $CHD_PATH"
		echo "[ISO] $ISO_PATH"

		run chdman createcd -i "$CUE_PATH" -o "$CHD_PATH"
		run chdman extractraw -i "$CHD_PATH" -o "$ISO_PATH" -f

		if [ "$KEEP_SOURCES" = "no" ]; then
			run rm -f -- "$CUE_PATH" "$CHD_PATH"
		else
			echo "[KEEP] Keeping: $CUE_PATH and $CHD_PATH"
		fi

		echo "[OK] Created: $ISO_PATH"
	done

if [ "$FOUND_ANY" = "no" ]; then
	echo "No .cue files found in: ${TARGET_DIRS[*]}"
fi

echo "Done."
