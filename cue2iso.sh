#!/usr/bin/env bash
#
# cue2iso.sh - Convert BIN+CUE and CHD files to ISO format
#
# This script automatically processes:
# - BIN+CUE files: Converts directly to ISO, removing intermediate CHD
# - CHD files: Extracts directly to ISO format
#
# Usage: ./cue2iso.sh [--keep] [--dry-run] [directory1] [directory2] ...
#   --keep     Keep source files after conversion
#   --dry-run  Show what would be done without executing
#
set -euo pipefail

KEEP_SOURCES="no"
DRY_RUN="no"
TARGET_DIRS=()

# --- Parse flags ---
show_help() {
	cat << EOF
Usage: $0 [OPTIONS] [DIRECTORIES...]

Convert BIN+CUE and CHD files to ISO format automatically.

OPTIONS:
  --keep      Keep source files after conversion (default: remove)
  --dry-run   Show what would be done without executing
  --help      Show this help message

DIRECTORIES:
  One or more directories to search for files (default: current directory)

EXAMPLES:
  $0                          # Convert files in current directory
  $0 --keep /path/to/games    # Convert files in specified directory, keep sources
  $0 --dry-run .              # Show what would be converted without doing it

EOF
}

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
	--help|-h)
		show_help
		exit 0
		;;
	-*)
		echo "Unknown option: $1" >&2
		echo "Use --help for usage information." >&2
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

# Function to process CUE files (BIN+CUE format)
process_cue_file() {
	local CUE_PATH="$1"
	local DIR="$(dirname "$CUE_PATH")"
	local BASE="$(basename "$CUE_PATH")"
	local NAME="${BASE%.*}"
	local ISO_PATH="$DIR/$NAME.iso"

	if [ -f "$ISO_PATH" ]; then
		echo "[SKIP] ISO already exists: $ISO_PATH"
		return
	fi

	echo "========================================"
	echo "[CUE+BIN] Processing: $CUE_PATH"
	echo "[ISO] Output: $ISO_PATH"

	# For BIN+CUE, we can convert directly to ISO without intermediate CHD
	# First, try direct conversion using chdman
	local TEMP_CHD="$DIR/$NAME.tmp.chd"
	
	run chdman createcd -i "$CUE_PATH" -o "$TEMP_CHD"
	run chdman extractraw -i "$TEMP_CHD" -o "$ISO_PATH" -f
	
	# Clean up temporary CHD file
	run rm -f -- "$TEMP_CHD"

	if [ "$KEEP_SOURCES" = "no" ]; then
		# Extract BIN filenames from CUE file BEFORE removing it
		local BIN_FILES
		BIN_FILES=$(grep -i "FILE.*\.\(bin\|img\|iso\)" "$CUE_PATH" 2>/dev/null | \
			sed -E 's/.*FILE[[:space:]]+["]?([^"[:space:]]+\.(bin|img|iso))["]?.*/\1/I' | \
			head -20) || true
		
		# Remove the CUE file
		run rm -f -- "$CUE_PATH"
		
		# Remove associated BIN/IMG files if they exist
		if [ -n "$BIN_FILES" ]; then
			echo "[INFO] Found associated data files to remove:"
			while IFS= read -r BIN_FILE; do
				if [ -n "$BIN_FILE" ]; then
					local FULL_BIN_PATH="$DIR/$BIN_FILE"
					if [ -f "$FULL_BIN_PATH" ]; then
						echo "  - $BIN_FILE"
						run rm -f -- "$FULL_BIN_PATH"
					fi
				fi
			done <<< "$BIN_FILES"
		fi
		
		echo "[REMOVED] Removed CUE and associated data files"
	else
		echo "[KEEP] Keeping: $CUE_PATH and associated data files"
	fi

	echo "[OK] Created: $ISO_PATH"
}

# Function to process CHD files
process_chd_file() {
	local CHD_PATH="$1"
	local DIR="$(dirname "$CHD_PATH")"
	local BASE="$(basename "$CHD_PATH")"
	local NAME="${BASE%.*}"
	local ISO_PATH="$DIR/$NAME.iso"

	if [ -f "$ISO_PATH" ]; then
		echo "[SKIP] ISO already exists: $ISO_PATH"
		return
	fi

	echo "========================================"
	echo "[CHD] Processing: $CHD_PATH"
	echo "[ISO] Output: $ISO_PATH"

	run chdman extractraw -i "$CHD_PATH" -o "$ISO_PATH" -f

	if [ "$KEEP_SOURCES" = "no" ]; then
		run rm -f -- "$CHD_PATH"
		echo "[REMOVED] Removed: $CHD_PATH"
	else
		echo "[KEEP] Keeping: $CHD_PATH"
	fi

	echo "[OK] Created: $ISO_PATH"
}

# Process CUE files (BIN+CUE format)
find "${TARGET_DIRS[@]}" -type f -iname '*.cue' -print0 | sort -z |
	while IFS= read -r -d '' CUE_PATH; do
		FOUND_ANY="yes"
		process_cue_file "$CUE_PATH"
	done

# Process standalone CHD files (skip if corresponding CUE file exists)
find "${TARGET_DIRS[@]}" -type f -iname '*.chd' -print0 | sort -z |
	while IFS= read -r -d '' CHD_PATH; do
		DIR="$(dirname "$CHD_PATH")"
		BASE="$(basename "$CHD_PATH")"
		NAME="${BASE%.*}"
		CUE_PATH="$DIR/$NAME.cue"
		
		# Skip if corresponding CUE file exists (already processed above)
		if [ -f "$CUE_PATH" ]; then
			echo "[SKIP] CHD file $CHD_PATH has corresponding CUE file, already processed"
			continue
		fi
		
		FOUND_ANY="yes"
		process_chd_file "$CHD_PATH"
	done

if [ "$FOUND_ANY" = "no" ]; then
	echo "No .cue or .chd files found in: ${TARGET_DIRS[*]}"
fi

echo "Done."
