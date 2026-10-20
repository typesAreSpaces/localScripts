#!/bin/bash
# macOS /bin/bash 3.2 compatible. No Python or third-party packages required.
set -euo pipefail
umask 077
export LC_ALL=C
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH

usage() {
cat <<'HELP'
Usage: sioyek-session.sh [options] COMMAND [NAME]
Commands:
  paths                  Show resolved paths (does not change Sioyek).
  save NAME              Save a new, immutable session; quit Sioyek first.
  list                   List saved sessions and automatic backups.
  restore NAME           Back up current state, then restore a session.
  restore-backup NAME    Back up current state, then restore an automatic backup.
Options (must precede command):
  --state-dir DIR        Default: ~/Library/Application Support/sioyek
  --local-db FILE        Override local.db independently.
  --shared-db FILE       Override shared.db (e.g. shared_database_path config).
  --last-file FILE       Override last_document_path.txt.
  --store DIR            Default: ~/Library/Application Support/Sioyek Sessions
  -h, --help             Show help.
Environment equivalents: SIOYEK_STATE_DIR, SIOYEK_LOCAL_DB, SIOYEK_SHARED_DB,
SIOYEK_LAST_FILE, SIOYEK_SESSION_STORE. Options override environment values.
Names: 1–80 ASCII letters/digits/dots/underscores/hyphens, starting alphanumeric.
Use a new name for every save. Restore replaces BOTH databases, including
annotations and history; it does not merge them. PDFs/configs are not copied.
No automatic quit, forced termination, or launch. Keep Sioyek closed throughout.
This tool does not promise restoration of goto_tab, windows, or tab order.
HELP
}
die() { echo "Error: $*" >&2; exit 1; }
state=${SIOYEK_STATE_DIR:-"$HOME/Library/Application Support/sioyek"}
local_db=${SIOYEK_LOCAL_DB:-}
shared_db=${SIOYEK_SHARED_DB:-}
last_file=${SIOYEK_LAST_FILE:-}
store=${SIOYEK_SESSION_STORE:-"$HOME/Library/Application Support/Sioyek Sessions"}
while [ $# -gt 0 ]; do
  case $1 in
    -h|--help) usage; exit 0 ;;
    --state-dir|--local-db|--shared-db|--last-file|--store)
      [ $# -ge 2 ] || die "Missing value for $1"
      case $1 in
        --state-dir) state=$2 ;; --local-db) local_db=$2 ;;
        --shared-db) shared_db=$2 ;; --last-file) last_file=$2 ;; --store) store=$2 ;;
      esac
      shift 2 ;;
    --*) die "Unknown option: $1" ;;
    *) break ;;
  esac
