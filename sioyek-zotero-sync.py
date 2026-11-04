#!/usr/bin/env python3
"""Mirror direct children of Zotero Projects as sioyek-session.sh snapshots."""
import argparse
from contextlib import closing
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from urllib.error import HTTPError, URLError
from urllib.parse import unquote, urlencode, urlsplit
from urllib.request import Request, urlopen

HOME = Path.home()
STATE = HOME / 'Library/Application Support/sioyek'
STORE = HOME / 'Library/Application Support/Sioyek Sessions'
MANIFEST = 'zotero-projects.json'


class API:
    def __init__(self, base, library):
        self.base = base.rstrip('/') + '/api/' + library.strip('/')
        self.version = None

    def get(self, route, **params):
        url = self.base + '/' + route
        if params:
            url += '?' + urlencode(params)
        with urlopen(Request(url, headers={'Zotero-API-Version': '3'}), timeout=30) as r:
            version = r.headers.get('Last-Modified-Version')
            if version and self.version and version != self.version:
                raise RuntimeError('Zotero library changed while reading; retry.')
            if version:
                self.version = version
            return json.load(r)

    def all(self, route):
        result = []
        while True:
            page = self.get(route, limit=100, start=len(result))
            if not isinstance(page, list):
                raise RuntimeError('Expected a list from Zotero: ' + route)
            result.extend(page)
            if len(page) < 100:
                return result


def session_name(name, key):
    name = re.sub(r'[^A-Za-z0-9._-]+', '-', name).strip('.-_')
    return (name or 'Project-' + key)[:80]


def read_json(path, default):
    return json.loads(path.read_text()) if path.exists() else default


def pdf_path(item):
    href = item.get('links', {}).get('enclosure', {}).get('href', '')
    url = urlsplit(href)
    if url.scheme == 'file' and url.netloc in ('', 'localhost'):
        return Path(unquote(url.path))
    return None


def discover(api, root_name, root_key, skip_missing):
    collections = api.all('collections')
    roots = [c for c in collections if c['key'] == root_key] if root_key else [
        c for c in collections if not c['data']['parentCollection'] and c['data']['name'] == root_name]
    if len(roots) != 1:
        raise RuntimeError('Expected exactly one root collection; use --root-key to disambiguate.')
    root = roots[0]
    children = {}
    for c in collections:
        children.setdefault(c['data']['parentCollection'], []).append(c)
    projects = children.get(root['key'], [])
    if not projects:
        raise RuntimeError('Root has no project subcollections; refusing to empty the session store.')
    planned, missing, cache = {}, [], {}
    for project in sorted(projects, key=lambda c: (c['data']['name'].casefold(), c['key'])):
        pending, paths, seen = [project], set(), set()
        while pending:
            collection = pending.pop()
            if collection['key'] in seen:
                raise RuntimeError('Cycle in collection hierarchy')
            seen.add(collection['key'])
            pending.extend(children.get(collection['key'], []))
            items = api.all('collections/' + collection['key'] + '/items')
            # Collection /items includes attachments; also fetch children explicitly
            # for linked/standalone items and API implementations omitting children.
            attachments = {i['key']: i for i in items if i['data']['itemType'] == 'attachment'}
            for item in items:
                if item['data']['itemType'] not in ('attachment', 'note', 'annotation') and item.get('meta', {}).get('numChildren', 0):
                    if item['key'] not in cache:
                        cache[item['key']] = api.all('items/' + item['key'] + '/children')
                    attachments.update({a['key']: a for a in cache[item['key']] if a['data']['itemType'] == 'attachment'})
            for item in attachments.values():
                data = item['data']
                if data.get('deleted'):
                    continue
                if data.get('contentType') != 'application/pdf' and not data.get('filename', '').lower().endswith('.pdf'):
                    continue
                path = pdf_path(item)
                if path is None or not path.is_file():
                    missing.append(project['data']['name'] + ': ' + item['key'] + ' (' + (str(path) if path else 'no local file') + ')')
                    continue
                if '\n' in str(path) or '\r' in str(path):
                    raise RuntimeError('Sioyek tab paths cannot contain line breaks: ' + str(path))
                paths.add(str(path))
        name = session_name(project['data']['name'], project['key'])
        if any(p['name'] == name for p in planned.values()):
            name = name[:71] + '-' + project['key']
        planned[project['key']] = {'name': name, 'title': project['data']['name'], 'paths': sorted(paths)}
    if missing:
        print('Unavailable PDFs:\n  ' + '\n  '.join(sorted(set(missing))), file=sys.stderr)
        if not skip_missing:
            raise RuntimeError('Missing PDFs; sync cancelled. Download them in Zotero or use --skip-missing.')
    return root, planned


