#!/usr/bin/env bash

FILE_EXT="*.tex"
DIR="${1:-.}"

find "$DIR" -type f -name "$FILE_EXT" -print0 | while IFS= read -r -d '' file; do
    if file "$file" | grep -q text; then
        typos=$(aspell list < "$file" | sort -u)

        if [ -n "$typos" ]; then
            echo "==== Typos in: $file ===="
            echo "$typos"
            echo
        fi
    fi
done
