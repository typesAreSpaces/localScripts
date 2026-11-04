# Zotero project sessions for Sioyek

Run with Zotero open and Sioyek fully quit (Cmd-Q):

```sh
~/.local/scripts/sioyek-zotero-sync.py
```

Preview without writing:

```sh
~/.local/scripts/sioyek-zotero-sync.py --dry-run
```

Each **direct subcollection** of the top-level Zotero `Projects` collection becomes one Sioyek session. A project's PDFs include those in all of its nested subcollections. All local PDF attachments are included, with duplicate file paths removed. Papers without PDF attachments add no tabs. An empty project produces an empty session. Items directly in `Projects` are not assigned a session.

Open a project using the existing session manager:

```sh
sioyek-session.sh restore LearningSwitchedLinearSystems
```

The sync maintains the entire session list: sessions without a matching project are archived in the backup, then removed from the list. Collection keys track projects across renames; session names follow collection names, replacing unsupported characters with hyphens. PDFs stay in Zotero storage. The Zotero library is read only.

Existing sessions retain their databases, annotations, and reading history. New sessions start from the live Sioyek databases. When syncing the active project, its latest live databases are used and its live tab list is updated too. Other live state stays as it was; if its session is retired, the active-session marker is cleared. This uses the same snapshot format and lock as `sioyek-session.sh`. As with that tool, restoring a session replaces both databases rather than merging annotations between sessions.

The script requires Python 3.8+ and Zotero's local API enabled (`extensions.zotero.httpServer.localAPI.enabled`). No third-party Python packages are needed. Missing/download-pending PDFs abort the sync before any session changes. Download those attachments in Zotero and rerun, or explicitly choose `--skip-missing` to omit them. Repeated runs with unchanged memberships do not rewrite the sessions or make more backups.

Before each change, the script backs up the whole session store and live Sioyek state under:

```
~/Library/Application Support/Sioyek Zotero Sync Backups/<UTC timestamp>/
  state/
  store/
```

Backups are retained indefinitely. Exceptions during replacement trigger rollback. For recovery after a machine crash during replacement, quit Sioyek and restore the corresponding `state/` files and `store/` directory from that backup. A crash may leave the store's `.lock` directory; remove that stale lock only after checking that no session command is still running.

The first migration on 2026-11-04 adopted `LearningSLS` as `LearningSwitchedLinearSystems`; the previous `ReviewTACAS` snapshot is in the backups. The original pre-migration backup is also saved at:

```
~/.local/scripts/backups/sioyek-before-zotero-20261104T092408/
```

Advanced options:

```sh
# A different root collection or library:
sioyek-zotero-sync.py --root Project
sioyek-zotero-sync.py --root-key H6WD5SG9 --library users/0

# One-time adoption of an existing session with a different name:
sioyek-zotero-sync.py --adopt ProjectTitle=OldSessionName

# Alternate directories (same environment variables as the session manager):
sioyek-zotero-sync.py --state-dir /absolute/state --store /absolute/store
```

The sync does not support independently overridden database paths such as `SIOYEK_SHARED_DB`; both databases must be inside `--state-dir`. Regression tests use temporary directories and never modify the real apps:

```sh
python3 -m unittest -v test_sioyek_zotero_sync.py
```
