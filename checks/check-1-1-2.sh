#!/usr/bin/env bash
# Задание П1.1.2 «Первый проект».
# Состав проекта, содержание main.c и CMakeLists.txt, конфигурация сборки.
# Использование: check-1-1-2.sh <путь к репозиторию> [папка проекта]
set -u

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/report.sh"

TITLE="Задание 1.1.2 — Первый проект"
REPO="${1:-.}"
PROJECT="${2:-112-blink}"
SRC="$REPO/$PROJECT"

if [ ! -d "$SRC" ]; then
	fail "В репозитории нет папки проекта $PROJECT"
	finish "$TITLE"
	exit 1
fi
ok "Папка проекта $PROJECT найдена"

EXPECTED="main.c CMakeLists.txt memmap_rp2040.ld pico_sdk_import.cmake"
for f in $EXPECTED; do
	if [ -f "$SRC/$f" ]; then
		ok "Файл $f на месте"
	else
		fail "В проекте нет файла $f"
	fi
done

EXTRA=""
for f in "$SRC"/*; do
	[ -f "$f" ] || continue
	name="$(basename "$f")"
	case " $EXPECTED " in
		*" $name "*) ;;
		*) EXTRA="$EXTRA $name" ;;
	esac
done
if [ -z "$EXTRA" ]; then
	ok "В проекте ровно четыре файла"
else
	fail "В проекте есть лишние файлы:$EXTRA"
	note "Для сборки прошивки достаточно четырёх файлов, только они и коммитятся."
fi

# Вызовы в C и CMake переносятся на несколько строк, поэтому ищем по тексту
# со схлопнутыми переводами строк.
flatten() {
	local out
	out="$(mktemp)"
	tr '\n' ' ' < "$1" > "$out"
	echo "$out"
}

MAIN="$SRC/main.c"
if [ -f "$MAIN" ]; then
	MAIN="$(flatten "$MAIN")"
	match "$MAIN" '#include[[:space:]]*"pico/stdlib\.h"' \
		"main.c: подключена pico/stdlib.h" "main.c: не подключён заголовок pico/stdlib.h"
	match "$MAIN" '#include[[:space:]]*"hardware/gpio\.h"' \
		"main.c: подключена hardware/gpio.h" "main.c: не подключён заголовок hardware/gpio.h"
	match "$MAIN" 'gpio_init[[:space:]]*\(' \
		"main.c: вывод инициализируется" "main.c: нет вызова gpio_init"
	match "$MAIN" 'gpio_set_dir[[:space:]]*\(.*GPIO_OUT' \
		"main.c: вывод настроен на выход" "main.c: нет настройки вывода через gpio_set_dir с GPIO_OUT"
	match "$MAIN" 'gpio_put[[:space:]]*\(' \
		"main.c: состояние вывода переключается" "main.c: нет вызова gpio_put"
	match "$MAIN" 'sleep_ms[[:space:]]*\(' \
		"main.c: есть задержка между переключениями" "main.c: нет вызова sleep_ms"
	match "$MAIN" 'while[[:space:]]*\([[:space:]]*(1|true)[[:space:]]*\)|for[[:space:]]*\([[:space:]]*;[[:space:]]*;[[:space:]]*\)' \
		"main.c: есть бесконечный цикл" "main.c: нет бесконечного цикла — функция main завершится"
fi

CMAKE="$SRC/CMakeLists.txt"
if [ -f "$CMAKE" ]; then
	CMAKE="$(flatten "$CMAKE")"
	match "$CMAKE" 'include[[:space:]]*\([[:space:]]*pico_sdk_import\.cmake' \
		"CMakeLists.txt: подключён pico_sdk_import.cmake" "CMakeLists.txt: не подключён pico_sdk_import.cmake"
	match "$CMAKE" 'pico_sdk_init[[:space:]]*\(' \
		"CMakeLists.txt: SDK инициализируется" "CMakeLists.txt: нет вызова pico_sdk_init"
	match "$CMAKE" 'add_executable[[:space:]]*\(' \
		"CMakeLists.txt: цель сборки описана" "CMakeLists.txt: нет вызова add_executable"
	match "$CMAKE" 'target_link_libraries[[:space:]]*\([^)]*pico_stdlib' \
		"CMakeLists.txt: подключена библиотека pico_stdlib" "CMakeLists.txt: цель не связана с pico_stdlib"
	match "$CMAKE" 'pico_set_linker_script[[:space:]]*\([^)]*memmap_rp2040\.ld' \
		"CMakeLists.txt: указан линкер-скрипт memmap_rp2040.ld" "CMakeLists.txt: не указан линкер-скрипт memmap_rp2040.ld"
	match "$CMAKE" 'pico_add_extra_outputs[[:space:]]*\(' \
		"CMakeLists.txt: добавлена генерация форматов прошивки" "CMakeLists.txt: нет вызова pico_add_extra_outputs"
fi

if [ -n "${PICO_SDK_PATH:-}" ]; then
	BUILD="$(mktemp -d)"
	if cmake -S "$SRC" -B "$BUILD" -G "Unix Makefiles" > "$BUILD/cmake.log" 2>&1; then
		ok "Конфигурация сборки завершается без ошибок"
	else
		fail "Конфигурация сборки завершается с ошибкой"
		note "Последние строки вывода cmake:"
		tail -20 "$BUILD/cmake.log"
	fi
	rm -rf "$BUILD"
else
	note "Конфигурация сборки не проверялась: не задан PICO_SDK_PATH."
fi

finish "$TITLE"
