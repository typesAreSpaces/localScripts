# Sioyek database sessions for macOS

Download `sioyek-session.sh` and run it with macOS Bash. It copies state files into named snapshots; it does not move or edit database rows. No additional software is required beyond the standard macOS command-line utilities, including sqlite3 and shasum.

## First use

In Terminal, change to the folder containing the downloaded script, then:

```bash
/bin/bash ./sioyek-session.sh --help
/bin/bash ./sioyek-session.sh paths
```

Quit Sioyek completely with **Cmd-Q**, then save:

```bash
/bin/bash ./sioyek-session.sh save research-2026-10-20
/bin/bash ./sioyek-session.sh list
```

After using Sioyek for a different project, quit it and save another snapshot:

```bash
/bin/bash ./sioyek-session.sh save teaching-2026-10-20
/bin/bash ./sioyek-session.sh restore research-2026-10-20
```

Open Sioyek normally afterward. Keep it closed for the entire save or restore operation. The script never quits or launches the app. A snapshot name cannot be overwritten: save under a new name to capture later changes. Restoring does not automatically save your current work as another named session, but it always creates a recovery backup.

## What a session includes

- `local.db`: local document-path/hash mappings.
- `shared.db`: reading history/positions and annotations, including marks, bookmarks, highlights, and portals/links, depending on your version.
- `last_document_path.txt`: if present; its absence is also recorded and restored.

**Restoring replaces annotation/history state rather than merging it.** Annotations added after a snapshot disappear from the active database when you restore that snapshot, but remain available in the automatic backup. PDFs, preferences, key bindings, and other application state are not copied. Existing document paths must remain valid. This is a full database snapshot workflow, not selective grouping of documents.

The `opened_books` table is persisted history/position state; its existence does not establish that Sioyek persists the live tab list there. **Restoration of `goto_tab`, open windows, tab order, or automatic reopening has not been tested or guaranteed.** Verify those behaviors with disposable documents before relying on them.

## Paths and configuration

On the inspected Mac, the actual files were found under:

```text
~/Library/Application Support/sioyek/local.db
~/Library/Application Support/sioyek/shared.db
~/Library/Application Support/sioyek/last_document_path.txt
```

These are the script's defaults, not a claim about every Sioyek build. Default snapshot storage is `~/Library/Application Support/Sioyek Sessions`.

Use absolute paths, quoted when they contain spaces. All options go before the command:

```bash
/bin/bash ./sioyek-session.sh \
  --state-dir "$HOME/Library/Application Support/sioyek" \
  --shared-db "$HOME/Documents/Sioyek Data/shared.db" \
  --store "$HOME/Documents/Sioyek Sessions" \
  save research-v2
```

Independent overrides are `--local-db`, `--shared-db`, and `--last-file`. Environment equivalents are `SIOYEK_STATE_DIR`, `SIOYEK_LOCAL_DB`, `SIOYEK_SHARED_DB`, `SIOYEK_LAST_FILE`, and `SIOYEK_SESSION_STORE`. Explicit file overrides take priority over the state-directory default. Options take priority over their corresponding environment variables. The script does not parse Sioyek preferences: if you use `shared_database_path`, supply the actual database file with `--shared-db`.

Sioyek's documented extension substitutions `%{local_database}` and `%{shared_database}` can expose the paths used by the running build. Its diagnostic output may also show resolved database paths. Confirm them before saving; the script requires existing database files and parent directories and rejects symlink state files. Use the real target path for a deliberately symlinked database.

Keep snapshot storage local, private, and outside simultaneously synchronized folders. If your active shared database is synchronized, pause synchronization for the entire operation on all participating devices. Process checks on this Mac cannot detect a remote writer or a sync service replacing a closed database.

## Backups and recovery

Every restore first saves the current state in `backups/<UTC timestamp>-<process ID>`. The command prints the exact path. To recover:

```bash
/bin/bash ./sioyek-session.sh list
/bin/bash ./sioyek-session.sh restore-backup 20261020T180000Z-12345
```

