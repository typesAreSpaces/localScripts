#!/usr/bin/env bash
# Reindent a Maple source file in place using the installed Emacs MapleV package.
# Usage: ./format-maple.sh "path/to/file.mpl"
# Overrides: EMACS=/path/to/emacs MAPLEV_DIR=/path/to/maplev
#            BUTTON_LOCK_DIR=/path/to/button-lock
# Loads MapleV directly, without running your interactive Emacs init file.
set -euo pipefail

if [[ $# -eq 1 && ( $1 == --help || $1 == -h ) ]]; then
    echo "Usage: ${0##*/} FILE.mpl (reindent in place using MapleV)"
    exit 0
fi
if [[ $# -ne 1 ]]; then
    echo "Usage: ${0##*/} FILE.mpl" >&2
    exit 2
fi
if [[ ! -f $1 || ! -r $1 || ! -w $1 ]]; then
    echo "Error: expected a readable, writable file: $1" >&2
    exit 1
fi

emacs_bin=${EMACS:-emacs}
if ! command -v "$emacs_bin" >/dev/null 2>&1; then
    echo "Error: Emacs not found; set EMACS to its executable path." >&2
    exit 1
fi

# The first location is the Straight installation in your default profile.
maplev_dir=${MAPLEV_DIR:-}
if [[ -z $maplev_dir ]]; then
    for config_dir in "$HOME/.config/jose-emacs" "$HOME/.emacs.d" "$HOME/.config/emacs"; do
        if [[ -f "$config_dir/straight/build/maplev/maplev.el" ]]; then
            maplev_dir="$config_dir/straight/build/maplev"
            break
        fi
    done
fi
if [[ -z $maplev_dir || ! -f "$maplev_dir/maplev.el" ]]; then
    echo "Error: MapleV not found; set MAPLEV_DIR to the directory containing maplev.el." >&2
    exit 1
fi
button_lock_dir=${BUTTON_LOCK_DIR:-"$maplev_dir/../button-lock"}

# Pass the path as data, so quotes, spaces, and Lisp characters stay literal.
# Emacs saves only after indentation completes successfully.
MAPLEV_FORMAT_FILE="$1" "$emacs_bin" --batch -Q \
    -L "$maplev_dir" -L "$button_lock_dir" \
    --eval '
(condition-case err
    (progn
      (require (quote cl-lib))
      (require (quote maplev))
      (let ((enable-local-variables nil)
            (enable-local-eval nil)
            (auto-mode-alist nil)
            (make-backup-files nil)
            (backup-inhibited t)
            (create-lockfiles nil))
        (with-current-buffer
            (find-file-noselect (expand-file-name (getenv "MAPLEV_FORMAT_FILE")))
          (maplev-mode)
          (setq-local indent-tabs-mode nil)
          (setq-local require-final-newline nil)
          ;; MapleV normally swallows this error after displaying a message.
          (cl-letf (((symbol-function (quote maplev-indent-handle-grammar-error))
                     (lambda (grammar-error)
                       (error "MapleV: keyword %s out of sequence at position %s"
                              (nth 1 grammar-error) (nth 2 grammar-error)))))
            (let ((inhibit-message t))
              (maplev-indent-buffer)))
          (save-buffer)
          (princ (format "Formatted: %s\n" buffer-file-name)))))
  (error
   (princ (format "format-maple: %s\n" (error-message-string err))
          (quote external-debugging-output))
   (kill-emacs 1)))'
