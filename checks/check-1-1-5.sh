#!/usr/bin/env bash
# Задание П1.1.5 «Настройка автоматической проверки».
# Проверяется, что обучающийся подключил к своему репозиторию файлы проверок курса.
# Сборку из свежей копии репозитория и мигание светодиода проверяет человек: в CI такой проверки нет.
# Использование: check-1-1-5.sh <путь к репозиторию>
set -u

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/report.sh"

TITLE="Задание 1.1.5 — Настройка автоматической проверки"
REPO="${1:-.}"

if ! git -C "$REPO" rev-parse --git-dir > /dev/null 2>&1; then
	fail "Папка не является репозиторием git"
	finish "$TITLE"
	exit 1
fi
ok "Репозиторий git найден"

TRACKED="$(git -C "$REPO" ls-files)"

WORKFLOWS="$(echo "$TRACKED" | grep -c '^\.github/workflows/.*\.ya\?ml$' || true)"
if [ "$WORKFLOWS" -gt 0 ]; then
	ok "Файлы проверок в .github/workflows выгружены ($WORKFLOWS шт.)"
else
	fail "В репозитории нет файлов проверок в .github/workflows"
	note "Файлы берутся из шаблона курса и коммитятся в репозиторий, иначе проверки не запустятся."
fi

note "Сборка из свежей копии репозитория проверяется на плате: в CI такой проверки нет."

finish "$TITLE"
