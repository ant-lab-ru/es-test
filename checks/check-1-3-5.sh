#!/usr/bin/env bash
# Задание п1.3.5 «Модуль светодиода».
# Отдельный модуль led из двух файлов, его подключение к сборке и чистый main.c.
# Использование: check-1-3-5.sh <путь к репозиторию> [папка проекта]
set -u

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
. "$LIB/report.sh"
. "$LIB/build.sh"
. "$LIB/cmake.sh"

TITLE="Задание 1.3.5 — Модуль светодиода"
REPO="${1:-.}"
PROJECT="${2:-134-led-module}"
SRC="$REPO/$PROJECT"

if [ ! -d "$SRC" ]; then
	fail "В репозитории нет папки проекта $PROJECT"
	finish "$TITLE"
	exit 1
fi
ok "Папка проекта $PROJECT найдена"

for f in main.c CMakeLists.txt memmap_rp2040.ld pico_sdk_import.cmake led/led.h led/led.c; do
	if [ -f "$SRC/$f" ]; then
		ok "Файл $f на месте"
	else
		fail "В проекте нет файла $f"
	fi
done

HEADER="$SRC/led/led.h"
if [ -f "$HEADER" ]; then
	HEADER="$(normalize "$HEADER")"
	MISSING=""
	for fn in led_init led_set led_toggle led_is_on; do
		grep -Eq "$fn[[:space:]]*\(" "$HEADER" || MISSING="$MISSING $fn"
	done
	if [ -z "$MISSING" ]; then
		ok "led.h: объявлены led_init, led_set, led_toggle и led_is_on"
	else
		fail "led.h: не объявлены функции:$MISSING"
	fi
	match "$HEADER" '#ifndef|#pragma once' \
		"led.h: есть защита от повторного включения" \
		"led.h: нет защиты от повторного включения — заголовок попадёт в сборку дважды"
fi

BODY="$SRC/led/led.c"
if [ -f "$BODY" ]; then
	BODY="$(normalize "$BODY")"
	match "$BODY" 'gpio_put[[:space:]]*\(' \
		"led.c: состоянием вывода светодиода управляет модуль" \
		"led.c: в модуле нет вызова gpio_put"
	match "$BODY" 'gpio_set_dir[[:space:]]*\(.*GPIO_OUT' \
		"led.c: настройка вывода на выход переехала в модуль" \
		"led.c: в модуле нет настройки вывода на выход"
fi

MAIN="$SRC/main.c"
if [ -f "$MAIN" ]; then
	MAIN="$(normalize "$MAIN")"
	match "$MAIN" '#include[[:space:]]*"led\.h"' \
		"main.c: подключён заголовочный файл модуля" \
		"main.c: нет #include \"led.h\""

	if grep -Eq 'gpio_put[[:space:]]*\(|gpio_set_dir[[:space:]]*\([^)]*GPIO_OUT' "$MAIN"; then
		fail "main.c: остались прямые обращения к выводу светодиода"
		note "После выноса модуля светодиодом управляют только функции led_*."
	else
		ok "main.c: прямых обращений к выводу светодиода не осталось"
	fi

	if grep -Eq 'LED_PIN' "$MAIN"; then
		fail "main.c: номер вывода светодиода упоминается вне модуля"
		note "Номер вывода знает только led.c — в этом смысл модуля."
	else
		ok "main.c: номер вывода светодиода знает только модуль"
	fi

	match "$MAIN" 'handle_command[[:space:]]*\(' \
		"main.c: разбор команд по-прежнему живёт в отдельной функции" \
		"main.c: пропала функция handle_command из прошлого задания"
	match "$MAIN" 'led_toggle[[:space:]]*\(|led_set[[:space:]]*\(' \
		"main.c: светодиодом управляют функции модуля" \
		"main.c: нет вызовов led_set или led_toggle"
fi

CMAKE="$SRC/CMakeLists.txt"
if [ -f "$CMAKE" ]; then
	FLAT="$(cmake_flatten "$CMAKE")"
	if grep -Eo 'add_executable[[:space:]]*\([^)]*' "$FLAT" | grep -q 'led/led\.c'; then
		ok "CMakeLists.txt: led.c добавлен в список исходных файлов"
	else
		fail "CMakeLists.txt: led.c не добавлен в add_executable"
		note "Файл, которого нет в сборке, просто не компилируется."
	fi
	if grep -Eo 'target_include_directories[[:space:]]*\([^)]*' "$FLAT" | grep -q 'led'; then
		ok "CMakeLists.txt: папка led добавлена в пути поиска заголовочных файлов"
	else
		fail "CMakeLists.txt: папки led нет в target_include_directories"
		note "Без неё компилятор не найдёт led.h по короткому имени."
	fi
fi

check_project_name "$SRC" "$PROJECT"

build_project "$SRC"

note "Поведение прибора после выноса модуля не меняется — это проверяется на плате."
finish "$TITLE"
