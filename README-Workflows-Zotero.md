# Emacs workflows from Zotero Projects

`workflows-zotero-sync.py` creates one workflow directory for each direct child
of the Zotero `Projects` collection. Names retain Zotero's exact spelling,
spaces, and capitalization. It only manages folder names: existing desktop
and tab files stay intact; new project folders start empty. Other workflow
folders are preserved. No references or PDF paths are read.

Quit Emacs before applying a sync so it cannot save into an old folder path.
Zotero must be running with its local API enabled for the default mode:

```sh
workflows-zotero-sync.py --dry-run
workflows-zotero-sync.py
```

For offline use, read the personal library database in read-only mode:

```sh
workflows-zotero-sync.py --database ~/Zotero/zotero.sqlite --dry-run
workflows-zotero-sync.py --database ~/Zotero/zotero.sqlite
```

Associate an existing folder whose name differs substantially on the first run:

```sh
workflows-zotero-sync.py --adopt LearningSwitchedLinearSystems=learningsls
```

Case-only differences are matched automatically. The hidden file
`workflows/.zotero-projects.json` records collection keys, so subsequent Zotero
renames move the same workflow folders. Removed projects' folders are kept.
The script refuses conflicting destinations and rolls folder changes back if
an operation fails. Avoid other folder edits during a sync.

Case-equivalent Zotero projects (such as `BQRLG` and `bQRLG`) cannot have
separate names on a case-insensitive filesystem. Choose an exact spelling with
`--case-name BQRLG` or `--case-name bQRLG`; both collection keys will share that
folder. The manifest remembers the choice for later runs.

Use `--workflows PATH`, `--root NAME`, `--root-key KEY`, or `--library users/0`
to override the destination or collection selection. `--database` supports
the local personal library only; use the API for group libraries.

After renaming the last-used workflow, load its new name with
`M-x my-load-session` in Emacs to refresh the startup session selection.
