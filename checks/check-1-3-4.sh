#!/usr/bin/env bash
# Задание п1.3.4 «Светодиод и USB».
# Разбор команд из порта, сохранённая кнопка, сборка и лог обмена с устройством,
# снятый скриптом задания.
# Использование: check-1-3-4.sh <путь к репозиторию> [папка проекта]
set -u

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
. "$LIB/report.sh"
. "$LIB/build.sh"
. "$LIB/cmake.sh"
. "$LIB/device.sh"

TITLE="Задание 1.3.4 — Светодиод и USB"
REPO="${1:-.}"
PROJECT="${2:-132-led-button-usb}"
SRC="$REPO/$PROJECT"

if [ ! -d "$SRC" ]; then
	fail "В репозитории нет папки проекта $PROJECT"
	finish "$TITLE"
	exit 1
fi
ok "Папка проекта $PROJECT найдена"

for f in main.c CMakeLists.txt check-1-3-4.py device-1-3-4.log; do
	if [ -f "$SRC/$f" ]; then
		ok "Файл $f на месте"
	else
		fail "В проекте нет файла $f"
	fi
done

MAIN="$SRC/main.c"
if [ -f "$MAIN" ]; then
	MAIN="$(normalize "$MAIN")"

	match "$MAIN" 'getchar_timeout_us[[:space:]]*\(' \
		"main.c: символы из порта читаются без ожидания" \
		"main.c: нет вызова getchar_timeout_us — суперцикл встанет на ожидании ввода"
	match "$MAIN" 'handle_command[[:space:]]*\(' \
		"main.c: разбор команды вынесен в отдельную функцию" \
		"main.c: нет функции handle_command — разбор остался в суперцикле"
	match "$MAIN" "'e'" \
		"main.c: команда e разобрана" "main.c: нет разбора команды e"
	match "$MAIN" "'d'" \
		"main.c: команда d разобрана" "main.c: нет разбора команды d"
	match "$MAIN" 'PICO_ERROR_TIMEOUT' \
		"main.c: пустое чтение отличается от команды" \
		"main.c: нет сравнения с PICO_ERROR_TIMEOUT — отсутствие символа примется за команду"
	match "$MAIN" 'unknown' \
		"main.c: на неизвестную команду есть ответ" \
		"main.c: нет сообщения о неизвестной команде"
	match "$MAIN" 'bool[[:space:]]+get_button_debounce[[:space:]]*\([[:space:]]*uint[[:space:]]+[A-Za-z_]' \
		"main.c: управление кнопкой сохранено" \
		"main.c: пропала функция get_button_debounce — кнопка должна работать по-прежнему"
fi

check_project_name "$SRC" "$PROJECT"

if device_log "$SRC/device-1-3-4.log" "1.3.4"; then
	PAIRS="$(awk '
		/-->/ { command = $3; next }
		/<--/ { if (command != "") { print command, substr($0, index($0, "<-- ") + 4); command = "" } }
	' "$DEVICE_LOG")"

	BAD="$(echo "$PAIRS" | awk '
		$1 == "e" && $0 !~ /led on$/ { bad++ }
		$1 == "d" && $0 !~ /led off$/ { bad++ }
		END { print bad + 0 }')"
	SENT="$(device_sent "$DEVICE_LOG" | grep -c '^[ed]$')"

	if [ "$SENT" -ge 4 ]; then
		ok "Скрипт отправил плате $SENT команд e и d"
	else
		fail "В логе только $SENT команд e и d — нужно не меньше четырёх"
	fi

	if [ "$BAD" = "0" ] && [ "$SENT" -ge 4 ]; then
		ok "На каждую команду плата ответила нужным состоянием"
	else
		fail "Ответы платы не совпадают с отправленными командами"
		note "После e плата отвечает led on, после d — led off."
	fi

	if echo "$PAIRS" | grep -q '^x .*unknown'; then
		ok "На неизвестную команду плата ответила сообщением об ошибке"
	else
		fail "В логе нет ответа на неизвестную команду"
		note "Скрипт посылает символ x: прошивка должна сообщить, что команда неизвестна."
	fi
fi

build_project "$SRC"

note "Одновременное нажатие кнопки и команду из порта проверяет человек на плате."
finish "$TITLE"
