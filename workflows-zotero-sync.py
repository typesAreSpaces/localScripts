#!/usr/bin/env python3
"""Match Emacs workflow folder names to direct children of Zotero Projects."""
import argparse
from contextlib import closing
import json
import os
from pathlib import Path
import sqlite3
import sys
import tempfile
import unicodedata
from urllib.parse import urlencode
from urllib.request import Request, urlopen
from urllib.error import URLError

DEFAULT = Path.home() / '.config/jose-emacs/workflows'
MANIFEST = '.zotero-projects.json'


def name_key(name):
    return unicodedata.normalize('NFD', name).casefold()


def valid_name(name):
    if not isinstance(name, str) or not name or name in ('.', '..') or '/' in name or '\0' in name or name.startswith('.'):
        raise ValueError(f'Invalid workflow folder name: {name!r}')
    return name


def collections(args):
    if args.database:
        if args.library != 'users/0':
            raise ValueError('--database supports the personal library (users/0) only.')
        with closing(sqlite3.connect(args.database.expanduser().resolve().as_uri() + '?mode=ro', uri=True)) as db:
            rows = db.execute('SELECT collectionID, key, collectionName, parentCollectionID FROM collections WHERE libraryID=1').fetchall()
        keys = {row[0]: row[1] for row in rows}
        return [{'key': key, 'data': {'name': name, 'parentCollection': keys.get(parent, False)}}
                for _, key, name, parent in rows]
    result, version = [], None
    while True:
        url = args.api.rstrip('/') + '/api/' + args.library.strip('/') + '/collections?'
        url += urlencode({'limit': 100, 'start': len(result)})
        with urlopen(Request(url, headers={'Zotero-API-Version': '3'}), timeout=30) as response:
            current = response.headers.get('Last-Modified-Version')
            if version and current and version != current:
                raise ValueError('Zotero changed while reading; retry.')
            version = current or version
            page = json.load(response)
        if not isinstance(page, list):
            raise ValueError('Expected a collection list from Zotero.')
        result.extend(page)
        if len(page) < 100:
            return result


def read_json(path):
    return json.loads(path.read_text()) if path.exists() else {}


