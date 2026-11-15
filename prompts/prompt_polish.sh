#!/bin/bash
DESC="Polish clipboard sentence"
set -euo pipefail

# Preserve trailing newlines with a sentinel; stop if clipboard reading fails.
clipboard=$(pbpaste && printf '.')
clipboard=${clipboard%.}

printf '%s%s%s' 'Can you help me polish the following sentence? "' "$clipboard" '"' | pbcopy
