#!/usr/bin/env python3
"""Собирает JSON-отчёт проверки для отправки на платформу.

Вызывается из report.sh при заданной переменной CHECKS_JSON. Пункты проверки берутся
из файла с строками вида «ok<TAB>текст», остальное — из окружения GitHub Actions.
Статус пункта — «ok», «fail» или «warn»; замечания не влияют на итог задания.
"""

import argparse
import json
import os
import sys
from datetime import datetime, timezone


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--task', required=True)       # 1.1.3
    p.add_argument('--title', required=True)      # Задание 1.1.3 — Запуск прошивки
    p.add_argument('--passed', type=int, required=True)
    p.add_argument('--total', type=int, required=True)
    p.add_argument('--warned', type=int, default=0)
    p.add_argument('--items', required=True)      # файл с пунктами
    args = p.parse_args()

    items = []
    if os.path.exists(args.items):
        with open(args.items, encoding='utf-8') as f:
            for line in f:
                status, _, text = line.rstrip('\n').partition('\t')
                if text:
                    items.append({
                        'ok': status == 'ok',
                        'status': status,
                        'text': text,
                    })

    repo = os.environ.get('GITHUB_REPOSITORY', '')
    server = os.environ.get('GITHUB_SERVER_URL', 'https://github.com')
    run_id = os.environ.get('GITHUB_RUN_ID', '')

    report = {
        'student': os.environ.get('GITHUB_REPOSITORY_OWNER', ''),
        'repo': repo,
        'task': args.task,
        'title': args.title,
        'status': 'ok' if args.passed == args.total else 'failed',
        'passed': args.passed,
        'total': args.total,
        'warned': args.warned,
        'items': items,
        'commit': os.environ.get('GITHUB_SHA', ''),
        'run_url': f'{server}/{repo}/actions/runs/{run_id}' if repo and run_id else '',
        'finished_at': datetime.now(timezone.utc).isoformat(timespec='seconds'),
    }
    json.dump(report, sys.stdout, ensure_ascii=False, indent=2, sort_keys=True)
    sys.stdout.write('\n')


if __name__ == '__main__':
    main()