def atomic_json(path, value):
    fd, temporary = tempfile.mkstemp(prefix='.zotero-manifest-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as stream:
            stream.write(json.dumps(value, indent=2, ensure_ascii=False) + '\n')
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def plan_sync(args):
    all_collections = collections(args)
    roots = [c for c in all_collections if c['key'] == args.root_key] if args.root_key else [
        c for c in all_collections if not c['data']['parentCollection'] and c['data']['name'] == args.root]
    if len(roots) != 1:
        raise ValueError('Expected one root collection; use --root-key to disambiguate.')
    root = roots[0]
    projects = [c for c in all_collections if c['data']['parentCollection'] == root['key']]
    if not projects:
        raise ValueError('The root has no project subcollections.')
    directory = args.workflows.expanduser().resolve()
    manifest_path = directory / MANIFEST
    if manifest_path.is_symlink():
        raise ValueError('The manifest must not be a symlink.')
    old = read_json(manifest_path)
    scope = {'library': args.library, 'root_key': root['key']}
    if old and any(old.get(k) != v for k, v in scope.items()):
        raise ValueError('The existing manifest belongs to a different library/root.')
    existing = {p.name: p for p in directory.iterdir() if not p.name.startswith('.')} if directory.exists() else {}
    titles = [valid_name(c['data']['name']) for c in projects]
    if len(set(titles)) != len(titles):
        raise ValueError('Duplicate Zotero project names cannot have distinct folders.')
    adopt = {}
    for value in args.adopt:
        title, sep, source = value.partition('=')
        if not sep or title not in titles or title in adopt:
            raise ValueError('--adopt requires a unique, known PROJECT=EXISTING_FOLDER.')
        adopt[title] = valid_name(source)
        if source not in existing:
            raise ValueError(f'Adoption source does not exist: {source}')
    groups = {}
    for project in projects:
        groups.setdefault(name_key(project['data']['name']), []).append(project)
    choices = set(args.case_name)
    if choices - set(titles):
        raise ValueError('--case-name must name a Zotero project exactly.')
    plan, manifest_projects = [], {}
    used = set()
    for group in groups.values():
        names = {c['data']['name'] for c in group}
        if len(group) > 1:
            selected = names & choices
            if not selected:
                remembered = {old.get('projects', {}).get(c['key'], {}).get('name') for c in group}
                if len(remembered) == 1 and remembered <= names:
                    selected = remembered
            if len(selected) != 1:
                raise ValueError(f'Case-equivalent project names {sorted(names)!r}; choose one shared folder with --case-name NAME.')
            target = selected.pop()
        else:
            target = group[0]['data']['name']
        sources = set()
        for project in group:
            title, key = project['data']['name'], project['key']
            previous = adopt.get(title, old.get('projects', {}).get(key, {}).get('name'))
            if previous:
                valid_name(previous)
                if previous in existing:
                    sources.add(previous)
            manifest_projects[key] = {'name': target, 'title': title}
        # Match exact names first, then spelling/case-only differences.
        if not sources:
            sources.update(n for n in existing if name_key(n) == name_key(target))
        if len(sources) > 1:
            raise ValueError(f'Multiple existing folders match {target!r}: {sorted(sources)}')
        source = next(iter(sources), None)
        if source:
            if source in used or existing[source].is_symlink() or not existing[source].is_dir():
                raise ValueError(f'Unsafe or multiply assigned source: {source}')
            used.add(source)
        plan.append({'source': source, 'name': target})
    # Do not overwrite unrelated folders, files, or symlinks.
    for entry in plan:
        dest = directory / entry['name']
        if os.path.lexists(dest) and (entry['source'] is None or not dest.samefile(directory / entry['source'])):
            raise ValueError(f'Destination already exists: {dest}')
    manifest = {'format': 1, **scope, 'projects': manifest_projects}
    return directory, sorted(plan, key=lambda p: p['name']), manifest


def run(args):
    directory, plan, manifest = plan_sync(args)
    for entry in plan:
        source, target = entry['source'], entry['name']
        print(f'Create: {target}' if source is None else f'Rename: {source} -> {target}' if source != target else f'Keep: {target}')
    if args.dry_run:
        print('Dry run; no files changed.')
        return
    directory.mkdir(parents=True, exist_ok=True)
    lock = directory / '.zotero-sync.lock'
    lock.mkdir()  # Serialize other instances of this script.
    staged, created, installed = [], [], []
    try:
        # Recheck under the lock before mutating any folders.
        if plan_sync(args) != (directory, plan, manifest):
            raise ValueError('Folders or Zotero changed; retry.')
        with tempfile.TemporaryDirectory(prefix='.zotero-stage-', dir=directory) as tmp:
            try:
                for index, entry in enumerate(plan):
                    source, target = entry['source'], entry['name']
                    if source is not None and source != target:
                        temporary = Path(tmp) / str(index)
                        (directory / source).rename(temporary)
                        staged.append((temporary, directory / source, directory / target))
                for temporary, original, target in staged:
                    if os.path.lexists(target):
                        raise ValueError(f'Destination appeared during sync: {target}')
                    temporary.rename(target)
                    installed.append((temporary, target))
                for entry in plan:
                    if entry['source'] is None:
                        target = directory / entry['name']
                        target.mkdir()
                        created.append(target)
                if read_json(directory / MANIFEST) != manifest:
                    atomic_json(directory / MANIFEST, manifest)
            except BaseException:
                for target in reversed(created):
                    target.rmdir()
                for temporary, target in reversed(installed):
                    target.rename(temporary)
                for temporary, original, target in reversed(staged):
                    temporary.rename(original)
                raise
        print(f'Synced {len(plan)} workflow folders. Unrelated folders preserved.')
    finally:
        lock.rmdir()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--workflows', type=Path, default=DEFAULT)
    parser.add_argument('--root', default='Projects')
    parser.add_argument('--root-key')
    parser.add_argument('--api', default='http://127.0.0.1:23119')
    parser.add_argument('--library', default='users/0')
    parser.add_argument('--database', type=Path, help='Read a local Zotero SQLite database in read-only mode instead of the API')
    parser.add_argument('--adopt', action='append', default=[], metavar='PROJECT=FOLDER', help='Associate an existing differently named folder (repeatable)')
    parser.add_argument('--case-name', action='append', default=[], metavar='NAME', help='Explicitly share one exact spelling for case-equivalent project names')
    try:
        run(parser.parse_args())
    except (OSError, ValueError, RuntimeError, sqlite3.Error, URLError) as exc:
        print('Error: ' + str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
