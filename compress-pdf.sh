#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $(basename "$0") INPUT.pdf [OUTPUT.pdf] [screen|ebook|printer|prepress|default]"
  echo "Default output: INPUT-compressed.pdf; default quality: ebook"
}

if [[ ${1:-} == --help || ${1:-} == -h ]]; then
  usage
  exit 0
fi
if (( $# < 1 || $# > 3 )); then
  usage >&2
  exit 1
fi

input=$1
output=${2:-"${input%.*}-compressed.pdf"}
quality=${3:-ebook}

if ! command -v gs >/dev/null 2>&1; then
  echo "Ghostscript is required. On macOS, install it with: brew install ghostscript" >&2
  exit 1
fi
if [[ ! -f "$input" ]]; then
  echo "Input file not found: $input" >&2
  exit 1
fi
if [[ -e "$output" || -L "$output" ]]; then
  echo "Output already exists; choose another filename: $output" >&2
  exit 1
fi
case "$quality" in
  screen|ebook|printer|prepress|default) ;;
  *) echo "Invalid quality: $quality" >&2; usage >&2; exit 1 ;;
esac

# Prefix relative paths so filenames beginning with '-' are treated as files.
[[ "$input" == /* ]] || input="./$input"
[[ "$output" == /* ]] || output="./$output"

gs -sDEVICE=pdfwrite -dCompatibilityLevel=1.4 \
  "-dPDFSETTINGS=/$quality" -dNOPAUSE -dBATCH \
  "-sOutputFile=$output" -f "$input"

echo "Saved: $output"
