#!/usr/bin/env bash
# Задание п1.3.7 «Паспорт устройства».
# Модуль device, сведения из настроек сборки и из чипа, команда i, сборка,
# а также лог с паспортом, снятый скриптом задания.
# Использование: check-1-3-7.sh <путь к репозиторию> [папка проекта]
set -u

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
. "$LIB/report.sh"
. "$LIB/build.sh"
. "$LIB/cmake.sh"
. "$LIB/device.sh"

TITLE="Задание 1.3.7 — Паспорт устройства"
REPO="${1:-.}"
PROJECT="${2:-134-led-module}"
SRC="$REPO/$PROJECT"

if [ ! -d "$SRC" ]; then
	fail "В репозитории нет папки проекта $PROJECT"
	finish "$TITLE"
	exit 1
fi
ok "Папка проекта $PROJECT найдена"

for f in device/device.h device/device.c check-1-3-7.py device-1-3-7.log; do
	if [ -f "$SRC/$f" ]; then
		ok "Файл $f на месте"
	else
		fail "В проекте нет файла $f"
	fi
done

HEADER="$SRC/device/device.h"
if [ -f "$HEADER" ]; then
	HEADER="$(normalize "$HEADER")"
	match "$HEADER" 'DEVICE_PROJECT|PROJECT_NAME' \
		"device.h: задано название проекта" "device.h: нет константы с названием проекта"
	match "$HEADER" 'https?://' \
		"device.h: задана ссылка на репозиторий курса" "device.h: нет ссылки на репозиторий курса"
	match "$HEADER" 'DEVICE_NAME' \
		"device.h: название устройства переехало из log.h" \
		"device.h: нет константы с названием устройства"
	match "$HEADER" 'FIRMWARE_VERSION' \
		"device.h: версия прошивки переехала из log.h" \
		"device.h: нет константы с версией прошивки"
	match "$HEADER" 'device_info[[:space:]]*\(' \
		"device.h: объявлена функция device_info()" "device.h: нет объявления device_info()"
	match "$HEADER" '#ifndef[[:space:]]+DEVICE_BOARD' \
		"device.h: у типа платы есть значение на случай сборки без него" \
		"device.h: тип платы не защищён значением по умолчанию"
fi

BODY="$SRC/device/device.c"
if [ -f "$BODY" ]; then
	BODY="$(normalize "$BODY")"
	match "$BODY" 'pico_get_unique_board_id_string[[:space:]]*\(' \
		"device.c: серийный номер платы читается из чипа" \
		"device.c: нет вызова pico_get_unique_board_id_string()"
	match "$BODY" 'SYSINFO_BASE|0x40000000' \
		"device.c: есть обращение к блоку SYSINFO по адресу" \
		"device.c: нет обращения к базовому адресу блока SYSINFO"
	match "$BODY" 'CHIP_ID' \
		"device.c: читается регистр CHIP_ID" "device.c: регистр CHIP_ID не читается"
	match "$BODY" 'volatile' \
		"device.c: регистр читается через volatile" \
		"device.c: у указателя на регистр нет volatile — компилятор вправе выбросить чтение"
	for field in manufacturer part revision; do
		if grep -q "$field" "$BODY"; then
			ok "device.c: в паспорте разобрано поле $field"
		else
			fail "device.c: поле $field регистра CHIP_ID не разобрано"
		fi
	done
fi

LOGC="$SRC/logging/log.c"
if [ -f "$LOGC" ]; then
	LOGC="$(normalize "$LOGC")"
	match "$LOGC" '#include[[:space:]]*"device\.h"' \
		"log.c: имя и версия берутся из device.h" \
		"log.c: нет #include \"device.h\" — имя и версия должны переехать в паспорт"
fi

MAIN="$SRC/main.c"
if [ -f "$MAIN" ]; then
	MAIN="$(normalize "$MAIN")"
	match "$MAIN" "'i'" \
		"main.c: команда i разобрана" "main.c: нет разбора команды i"
	match "$MAIN" '#include[[:space:]]*"device\.h"' \
		"main.c: подключён заголовочный файл модуля device" "main.c: нет #include \"device.h\""
fi

CMAKE="$SRC/CMakeLists.txt"
if [ -f "$CMAKE" ]; then
	FLAT="$(cmake_flatten "$CMAKE")"
	if grep -Eo 'add_executable[[:space:]]*\([^)]*' "$FLAT" | grep -q 'device/device\.c'; then
		ok "CMakeLists.txt: device.c добавлен в список исходных файлов"
	else
		fail "CMakeLists.txt: device.c не добавлен в add_executable"
	fi
	if grep -Eo 'target_include_directories[[:space:]]*\([^)]*' "$FLAT" | grep -q 'device'; then
		ok "CMakeLists.txt: папка device добавлена в пути поиска заголовочных файлов"
	else
		fail "CMakeLists.txt: папки device нет в target_include_directories"
	fi
	if grep -Eo 'target_link_libraries[[:space:]]*\([^)]*' "$FLAT" | grep -q 'pico_unique_id'; then
		ok "CMakeLists.txt: подключена библиотека pico_unique_id"
	else
		fail "CMakeLists.txt: нет библиотеки pico_unique_id — серийный номер прочитать нечем"
	fi
	if grep -Eo 'target_compile_definitions[[:space:]]*\([^)]*' "$FLAT" | grep -q 'PICO_BOARD'; then
		ok "CMakeLists.txt: тип платы передан в код из настроек сборки"
	else
		fail "CMakeLists.txt: значение PICO_BOARD не передано в код определением компилятора"
	fi
fi

if device_log "$SRC/device-1-3-7.log" "1.3.7"; then
	PASSPORT="$(device_received "$DEVICE_LOG")"

	MISSING=""
	for field in project repo board serial chip; do
		echo "$PASSPORT" | grep -Eq "^$field:" || MISSING="$MISSING $field"
	done
	if [ -z "$MISSING" ]; then
		ok "Плата прислала паспорт из пяти строк"
	else
		fail "В паспорте нет строк:$MISSING"
		note "Каждая строка паспорта — пара «ключ — значение», ключ и двоеточие в начале строки."
	fi

	if device_sent "$DEVICE_LOG" | grep -q '^i$'; then
		ok "Паспорт получен по команде i"
	else
		fail "В логе нет отправленной команды i"
	fi

	REPORTED="$(echo "$PASSPORT" | sed -n 's/^serial:[[:space:]]*//p' | head -1)"
	if [ -n "$REPORTED" ] && [ -n "$DEVICE_SERIAL" ]; then
		if [ "$(echo "$REPORTED" | tr 'A-Z' 'a-z')" = "$(echo "$DEVICE_SERIAL" | tr 'A-Z' 'a-z')" ]; then
			ok "Серийный номер в паспорте совпал с номером, который плата сообщила по USB"
		else
			fail "Серийный номер в паспорте ($REPORTED) не совпал с номером платы по USB ($DEVICE_SERIAL)"
			note "Оба числа — один и тот же уникальный идентификатор платы, прочитанный с двух сторон."
		fi
	fi

	if echo "$PASSPORT" | grep -Eq '^chip:.*0x[0-9a-fA-F]+'; then
		ok "В строке chip разобраны поля регистра"
	else
		fail "В строке chip нет разобранных полей регистра CHIP_ID"
	fi
fi

check_project_name "$SRC" "$PROJECT"

build_project "$SRC"

note "Ответы на команды v и i человек смотрит на плате."
finish "$TITLE"
