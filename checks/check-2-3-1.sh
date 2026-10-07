#!/usr/bin/env bash
# Задание п2.3.1 «Протокол и API».
# Проверка статическая: модуль протокола делит строку на имя и аргументы и не знает
# ни одной команды, модуль api находит команду в таблице. Модули ищутся по имени файла:
# в 2.3.6 протокол переезжает в libs/, в 2.3.7 api — в logic/.
# Использование: check-2-3-1.sh <путь к репозиторию> [папка проекта]
set -u

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
. "$LIB/report.sh"
. "$LIB/code.sh"
. "$LIB/cmake.sh"
. "$LIB/firmware.sh"

fw_start "Задание 2.3.1 — Протокол и API" 231-firmware-template "${1:-.}" "${2:-}"

CMAKE="$FW_SRC/CMakeLists.txt"
if [ -f "$CMAKE" ]; then
	match "$(cmake_flatten "$CMAKE")" 'project[[:space:]]*\([[:space:]]*231_firmware_template[[:space:]]*\)' \
		"CMakeLists.txt: проект назван 231_firmware_template" \
		"CMakeLists.txt: в project() не 231_firmware_template"
else
	fail "В проекте нет CMakeLists.txt"
	note "Проект создаётся копией 221-command-time, CMakeLists.txt копируется вместе с ним."
fi

fw_need PROTOCOL_H stdio-text-protocol.h
fw_need PROTOCOL_C stdio-text-protocol.c
fw_need API_H api.h

if [ -n "$PROTOCOL_H" ]; then
	FLAT="$(fw_flat "$(fw_code "$PROTOCOL_H")")"
	if grep -Eq 'typedef[[:space:]]+struct[^}]*\bname\b[^}]*\bargc\b[^}]*\bargv\b[^}]*\btruncated\b[^}]*\}[[:space:]]*command_t' "$FLAT"; then
		ok "stdio-text-protocol.h: тип command_t с полями name, argc, argv и truncated"
	else
		fail "stdio-text-protocol.h: нет типа command_t с полями name, argc, argv и truncated"
		note "Команда — имя, число аргументов, массив аргументов и пометка, что строка принята не целиком."
	fi
	match "$FLAT" 'stdio_text_protocol_handle[[:space:]]*\([[:space:]]*void[[:space:]]*\)' \
		"stdio-text-protocol.h: объявлен обработчик stdio_text_protocol_handle()" \
		"stdio-text-protocol.h: нет объявления stdio_text_protocol_handle(void)"
fi

if [ -n "$PROTOCOL_C" ]; then
	CODE="$(fw_code "$PROTOCOL_C")"
	match "$CODE" 'getchar_timeout_us[[:space:]]*\([[:space:]]*0[[:space:]]*\)' \
		"stdio-text-protocol.c: символ читается без ожидания, getchar_timeout_us(0)" \
		"stdio-text-protocol.c: нет вызова getchar_timeout_us(0)"
	match "$CODE" "0x7[fF]|127|'\\\\b'|0x08|\\b8\\b" \
		"stdio-text-protocol.c: обрабатывается Backspace" \
		"stdio-text-protocol.c: не видно обработки Backspace (коды 0x08 и 0x7f)"
	if grep -Eq '"(help|info|uptime|led_[a-z]+|button|pi|pi_start|profiling)"' "$CODE"; then
		fail "stdio-text-protocol.c: в протоколе есть имя команды прибора"
		note "Протокол знает только формат строки. Какие команды есть у прибора, знает api."
	else
		ok "stdio-text-protocol.c: ни одного имени команды прибора"
	fi
fi

API="$(fw_join api.c api-callbacks.c api-commands.h api.h)"
if [ -s "$API" ]; then
	FLAT="$(fw_flat "$API")"
	match "$API" 'api_handle[[:space:]]*\([[:space:]]*const[[:space:]]+command_t[[:space:]]*\*' \
		"api: функция api_handle(const command_t *) принимает команду" \
		"api: нет функции api_handle(const command_t *command)"
	if grep -Eq 'struct[^}]*\bname\b[^}]*\bhelp\b[^}]*\bcallback\b[^}]*\}[[:space:]]*api_command_t' "$FLAT"; then
		ok "api: запись таблицы api_command_t с полями name, help и callback"
	else
		fail "api: нет типа api_command_t с полями name, help и callback"
		note "Тип записи таблицы приведён в т2.3.8, раздел «Выполнение команды в API»."
	fi
	match "$API" '"help"' \
		"api: есть команда help" \
		"api: нет команды help"
	match "$API" 'error: unknown command' \
		"api: на неизвестную команду ответ error: unknown command" \
		"api: нет ответа error: unknown command '<имя>', try help"
	match "$API" 'truncated' \
		"api: команда с пометкой truncated не выполняется" \
		"api: не видно проверки truncated"
	match "$API" 'strtoul[[:space:]]*\(' \
		"api: числовой аргумент разбирается функцией strtoul()" \
		"api: нет разбора числа через strtoul()"
	if grep -Eq 'sscanf[[:space:]]*\(' "$API"; then
		fail "api: аргумент разбирается через sscanf()"
		note "sscanf() добавляет к образу около 55 КБ. Вернитесь к parse_u32() на strtoul()."
	else
		ok "api: sscanf() не используется"
	fi
fi

MAIN="$FW_SRC/main.c"
if [ -f "$MAIN" ]; then
	CODE="$(fw_code "$MAIN")"
	match "$CODE" 'stdio_text_protocol_handle[[:space:]]*\(' \
		"main.c: суперцикл забирает команду у протокола" \
		"main.c: нет вызова stdio_text_protocol_handle()"
	match "$CODE" 'api_handle[[:space:]]*\(' \
		"main.c: команда передаётся в api_handle()" \
		"main.c: нет вызова api_handle()"
	if grep -Eq 'getchar|strcmp|\[[[:space:]]*[0-9A-Z_]+[[:space:]]*\][[:space:]]*;' "$CODE"; then
		fail "main.c: в main.c остались чтение символов, буфер строки или поиск команды"
		note "Строку собирает протокол, команду ищет api. В main.c — только передача команды из одного в другой."
	else
		ok "main.c: ни чтения символов, ни буфера строки, ни поиска команды"
	fi
else
	fail "В проекте нет main.c"
	note "main.c лежит в корне папки проекта."
fi

if grep -Eq '"(mem_info|fw_info|boot_info|dev_info|clk_info|clk_sys_low|clk_sys_default)"' "$(fw_project_code)"; then
	fail "В проекте остались опыты занятий 2.1 и 2.2"
	note "Команды mem_info, fw_info, boot_info, dev_info и clk_* в прибор не входят."
else
	ok "Опыты занятий 2.1 и 2.2 убраны"
fi

finish "$TITLE"