def assert_closed(state):
    check = subprocess.run(['pgrep', '-ix', 'sioyek'], capture_output=True)
    if check.returncode != 1:
        raise RuntimeError('Quit Sioyek with Cmd-Q before syncing (or process check failed).')
    for db in state.glob('*.db'):
        if any(Path(str(db) + suffix).exists() for suffix in ('-wal', '-shm', '-journal')):
            raise RuntimeError('SQLite sidecar present; reopen Sioyek and quit cleanly: ' + str(db))


def backup_tree(source, destination):
    if source.exists():
        shutil.copytree(source, destination)
        for db in source.rglob('*.db'):
            with closing(sqlite3.connect(db.as_uri() + '?mode=ro', uri=True)) as src, closing(sqlite3.connect(destination / db.relative_to(source))) as dst:
                src.backup(dst)
                if dst.execute('pragma integrity_check').fetchone()[0] != 'ok':
                    raise RuntimeError('Backup database integrity check failed: ' + str(db))


def snapshot(source, dest, paths):
    dest.mkdir()
    for name in ('local.db', 'shared.db'):
        with closing(sqlite3.connect((source / name).as_uri() + '?mode=ro', uri=True)) as src, closing(sqlite3.connect(dest / name)) as dst:
            src.backup(dst)
            if dst.execute('pragma integrity_check').fetchone()[0] != 'ok':
                raise RuntimeError('Database integrity check failed: ' + str(source / name))
    (dest / 'FORMAT-1').write_text('Sioyek state snapshot format 1\n')
    last = 'last_document_path.txt' if paths else 'last-file-absent'
    (dest / last).write_text(''.join(p + '\n' for p in paths))
    names = ['local.db', 'shared.db', 'FORMAT-1', last]
    (dest / 'SHA256SUMS').write_text(''.join(hashlib.sha256((dest / n).read_bytes()).hexdigest() + '  ' + n + '\n' for n in names))


