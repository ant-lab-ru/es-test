#!/usr/bin/env bash
# Задание П1.1.4 «Создание репозитория курса».
# Состояние репозитория: .gitignore, отсутствие результатов сборки в истории, состав коммита.
# Использование: check-1-1-4.sh <путь к репозиторию> [папка проекта]
set -u

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/report.sh"

TITLE="Задание 1.1.4 — Создание репозитория курса"
REPO="${1:-.}"
PROJECT="${2:-112-blink}"

if ! git -C "$REPO" rev-parse --git-dir > /dev/null 2>&1; then
	fail "Папка не является репозиторием git"
	finish "$TITLE"
	exit 1
fi
ok "Репозиторий git найден"

TRACKED="$(git -C "$REPO" ls-files)"

IGNORE="$REPO/.gitignore"
if [ -f "$IGNORE" ]; then
	ok "Файл .gitignore на месте"
	IGNORE="$(normalize "$IGNORE")"
	match "$IGNORE" '(^|/)build/?[[:space:]]*$' \
		".gitignore: директория build исключена" ".gitignore: не исключена директория build"
	match "$IGNORE" '(^|/)\.vscode/?[[:space:]]*$' \
		".gitignore: директория .vscode исключена" ".gitignore: не исключена директория .vscode"
	# .DS_Store заводит только macOS, поэтому его отсутствие в .gitignore — не ошибка.
	if grep -Eq '(^|/)\.DS_Store[[:space:]]*$' "$IGNORE"; then
		ok ".gitignore: служебный файл .DS_Store исключён"
	else
		warn ".gitignore: не исключён служебный файл .DS_Store"
		note "Нужно тем, кто работает в macOS: Finder заводит этот файл в каждой открытой папке."
	fi
else
	fail "В корне репозитория нет файла .gitignore"
fi

if echo "$TRACKED" | grep -Eq '(^|/)build/'; then
	fail "В репозиторий попала директория build"
else
	ok "Директории build в репозитории нет"
fi

if echo "$TRACKED" | grep -Eq '\.(uf2|elf|bin|o|a)$'; then
	fail "В репозиторий попали результаты сборки"
	note "Версионируются только исходные файлы проекта."
else
	ok "Результатов сборки в репозитории нет"
fi

if echo "$TRACKED" | grep -q '^tools\.log$'; then
	ok "Файл tools.log выгружен в репозиторий"
else
	fail "В репозитории нет файла tools.log из задания П1.1.1"
fi

if echo "$TRACKED" | grep -q '^git\.log$'; then
	warn "В репозиторий выгружен файл git.log"
	note "Он нужен только для самопроверки на машине обучающегося и остаётся в папке pico."
else
	ok "Файла git.log в репозитории нет"
fi

COUNT="$(echo "$TRACKED" | grep -c "^$PROJECT/" || true)"
if [ "$COUNT" -eq 4 ]; then
	ok "Проект $PROJECT выгружен четырьмя файлами"
elif [ "$COUNT" -eq 0 ]; then
	fail "Проект $PROJECT в репозиторий не выгружен"
else
	fail "В проекте $PROJECT выгружено файлов: $COUNT, ожидается 4"
fi

finish "$TITLE"
