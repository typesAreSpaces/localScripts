#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") <submodule-path>

Remove a git submodule from the current repository.

Arguments:
  <submodule-path>  Path of the submodule as listed in .gitmodules,
                    relative to the repository root (trailing slash ok).

What it does (automatically):
  1. Check that <submodule-path> is a registered submodule.
  2. Run 'git submodule deinit', which stops if the submodule has local changes.
  3. Run 'git rm' to remove it from the index and .gitmodules.
  4. Delete its cloned repository under .git/modules/.

Nothing is committed. Review the staged changes and commit them yourself.

Options:
  -h, --help        Show this help and exit.

Example:
  $(basename "$0") vendor/lib
  git commit -m "Remove vendor/lib submodule"
EOF
}

if [[ $# -eq 1 && ( "$1" == "-h" || "$1" == "--help" ) ]]; then
  usage
  exit 0
fi

if [[ $# -ne 1 ]]; then
  usage >&2
  exit 1
fi

root="$(git rev-parse --show-toplevel)"
cd "$root"

path="${1%/}"

# Verify this path is a registered submodule.
found=false
name=""
while IFS= read -r key; do
  if [[ "$(git config -f .gitmodules --get "$key")" == "$path" ]]; then
    found=true
    # The name can differ from the path; .git/modules/ is keyed by name.
    name="${key#submodule.}"
    name="${name%.path}"
    break
  fi
done < <(git config -f .gitmodules --name-only \
  --get-regexp '^submodule\..*\.path$' || true)

if [[ "$found" != true ]]; then
  printf 'Submodule not found: %s\n' "$path" >&2
  exit 1
fi

# Refuse removal if the submodule contains local changes.
git submodule deinit -- "$path"
git rm -- "$path"

# Delete the submodule's cloned repository so the path can be re-added.
modules_dir="$(git rev-parse --path-format=absolute --git-common-dir)/modules/$name"
if [[ -n "$name" && -d "$modules_dir" ]]; then
  rm -rf -- "$modules_dir"
  printf 'Deleted %s\n' "$modules_dir"
fi

printf 'Removed submodule: %s\nReview and commit the staged changes.\n' "$path"
