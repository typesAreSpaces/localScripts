#!/usr/bin/env bash
# Interactive disk cleanup. Asks before every step (default: No).
#   ./cleanup-disk.sh        run interactively
#   ./cleanup-disk.sh -n     dry run: show what would be done
set -uo pipefail

DRY_RUN=0
[[ "${1:-}" == "-n" ]] && DRY_RUN=1

bold() { printf '\n\033[1m%s\033[0m\n' "$*"; }

size_of() {
  local total=""
  for p in "$@"; do [[ -e "$p" ]] && total+="$(du -sh "$p" 2>/dev/null | cut -f1) "; done
  echo "${total:-0}"
}

ask() {
  local reply
  read -r -p "  -> $1 [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

run() {
  echo "     \$ $*"
  (( DRY_RUN )) || eval "$@"
}

# Remove paths, falling back to sudo when not owned by the user.
remove() {
  for p in "$@"; do
    [[ -e "$p" ]] || continue
    if [[ -w "$(dirname "$p")" ]]; then run "rm -rf \"$p\""; else run "sudo rm -rf \"$p\""; fi
  done
}

step() { # step "description" path...  (then a command block via $CMD)
  local desc="$1"; shift
  echo "  $desc  ($(size_of "$@"))"
}

before=$(df -k /System/Volumes/Data | awk 'NR==2 {print $4}')
(( DRY_RUN )) && bold "DRY RUN: nothing will be deleted"

########################################################################
bold "== SAFE: caches and build artifacts (regenerate automatically) =="

step "Homebrew old versions + download cache" ~/Library/Caches/Homebrew
ask "Run brew cleanup --prune=all?" && run "brew cleanup --prune=all"

C=~/Library/Caches
for d in BraveSoftware Thunderbird Firefox com.spotify.client bazel; do
  [[ -e "$C/$d" ]] || continue
  step "App cache: $d (quit the app first)" "$C/$d"
  ask "Delete $C/$d?" && remove "$C/$d"
done

step "Playwright browsers" "$C/ms-playwright"
ask "Delete Playwright browsers?" && remove "$C/ms-playwright"

step "npm cache" ~/.npm
ask "Run npm cache clean --force?" && run "npm cache clean --force"

step "uv cache" ~/.cache/uv
command -v uv >/dev/null && ask "Run uv cache clean?" && run "uv cache clean"

for d in node ghcide stack hie-bios; do
  [[ -e ~/.cache/$d ]] || continue
  step "~/.cache/$d" ~/.cache/$d
  ask "Delete ~/.cache/$d?" && remove ~/.cache/$d
done

step "Julia compiled cache" ~/.julia/compiled
ask "Delete ~/.julia/compiled?" && remove ~/.julia/compiled

step "Xcode DerivedData" ~/Library/Developer/Xcode/DerivedData
ask "Delete Xcode DerivedData?" && remove ~/Library/Developer/Xcode/DerivedData

step "Cabal downloaded package tarballs" ~/.cabal/packages
ask "Delete ~/.cabal/packages?" && remove ~/.cabal/packages

########################################################################
bold "== OPTIONAL: only if you don't use these =="

step "Wolfram Engine (keeps Mathematica)" "/Applications/Wolfram Engine.app" ~/Library/WolframEngine
ask "Remove Wolfram Engine?" && remove "/Applications/Wolfram Engine.app" ~/Library/WolframEngine

step "Wolfram offline documentation" /Library/Wolfram/Documentation
ask "Remove Wolfram offline docs (needs sudo)?" && remove /Library/Wolfram/Documentation

step "Claude desktop VM bundle (re-downloads if needed; quit Claude first)" ~/Library/Application\ Support/Claude/vm_bundles
ask "Remove Claude VM bundle?" && remove ~/Library/Application\ Support/Claude/vm_bundles

step "Rust nightly toolchain" ~/.rustup/toolchains/nightly-aarch64-apple-darwin
ask "Uninstall Rust nightly?" && run "rustup toolchain uninstall nightly"

step "MacTeX" /opt/homebrew/Caskroom/mactex
ask "Uninstall MacTeX cask?" && run "brew uninstall --cask mactex"

step "Codex data and runtimes" ~/.codex ~/.cache/codex-runtimes
ask "Remove Codex data?" && remove ~/.codex ~/.cache/codex-runtimes

step "MATLAB R2026a" /Applications/MATLAB_R2026a.app ~/Library/Application\ Support/MathWorks
ask "Remove MATLAB?" && remove /Applications/MATLAB_R2026a.app ~/Library/Application\ Support/MathWorks

step "Maple framework" /Library/Frameworks/Maple.framework
ask "Remove Maple framework (needs sudo)?" && remove /Library/Frameworks/Maple.framework

step "Xcode.app (Command Line Tools stay installed)" /Applications/Xcode.app
ask "Remove Xcode.app?" && remove /Applications/Xcode.app

########################################################################
after=$(df -k /System/Volumes/Data | awk 'NR==2 {print $4}')
bold "Done. Freed approximately $(( (after - before) / 1024 / 1024 )) GiB. Free now: $(df -h /System/Volumes/Data | awk 'NR==2 {print $4}')"
