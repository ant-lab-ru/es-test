#!/usr/bin/env bash
# Задание п1.3.1 «Hello World USB COM».
# Состав проекта, вывод через USB в описании сборки и в коде, имя проекта, сборка.
# Работу прошивки на плате проверяет задание 1.3.2 — по логу прогона.
# Использование: check-1-3-1.sh <путь к репозиторию> [папка проекта]
set -u

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
. "$LIB/report.sh"
. "$LIB/build.sh"
. "$LIB/cmake.sh"

TITLE="Задание 1.3.1 — Hello World USB COM"
REPO="${1:-.}"
PROJECT="${2:-131-hello-usb}"
SRC="$REPO/$PROJECT"

if [ ! -d "$SRC" ]; then
	fail "В репозитории нет папки проекта $PROJECT"
	note "Работа прошивки на плате проверяется в задании 1.3.2 — по логу прогона."
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

CMAKE="$SRC/CMakeLists.txt"
if [ -f "$CMAKE" ]; then
	CMAKE="$(normalize "$CMAKE")"
	match "$CMAKE" 'pico_enable_stdio_usb[[:space:]]*\([^)]*1[[:space:]]*\)' \
		"CMakeLists.txt: вывод через USB включён" \
		"CMakeLists.txt: нет pico_enable_stdio_usb с единицей — вывод в USB не попадёт"
	match "$CMAKE" 'pico_enable_stdio_uart[[:space:]]*\([^)]*0[[:space:]]*\)' \
		"CMakeLists.txt: вывод в UART выключен" \
		"CMakeLists.txt: вывод в UART не выключен — pico_enable_stdio_uart с нулём"
fi

MAIN="$SRC/main.c"
if [ -f "$MAIN" ]; then
	MAIN="$(normalize "$MAIN")"

	match "$MAIN" '#include[[:space:]]*<stdio\.h>' \
		"main.c: подключён заголовочный файл stdio.h" \
		"main.c: нет #include <stdio.h> — printf объявлен в нём"
	match "$MAIN" 'stdio_init_all[[:space:]]*\(' \
		"main.c: стандартный ввод-вывод инициализирован" \
		"main.c: нет вызова stdio_init_all — канал не откроется"
	match "$MAIN" 'while[[:space:]]*\([[:space:]]*(1|true)[[:space:]]*\)|for[[:space:]]*\([[:space:]]*;[[:space:]]*;[[:space:]]*\)' \
		"main.c: есть бесконечный цикл" "main.c: нет бесконечного цикла — функция main завершится"

	LOOP="$(awk '/while[ \t]*\([ \t]*(1|true)[ \t]*\)|for[ \t]*\([ \t]*;[ \t]*;[ \t]*\)/{f=1} f' "$MAIN")"

	if echo "$LOOP" | grep -Eq 'printf[[:space:]]*\([[:space:]]*"Hello, world!'; then
		ok "main.c: в бесконечном цикле печатается Hello, world!"
	else
		fail "main.c: в бесконечном цикле нет printf со строкой Hello, world!"
		note "Строка печатается ровно так, как написано в задании, вместе с переводом строки."
	fi

	if echo "$LOOP" | grep -Eq 'sleep_ms[[:space:]]*\([[:space:]]*1000[[:space:]]*\)'; then
		ok "main.c: между строками выдержка в секунду"
	else
		fail "main.c: в цикле нет sleep_ms(1000)"
		note "Без выдержки строки пойдут сплошным потоком."
	fi
fi

check_project_name "$SRC" "$PROJECT"

build_project "$SRC"

note "Работа прошивки на плате проверяется в задании 1.3.2 — по логу прогона."
finish "$TITLE"
