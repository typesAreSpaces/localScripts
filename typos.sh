#!/usr/bin/env bash

DIR="${1:-.}"

find "$DIR" -type f -name "*.tex" -print0 | while IFS= read -r -d '' file; do
    if file "$file" | grep -q text; then
        typos=$(aspell list < "$file" | sort -u)

        if [ -n "$typos" ]; then
            echo "==== Typos in: $file ===="
            echo "$typos"
            echo
        fi
    fi
done
