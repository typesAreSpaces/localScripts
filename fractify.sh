#!/usr/bin/env sh

gsed -i -E 's|([0-9]+)/([0-9]+)|\\frac{\1}{\2}|g' $1
