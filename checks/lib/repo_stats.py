#!/usr/bin/env python3
"""Сводка по репозиторию обучающегося: сколько в нём коммитов и строк исходников.

Считает состояние всего репозитория на коммит, а не прирост. Читает то, что лежит
в git, а не рабочую папку: проверка уже собрала проект, и рядом с исходниками лежат
её промежуточные файлы.

Исходники — файлы .c и .h в папках проектов и в libs, кроме папок сборки. Папки
проектов берутся из workflow проверок, поэтому новое занятие подхватывается само.
Этим же кодом заполнена история прогонов: python3 repo_stats.py <репозиторий> <коммит>.
"""

import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE_SUFFIXES = ('.c', '.h')
BUILD_DIR = re.compile(r'^(build.*|cmake-build.*|CMakeFiles)$', re.IGNORECASE)
PROJECT = re.compile(r'^\s+project:\n(?:\s+\w+:.*\n)*?\s+default:\s*"([^"]+)"', re.MULTILINE)
SYMLINK_MODE = '120000'
GIT_TIMEOUT = 60  # секунд: сводка не должна держать проверку


def source_folders():
    """Верхние папки репозитория, в которых лежат исходники заданий."""
    folders = {'libs'}
    for workflow in (ROOT / '.github' / 'workflows').glob('check-*.yml'):
        folders.update(PROJECT.findall(workflow.read_text(encoding='utf-8')))
    return folders


def is_source(path, folders):
    parts = path.split('/')
    return (len(parts) > 1 and parts[0] in folders
            and path.endswith(SOURCE_SUFFIXES)
            and not any(BUILD_DIR.match(part) for part in parts[:-1]))


def count_lines(blob):
    """Строки файла. Windows может сохранить исходник в UTF-16: там каждый второй
    байт нулевой, поэтому его перекодируем, а нули без метки считаем двоичным файлом."""
    if blob[:2] in (b'\xff\xfe', b'\xfe\xff'):
        blob = blob.decode('utf-16', 'replace').encode()
    if b'\0' in blob[:8000]:
        return 0
    return blob.count(b'\n') + (1 if blob and not blob.endswith(b'\n') else 0)


def _git(repo, *args, stdin=None):
    return subprocess.run(['git', '-C', str(repo), *args], input=stdin, check=True,
                          capture_output=True, timeout=GIT_TIMEOUT).stdout


def _blobs(repo, shas):
    """Содержимое файлов разом: по процессу git на файл вышло бы заметно дольше."""
    out = _git(repo, 'cat-file', '--batch', stdin=''.join(f'{s}\n' for s in shas).encode())
    position = 0
    for _ in shas:
        end = out.index(b'\n', position)
        size = int(out[position:end].split()[2])
        yield out[end + 1:end + 1 + size]
        position = end + 1 + size + 1


def count_source_lines(repo, rev):
    folders = source_folders()
    shas = []
    for entry in _git(repo, 'ls-tree', '-r', '-z', rev).split(b'\0'):
        if not entry:
            continue
        meta, path = entry.decode(errors='replace').split('\t', 1)
        mode, kind, sha = meta.split()
        if kind == 'blob' and mode != SYMLINK_MODE and is_source(path, folders):
            shas.append(sha)
    return sum(count_lines(blob) for blob in _blobs(repo, shas)) if shas else 0


def unshallow(repo):
    """Проверка скачивает только последний коммит. Историю догружаем здесь, а не
    параметром fetch-depth, чтобы не править workflow каждого задания."""
    if _git(repo, 'rev-parse', '--is-shallow-repository').strip() == b'true':
        _git(repo, 'fetch', '--quiet', '--unshallow')


def repo_stats(repo, rev='HEAD'):
    return {
        'repo_commits': int(_git(repo, 'rev-list', '--count', rev)),
        'repo_lines': count_source_lines(repo, rev),
    }


if __name__ == '__main__':
    json.dump(repo_stats(sys.argv[1], sys.argv[2]), sys.stdout)
    sys.stdout.write('\n')
