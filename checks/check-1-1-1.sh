#!/usr/bin/env bash
# Задание П1.1.1 «Установка инструментов».
# Инструменты стоят на машине обучающегося, поэтому проверяется файл tools.log,
# в который записан вывод команд запроса версий.
# Использование: check-1-1-1.sh <путь к репозиторию>
set -u

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/report.sh"

TITLE="Задание 1.1.1 — Установка инструментов"
REPO="${1:-.}"
LOG="$REPO/tools.log"

# Версии Pico SDK и picotool не свободные: курс идёт на одной версии, и они обязаны
# совпадать между собой. При смене версии правится здесь, в карточках инструментов
# es-book и в .github/actions/pico-toolchain.
COURSE_VERSION="2.3.0"

# pinned <образец начала строки> <название> — версия записана и равна версии курса.
pinned() {
	if ! grep -Eq "^$1 v?[0-9]+\.[0-9]+" "$LOG"; then
		fail "$2: в tools.log нет строки с версией"
	elif grep -Eq "^$1 v?${COURSE_VERSION//./\\.}([^0-9]|\$)" "$LOG"; then
		ok "$2: версия $COURSE_VERSION"
	else
		fail "$2: нужна версия $COURSE_VERSION, в tools.log записана другая"
		note "Pico SDK и picotool закреплены версией курса и обязаны совпадать, иначе конфигурация сборки прервётся."
	fi
}

if [ ! -f "$LOG" ]; then
	fail "В корне репозитория нет файла tools.log"
	note "Файл собирается командой из задания П1.1.1 и коммитится вместе с проектом."
	finish "$TITLE"
	exit 1
fi
ok "Файл tools.log найден"

LOG="$(normalize "$LOG")"

match "$LOG" '^git version [0-9]+\.[0-9]+' \
	"git: версия записана" "git: в tools.log нет строки с версией"
match "$LOG" '^cmake version [0-9]+\.[0-9]+' \
	"CMake: версия записана" "CMake: в tools.log нет строки с версией"
match "$LOG" 'GNU Make [0-9]+\.[0-9]+' \
	"GNU Make: версия записана" "GNU Make: в tools.log нет строки с версией"
match "$LOG" 'arm-none-eabi-gcc.*\)[[:space:]]+[0-9]+\.[0-9]+' \
	"ARM GCC: версия записана" "ARM GCC: в tools.log нет строки с версией"
pinned 'picotool' "picotool"
pinned 'pico-sdk' "Pico SDK"
match "$LOG" '^code [0-9]+\.[0-9]+\.[0-9]+' \
	"Visual Studio Code: версия записана" "Visual Studio Code: в tools.log нет строки с версией"
match "$LOG" 'Python [0-9]+\.[0-9]+' \
	"Python: версия записана" "Python: в tools.log нет строки с версией"

if grep -Eq '^PICO_SDK_PATH=[[:space:]]*$|^PICO_SDK_PATH=$' "$LOG" || ! grep -q '^PICO_SDK_PATH=' "$LOG"; then
	fail "Переменная среды PICO_SDK_PATH не задана"
	note "Без неё сборка проекта не найдёт Pico SDK."
elif grep -Eq '^PICO_SDK_PATH=.*pico-sdk' "$LOG"; then
	ok "PICO_SDK_PATH указывает на директорию pico-sdk"
else
	fail "PICO_SDK_PATH задан, но не ведёт в директорию pico-sdk"
fi

finish "$TITLE"