def atomic_text(path, text):
    fd, temp = tempfile.mkstemp(prefix='.' + path.name + '-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as f:
            f.write(text)
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


def run(args):
    api = API(args.api, args.library)
    root, plan = discover(api, args.root, args.root_key, args.skip_missing)
    store, state = args.store.expanduser().resolve(), args.state_dir.expanduser().resolve()
    if store == state or store in state.parents or state in store.parents:
        raise RuntimeError('State and session store must be separate directories.')
    sessions = store / 'sessions'
    old = read_json(store / MANIFEST, {}).get('projects', {})
    adopt = {}
    for value in args.adopt:
        title, sep, source = value.partition('=')
        if not sep or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]{0,79}', source):
            raise RuntimeError('--adopt requires ProjectTitle=ExistingSessionName')
        if title not in [p['title'] for p in plan.values()]:
            raise RuntimeError('Unknown project for --adopt: ' + title)
        adopt[title] = source
    existing = {p.name: p for p in sessions.iterdir()} if sessions.exists() else {}
    if any(not p.is_dir() or p.is_symlink() for p in existing.values()):
        raise RuntimeError('Session store contains symlinks or non-directories.')
    current = (store / 'current').read_text().strip() if (store / 'current').exists() else ''
    desired_names = {p['name'] for p in plan.values()}
    if len(desired_names) != len(plan):
        raise RuntimeError('Session name collision; rename the colliding Zotero collection.')
    active_target = None
    for key, p in plan.items():
        source = adopt.get(p['title'], old.get(key, {}).get('name', p['name']))
        p['source'] = source
        if source == current:
            active_target = p
        verb = 'Update' if source in existing else 'Create'
        print(f"{verb}: {p['name']} ({len(p['paths'])} PDFs)" + (f' [from {source}]' if source != p['name'] else ''))
    retired = sorted(set(existing) - desired_names)
    if retired:
        print('Archive previous sessions: ' + ', '.join(retired))
    manifest = {'format': 1, 'library': args.library, 'root_key': root['key'], 'projects': {
        k: {field: p[field] for field in ('name', 'title')} for k, p in plan.items()}}
    if args.dry_run:
        print('Dry run; no files changed.')
        return
    store.mkdir(parents=True, exist_ok=True)
    lock = store / '.lock'  # Same lock as sioyek-session.sh.
    lock.mkdir()
    try:
        (lock / 'pid').write_text(str(os.getpid()) + '\n')
        assert_closed(state)
        # Refuse unsafe tree layouts before recursive copy or session replacement.
        if any(p.is_symlink() for base in (store, state) for p in base.rglob('*')):
            raise RuntimeError('Symlinks in state/store are unsupported.')
        unchanged = not retired and read_json(store / MANIFEST, {}) == manifest
        for p in plan.values():
            tabfile = sessions / p['name'] / 'last_document_path.txt'
            actual = tabfile.read_text().splitlines() if tabfile.exists() else []
            unchanged = unchanged and (sessions / p['name']).is_dir() and actual == p['paths'] and p['source'] == p['name']
        if active_target:
            live = state / 'last_document_path.txt'
            unchanged = unchanged and (live.read_text().splitlines() if live.exists() else []) == active_target['paths']
        if unchanged:
            print('Already in sync; no files changed.')
            return
        # Outside the store so backing up never recursively includes its own output.
        backup = store.parent / 'Sioyek Zotero Sync Backups' / datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S.%fZ')
        backup.mkdir(parents=True)
        backup_tree(state, backup / 'state')
        # Exclude the transient lock from the restorable backup.
        shutil.copytree(store, backup / 'store', ignore=shutil.ignore_patterns('.lock'))
        print('Backup: ' + str(backup))
        with tempfile.TemporaryDirectory(prefix='.zotero-stage-', dir=store) as tmp:
            stage = Path(tmp) / 'sessions'
            stage.mkdir()
            for p in plan.values():
                source = existing.get(p['source'], state)
                if active_target is p:
                    source = state  # Preserve the active session's latest annotations/history.
                snapshot(source, stage / p['name'], p['paths'])
            assert_closed(state)
            try:
                if sessions.exists():
                    sessions.rename(Path(tmp) / 'previous-sessions')
                stage.rename(sessions)
                atomic_text(store / MANIFEST, json.dumps(manifest, indent=2, ensure_ascii=False) + '\n')
                if active_target:
                    live = state / 'last_document_path.txt'
                    if active_target['paths']:
                        atomic_text(live, ''.join(p + '\n' for p in active_target['paths']))
                    elif live.exists():
                        live.unlink()
                    atomic_text(store / 'current', active_target['name'] + '\n')
                elif current and (store / 'current').exists():
                    (store / 'current').unlink()
            except BaseException:
                # Retain the complete backup and restore the pre-sync store/tab list.
                if sessions.exists():
                    shutil.rmtree(sessions)
                if (backup / 'store/sessions').exists():
                    shutil.copytree(backup / 'store/sessions', sessions)
                for name in (MANIFEST, 'current'):
                    target = store / name
                    if (backup / 'store' / name).exists():
                        shutil.copy2(backup / 'store' / name, target)
                    elif target.exists():
                        target.unlink()
                live = state / 'last_document_path.txt'
                if (backup / 'state/last_document_path.txt').exists():
                    shutil.copy2(backup / 'state/last_document_path.txt', live)
                elif live.exists():
                    live.unlink()
                raise
        print(f'Synced {len(plan)} project sessions. Open with sioyek-session.sh restore NAME.')
    finally:
        (lock / 'pid').unlink(missing_ok=True)
        lock.rmdir()


def main():
    parser = argparse.ArgumentParser(description=__doc__, epilog='Quit Sioyek before applying. Zotero must be running with its local API enabled. Unmatched sessions are archived in a full backup before replacement.')
    parser.add_argument('--dry-run', action='store_true', help='Preview without writing or requiring Sioyek to close')
    parser.add_argument('--root', default='Projects', help='Top-level Zotero collection (default: Projects)')
    parser.add_argument('--root-key', help='Use a specific collection key instead of its name')
    parser.add_argument('--api', default='http://127.0.0.1:23119')
    parser.add_argument('--library', default='users/0', help='Local API library, e.g. users/0 or groups/123')
    parser.add_argument('--state-dir', type=Path, default=Path(os.environ.get('SIOYEK_STATE_DIR', str(STATE))))
    parser.add_argument('--store', type=Path, default=Path(os.environ.get('SIOYEK_SESSION_STORE', str(STORE))))
    parser.add_argument('--skip-missing', action='store_true', help='Explicitly allow sessions omitting unavailable PDFs')
    parser.add_argument('--adopt', action='append', default=[], metavar='PROJECT=SESSION', help='Migrate an existing differently named session (repeatable)')
    args = parser.parse_args()
    os.umask(0o077)
    try:
        run(args)
    except (RuntimeError, OSError, ValueError, sqlite3.Error, HTTPError, URLError) as exc:
        print('Error: ' + str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