Replace the example ID with an actual backup name. Recovery itself also creates a backup. Use the same path options/environment as the original operation. No automatic pruning is performed; delete old snapshot directories manually only when you no longer need them. Snapshots contain private reading history and annotations; use storage permissions appropriate to that data. Existing file permissions are preserved, and newly created snapshot directories are private by default.

The script serializes operations using `<store>/.lock`. After a crash or forced termination, first confirm no invocation is running, then remove that specific `.lock` directory manually. Never remove a lock belonging to an active operation.

On an ordinary restore failure or catchable signal, the script attempts to roll back from the printed backup. Inspect any rollback failure messages. Individual destination replacements use temporary files and atomic renames, but **the complete multi-file restore is not atomic across power loss, SIGKILL, or disk failure**. After such a failure, keep Sioyek closed and restore the printed backup. If the live databases are missing/corrupt and the normal backup-before-restore check refuses to run, first preserve all affected files and manually copy `local.db`, `shared.db`, and, when present, `last_document_path.txt` from the verified backup to the configured paths. When the backup has `last-file-absent`, the live last-document file should be absent. Do not carry SQLite sidecars across this manual recovery. Seek SQLite recovery help if sidecars exist; they may hold unsaved data.

## Safety behavior and limitations

The script refuses a save/restore if an executable named `sioyek` is running (case-insensitive), if a state file is reported open by `lsof`, or if a database has any `-wal`, `-shm`, or `-journal` sidecar, including empty ones. If sidecars remain, reopen Sioyek and quit cleanly, then retry. Do not delete sidecars to bypass the guard. If process inspection fails, the operation is refused. A renamed executable is covered only by the open-file check while it holds a state file open.

Database copies pass SQLite `integrity_check`; snapshots carry SHA-256 checksums and a format marker. Before publication, a save checks that copied bytes still match the live files. Restore validates its source and prepares incoming copies before replacing files. Checksums detect accidental changes; they do not authenticate snapshots against malicious changes. Use only trusted snapshots and a private store. A successful integrity check does not establish compatibility between different Sioyek versions; keep the same app version for a session set or separately back up before upgrading.

The process/file checks are conservative checks, not an operating-system lock against Sioyek. Starting the app or a writer after the checks can still race the operation. The app must remain closed, and no other program may modify these files. The script does not change your live databases merely to inspect or save them.

## Verification performed

Read-only inspection of the installed databases confirmed `document_hash` in `local.db` and `opened_books`, `marks`, `bookmarks`, `highlights`, and `links` in `shared.db`. In this build, `opened_books` has `path`, `zoom_level`, `offset_x`, `offset_y`, `last_access_time`, and `document_name` columns, plus its ID. These observations are version-specific; the script does not assume or modify that schema.

The actual shutdown guard refused operation while Sioyek was running. Isolated tests use temporary SQLite fixtures and a test-only substitute for process detection, without modifying the installed Sioyek databases. They cover save/restore, duplicate names, backup recovery, spaces in paths, absent last-document files, sidecar rejection, invalid names, checksum rejection, process-check failures, and rollback after an injected mid-restore failure. UI/tab restoration has not been tested.

References:

- [Sioyek: scripting and database documentation](https://sioyek-documentation.readthedocs.io/en/latest/scripting.html)
- [Sioyek: configuration documentation](https://sioyek-documentation.readthedocs.io/en/latest/configuration.html)

## fzf Tab completion (zsh)

With [fzf](https://github.com/junegunn/fzf) installed, add this to `~/.zshrc` *after* fzf's own setup is sourced:

```zsh
eval "$(sioyek-session.sh completion zsh)"
```

Pressing Tab after `sioyek-session.sh restore ` (or `restore-backup `) opens fzf on the saved names, prefilled with any partial name already typed. Press Tab or Enter in fzf to accept a name; Escape cancels. Every other Tab falls through to the previous binding. `sioyek-session.sh names sessions|backups` prints the bare names without taking the store lock.

After changing the script, reload the completion in any already-open terminal:

```zsh
eval "$(~/.local/scripts/sioyek-session.sh completion zsh)"
```

If an older version has already broken the Tab fallback, open a new terminal to reload the original binding and the updated completion together.
