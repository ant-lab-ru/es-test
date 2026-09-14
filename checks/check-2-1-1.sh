#!/usr/bin/env bash
# Задание п2.1.1 «Многосимвольные команды».
# Проект 211-command-usb, приём строки из порта, разбор команд словами, версия SDK в паспорте.
# Использование: check-2-1-1.sh <путь к репозиторию> [папка проекта]
set -u

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
. "$LIB/report.sh"
. "$LIB/build.sh"
. "$LIB/cmake.sh"
. "$LIB/device.sh"

TITLE="Задание 2.1.1 — Многосимвольные команды"
REPO="${1:-.}"
PROJECT="${2:-211-command-usb}"
SRC="$REPO/$PROJECT"

if [ ! -d "$SRC" ]; then
	fail "В репозитории нет папки проекта $PROJECT"
	finish "$TITLE"
	exit 1
fi
ok "Папка проекта $PROJECT найдена"

for f in main.c device/device.c device/device.h led/led.c logging/log.c check-2-1-1.py device-2-1-1.log; do
	if [ -f "$SRC/$f" ]; then
		ok "Файл $f на месте"
	else
		fail "В проекте нет файла $f"
	fi
done

MAIN="$SRC/main.c"
if [ -f "$MAIN" ]; then
	MAIN="$(normalize "$MAIN")"

	match "$MAIN" '#include[[:space:]]*<string\.h>' \
		"main.c: подключён <string.h> — строки сравнивают его функцией" \
		"main.c: нет #include <string.h>"
	match "$MAIN" 'char[[:space:]]+line[[:space:]]*\[' \
		"main.c: заведён буфер строки" \
		"main.c: нет буфера, в котором копятся символы команды"
	match "$MAIN" 'line_length' \
		"main.c: длина набранного хранится отдельно" \
		"main.c: нет переменной с длиной набранной строки"
	match "$MAIN" 'getchar_timeout_us[[:space:]]*\(' \
		"main.c: символы принимаются без ожидания" \
		"main.c: нет вызова getchar_timeout_us"
	match "$MAIN" "'\\\\r'|'\\\\n'" \
		"main.c: конец команды определяется по переводу строки" \
		"main.c: не видно проверки на '\\r' или '\\n' — команда никогда не закончится"
	match "$MAIN" "line\[line_length\][[:space:]]*=[[:space:]]*'\\\\0'|\\\\0" \
		"main.c: строка завершается нулевым байтом" \
		"main.c: буфер не завершается '\\0' — strcmp прочитает лишнее"
	match "$MAIN" 'putchar[[:space:]]*\(' \
		"main.c: набранные символы возвращаются в терминал" \
		"main.c: нет putchar — набирать команду придётся вслепую"

	if grep -Eq 'strcmp[[:space:]]*\(' "$MAIN"; then
		ok "main.c: команды сравниваются функцией strcmp"
	else
		fail "main.c: нет strcmp — строки нельзя сравнивать оператором =="
		note "Имя массива — это адрес; line == \"on\" сравнит два адреса, а не текст."
	fi

	MISSING=""
	for cmd in on off info help; do
		grep -Eq "\"$cmd\"" "$MAIN" || MISSING="$MISSING $cmd"
	done
	if [ -z "$MISSING" ]; then
		ok "main.c: разобраны команды on, off, info и help"
	else
		fail "main.c: не разобраны команды:$MISSING"
	fi

	match "$MAIN" 'unknown command' \
		"main.c: на незнакомую команду прибор отвечает ошибкой" \
		"main.c: нет сообщения о незнакомой команде"
fi

DEVICE="$SRC/device/device.c"
if [ -f "$DEVICE" ]; then
	DEVICE="$(normalize "$DEVICE")"
	match "$DEVICE" 'PICO_SDK_VERSION_STRING' \
		"device.c: в паспорт добавлена версия Pico SDK" \
		"device.c: нет PICO_SDK_VERSION_STRING — от версии SDK зависят все адреса занятия"
fi

HEADER="$SRC/device/device.h"
if [ -f "$HEADER" ]; then
	HEADER="$(normalize "$HEADER")"
	match "$HEADER" 'DEVICE_PROJECT[[:space:]]+"211-command-usb"' \
		"device.h: имя проекта в паспорте — 211-command-usb" \
		"device.h: в DEVICE_PROJECT осталось имя проекта прошлого занятия"
fi

CMAKE="$SRC/CMakeLists.txt"
if [ -f "$CMAKE" ]; then
	FLAT="$(cmake_flatten "$CMAKE")"
	match "$FLAT" 'project[[:space:]]*\([[:space:]]*211_command_usb' \
		"CMakeLists.txt: имя проекта 211_command_usb" \
		"CMakeLists.txt: имя проекта не переименовано под это занятие"
fi

if device_log "$SRC/device-2-1-1.log" "2.1.1"; then
	RECEIVED="$(device_received "$DEVICE_LOG")"
	SENT="$(device_sent "$DEVICE_LOG")"

	for cmd in on off info; do
		if echo "$SENT" | grep -qx "$cmd"; then
			ok "Скрипт отправил команду $cmd"
		else
			fail "В логе нет отправленной команды $cmd"
		fi
	done

	if echo "$RECEIVED" | grep -Eq '^sdk: [0-9]+\.[0-9]+\.[0-9]+'; then
		ok "Плата ответила на info строкой с версией Pico SDK"
	else
		fail "В логе нет строки sdk: с версией Pico SDK"
	fi

	if echo "$RECEIVED" | grep -Eq '^project: 211-command-usb'; then
		ok "Паспорт называет проект 211-command-usb"
	else
		fail "В логе нет строки project: 211-command-usb"
	fi

	if echo "$RECEIVED" | grep -Eq 'led (on|off)'; then
		ok "Плата сообщила о новом состоянии светодиода"
	else
		fail "В логе нет сообщения о состоянии светодиода"
	fi

	if echo "$RECEIVED" | grep -Eq 'unknown command: [a-z]{2,}'; then
		ok "На незнакомое слово плата ответила ошибкой и назвала это слово"
	else
		fail "В логе нет ответа на незнакомую команду"
		note "Скрипт посылает выдуманное слово: прошивка должна вернуть unknown command и само слово."
	fi
fi

build_project "$SRC"

finish "$TITLE"