done
local_db=${local_db:-"$state/local.db"}
shared_db=${shared_db:-"$state/shared.db"}
last_file=${last_file:-"$state/last_document_path.txt"}
[ $# -ge 1 ] || { usage; exit 1; }
cmd=$1; shift
case $cmd in
  save|restore|restore-backup)
    [ $# -eq 1 ] || die "$cmd requires exactly one name"
    name=$1
    [ ${#name} -le 80 ] || die "Name too long"
    case $name in ''|[!a-zA-Z0-9]*|*[!a-zA-Z0-9._-]*) die "Invalid name" ;; esac ;;
  paths|list) [ $# -eq 0 ] || die "Unexpected arguments" ;;
  *) die "Unknown command: $cmd" ;;
esac
# Require existing parent directories; never create an accidentally mistyped live path.
canonical_file() {
  case $1 in /*) ;; *) die "Use an absolute path: $1" ;; esac
  [ ! -L "$1" ] || die "Symlink state files are unsupported: $1"
  local parent base
  parent=$(dirname "$1"); base=$(basename "$1")
  [ -d "$parent" ] || die "Missing directory: $parent"
  printf '%s/%s\n' "$(cd "$parent" && pwd -P)" "$base"
}
local_db=$(canonical_file "$local_db")
shared_db=$(canonical_file "$shared_db")
last_file=$(canonical_file "$last_file")
[ "$local_db" != "$shared_db" ] && [ "$local_db" != "$last_file" ] && [ "$shared_db" != "$last_file" ] || die "Live paths must be distinct"
files=("$local_db" "$shared_db" "$last_file")
keys=(local.db shared.db last_document_path.txt)
if [ "$cmd" = paths ]; then
  printf 'local_db: %s\nshared_db: %s\nlast_file: %s\nstore: %s\n' "$local_db" "$shared_db" "$last_file" "$store"
  exit 0
fi
case $store in /*) ;; *) die "Store must be an absolute path" ;; esac
mkdir -p "$store"
store=$(cd "$store" && pwd -P)
lock="$store/.lock"
mkdir "$lock" 2>/dev/null || die "Store locked: $lock (see README for stale-lock recovery)"
printf '%s\n' "$$" > "$lock/pid"
stage=''; rollback=''; committing=0
cleanup() {
  local rc=$? i tmp
  trap - EXIT HUP INT TERM
  if [ "$committing" -eq 1 ]; then
    echo "Restore interrupted; attempting rollback from $rollback" >&2
    for i in 0 1 2; do
      if [ -f "$rollback/${keys[$i]}" ]; then
        tmp=$(mktemp "${files[$i]}.rollback.XXXXXX") || continue
        if cp -p "$rollback/${keys[$i]}" "$tmp" && mv -f "$tmp" "${files[$i]}"; then :
        else echo "ROLLBACK FAILED: ${files[$i]}; recover from $rollback" >&2; fi
      elif [ "$i" -eq 2 ]; then
        rm -f "${files[$i]}"
      fi
    done
    rc=1
  fi
  [ -z "$stage" ] || rm -rf "$stage"
  rm -f "$lock/pid" "$lock/checksums"
  rmdir "$lock" || true
  exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
[ ! -L "$store/sessions" ] && [ ! -L "$store/backups" ] || die "Symlink storage subdirectories are unsupported"
mkdir -p "$store/sessions" "$store/backups"
if [ "$cmd" = list ]; then
  for kind in sessions backups; do
    echo "$kind:"
    for entry in "$store/$kind"/*; do
      [ -d "$entry" ] || continue
      printf '  %s\n' "${entry##*/}"
    done
  done
  exit 0
fi
assert_closed() {
  local rc f suffix
  if pgrep -ix sioyek >/dev/null; then die "Quit all Sioyek instances with Cmd-Q first"; else
    rc=$?; [ "$rc" -eq 1 ] || die "Process check failed"
  fi
  for f in "${files[@]}"; do
    [ ! -L "$f" ] || die "Refusing symlink: $f"
    [ ! -e "$f" ] || [ -f "$f" ] || die "Not a regular file: $f"
    if [ -e "$f" ]; then
      if /usr/sbin/lsof -t "$f" >/dev/null 2>&1; then die "File is open: $f"; else
        rc=$?; [ "$rc" -eq 1 ] || die "Open-file check failed: $f"
      fi
    fi
  done
  for f in "$local_db" "$shared_db"; do
    for suffix in -wal -shm -journal; do
      [ ! -e "$f$suffix" ] && [ ! -L "$f$suffix" ] || die "SQLite sidecar present: $f$suffix. Reopen Sioyek and quit cleanly; do not delete it manually."
    done
  done
}
validate_db() {
  [ -s "$1" ] && [ ! -L "$1" ] || die "Missing/empty/symlink database: $1"
  [ "$(sqlite3 -readonly "$1" 'PRAGMA integrity_check;')" = ok ] || die "SQLite integrity check failed: $1"
}
validate_snapshot() {
  local dir=$1 key
  [ -f "$dir/FORMAT-1" ] && [ -f "$dir/SHA256SUMS" ] || die "Not a supported snapshot: $dir"
  for key in local.db shared.db last_document_path.txt FORMAT-1 SHA256SUMS last-file-absent; do
    [ ! -L "$dir/$key" ] || die "Symlink in snapshot: $dir/$key"
  done
  validate_db "$dir/local.db"; validate_db "$dir/shared.db"
  if [ -f "$dir/last_document_path.txt" ]; then
    [ ! -e "$dir/last-file-absent" ] || die "Ambiguous last-file state"
  else
    [ -f "$dir/last-file-absent" ] || die "Incomplete last-file state"
  fi
  # Generate the expected manifest ourselves; never execute or trust stored paths.
  (cd "$dir"; shasum -a 256 local.db shared.db FORMAT-1
   if [ -f last_document_path.txt ]; then shasum -a 256 last_document_path.txt; else shasum -a 256 last-file-absent; fi) > "$lock/checksums"
  cmp -s "$lock/checksums" "$dir/SHA256SUMS" || die "Snapshot checksum mismatch: $dir"
  rm -f "$lock/checksums"
}
snapshot() {
  local dest=$1 i
  [ ! -e "$dest" ] && [ ! -L "$dest" ] || die "Snapshot already exists: $dest"
  assert_closed
  stage=$(mktemp -d "$store/.stage.XXXXXX")
  for i in 0 1; do
    validate_db "${files[$i]}"
    cp -p "${files[$i]}" "$stage/${keys[$i]}"
  done
  if [ -f "$last_file" ]; then cp -p "$last_file" "$stage/last_document_path.txt"; else : > "$stage/last-file-absent"; fi
  printf 'Sioyek state snapshot format 1\n' > "$stage/FORMAT-1"
  (cd "$stage"; shasum -a 256 local.db shared.db FORMAT-1
   if [ -f last_document_path.txt ]; then shasum -a 256 last_document_path.txt; else shasum -a 256 last-file-absent; fi) > "$stage/SHA256SUMS"
  validate_snapshot "$stage"
  assert_closed
  for i in 0 1 2; do
    if [ -f "${files[$i]}" ]; then cmp -s "${files[$i]}" "$stage/${keys[$i]}" || die "State changed during copy; retry with Sioyek closed"
    else [ "$i" -eq 2 ] && [ -f "$stage/last-file-absent" ] || die "State disappeared during copy"; fi
  done
  mv "$stage" "$dest"; stage=''
}
if [ "$cmd" = save ]; then
  snapshot "$store/sessions/$name"
  echo "Saved: $store/sessions/$name"
  exit 0
fi
kind=sessions; [ "$cmd" != restore-backup ] || kind=backups
source_dir="$store/$kind/$name"
[ -d "$source_dir" ] && [ ! -L "$source_dir" ] || die "Snapshot not found or symlink: $source_dir"
validate_snapshot "$source_dir"
assert_closed
backup_name="$(date -u +%Y%m%dT%H%M%SZ)-$$"
rollback="$store/backups/$backup_name"
snapshot "$rollback"
echo "Current state backed up: $rollback"
# Prepare all incoming files before replacing live state. Each rename is atomic,
# but the multi-file restore is not crash-atomic. Backup enables manual recovery.
stage=$(mktemp -d "$store/.restore.XXXXXX")
cp -p "$source_dir/"* "$stage/"
validate_snapshot "$stage"
assert_closed
committing=1
for i in 0 1 2; do
  if [ -f "$stage/${keys[$i]}" ]; then
    tmp=$(mktemp "${files[$i]}.incoming.XXXXXX")
    cp -p "$stage/${keys[$i]}" "$tmp"
    mv -f "$tmp" "${files[$i]}"
  else
    rm -f "$last_file"
  fi
done
validate_db "$local_db"; validate_db "$shared_db"
committing=0
echo "Restored: $name. You may now open Sioyek."
