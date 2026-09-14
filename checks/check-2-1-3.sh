#!/usr/bin/env bash
# Задание п2.1.3 «Системная память».
# Модуль memory, символы линкера через extern и &, команда mem_info.
# Использование: check-2-1-3.sh <путь к репозиторию> [папка проекта]
set -u

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
. "$LIB/report.sh"
. "$LIB/build.sh"
. "$LIB/cmake.sh"
. "$LIB/device.sh"

TITLE="Задание 2.1.3 — Системная память"
REPO="${1:-.}"
PROJECT="${2:-211-command-usb}"
SRC="$REPO/$PROJECT"

if [ ! -d "$SRC" ]; then
	fail "В репозитории нет папки проекта $PROJECT"
	finish "$TITLE"
	exit 1
fi
ok "Папка проекта $PROJECT найдена"

for f in memory/memory.h memory/memory.c check-2-1-3.py device-2-1-3.log; do
	if [ -f "$SRC/$f" ]; then
		ok "Файл $f на месте"
	else
		fail "В проекте нет файла $f"
	fi
done

BODY="$SRC/memory/memory.c"
if [ -f "$BODY" ]; then
	BODY="$(normalize "$BODY")"

	MISSING=""
	for sym in __data_start__ __data_end__ __bss_start__ __bss_end__ __HeapLimit __StackTop; do
		grep -Eq "extern[[:space:]]+char[[:space:]]+$sym" "$BODY" || MISSING="$MISSING $sym"
	done
	if [ -z "$MISSING" ]; then
		ok "memory.c: символы линкера объявлены через extern char"
	else
		fail "memory.c: не объявлены символами линкера:$MISSING"
		note "Символ объявляют как extern char и берут у него адрес — значения у него нет."
	fi

	if grep -Eq '&__(data_start__|bss_start__|bss_end__|StackTop|StackBottom|HeapLimit|end__|flash_binary_start|flash_binary_end)' "$BODY"; then
		ok "memory.c: адрес символа берётся оператором &"
	else
		fail "memory.c: символы читаются как переменные, а не берутся через &"
		note "Без & вы прочитаете байт, лежащий ПО этому адресу, — то есть чужие данные."
	fi

	match "$BODY" 'mem_info[[:space:]]*\(' \
		"memory.c: написана функция mem_info" \
		"memory.c: нет функции mem_info"
	match "$BODY" 'XIP_BASE|0x10000000' \
		"memory.c: назван базовый адрес флеш-памяти" \
		"memory.c: не видно базового адреса флеш-памяти"
	match "$BODY" 'SRAM_BASE|0x20000000' \
		"memory.c: назван базовый адрес ОЗУ" \
		"memory.c: не видно базового адреса ОЗУ"
fi

HEADER="$SRC/memory/memory.h"
if [ -f "$HEADER" ]; then
	HEADER="$(normalize "$HEADER")"
	match "$HEADER" 'void[[:space:]]+mem_info[[:space:]]*\(' \
		"memory.h: mem_info объявлена в заголовочном файле" \
		"memory.h: нет объявления mem_info"
fi

MAIN="$SRC/main.c"
if [ -f "$MAIN" ]; then
	MAIN="$(normalize "$MAIN")"
	match "$MAIN" '#include[[:space:]]*"memory\.h"' \
		"main.c: подключён заголовочный файл модуля памяти" \
		"main.c: нет #include \"memory.h\""
	match "$MAIN" '"mem_info"' \
		"main.c: разобрана команда mem_info" \
		"main.c: нет разбора команды mem_info"
fi

CMAKE="$SRC/CMakeLists.txt"
if [ -f "$CMAKE" ]; then
	FLAT="$(cmake_flatten "$CMAKE")"
	if grep -Eo 'add_executable[[:space:]]*\([^)]*' "$FLAT" | grep -q 'memory\.c'; then
		ok "CMakeLists.txt: memory.c добавлен в список исходных файлов"
	else
		fail "CMakeLists.txt: memory.c не добавлен в add_executable"
	fi
	if grep -Eo 'target_include_directories[[:space:]]*\([^)]*' "$FLAT" | grep -q 'memory'; then
		ok "CMakeLists.txt: папка memory добавлена в пути поиска заголовочных файлов"
	else
		fail "CMakeLists.txt: папки memory нет в target_include_directories"
	fi
fi

if device_log "$SRC/device-2-1-3.log" "2.1.3"; then
	RECEIVED="$(device_received "$DEVICE_LOG")"

	if device_sent "$DEVICE_LOG" | grep -qx 'mem_info'; then
		ok "Скрипт отправил команду mem_info"
	else
		fail "В логе нет отправленной команды mem_info"
	fi

	MISSING=""
	for area in flash sram rom image '\.data' '\.bss' heap stack; do
		echo "$RECEIVED" | grep -Eq "^$area[[:space:]]+0x[0-9a-f]{8}[[:space:]]+[0-9]+" \
			|| MISSING="$MISSING $(echo "$area" | tr -d '\\')"
	done
	if [ -z "$MISSING" ]; then
		ok "Плата перечислила все восемь областей памяти с адресом и размером"
	else
		fail "В ответе платы нет строк по областям:$MISSING"
	fi

	if echo "$RECEIVED" | grep -Eq '^\.data[[:space:]]+0x2000' && echo "$RECEIVED" | grep -Eq '^\.bss[[:space:]]+0x2000'; then
		ok "Секции .data и .bss стоят по адресам ОЗУ"
	else
		fail "Адреса .data и .bss не похожи на адреса ОЗУ (0x2000…)"
	fi

	if echo "$RECEIVED" | grep -Eq '^image[[:space:]]+0x1000'; then
		ok "Образ размещён во флеш-памяти"
	else
		fail "Адрес образа не похож на адрес флеш-памяти (0x1000…)"
	fi

	STACK_SIZE="$(echo "$RECEIVED" | awk '$1 == "stack" {print $3}')"
	if [ "$STACK_SIZE" = "2048" ]; then
		ok "Под стек отведено 2048 байт — ровно банк SCRATCH"
	else
		fail "Размер стека в ответе платы — «$STACK_SIZE», а линкер-скрипт отводит 2048 байт"
	fi
fi

build_project "$SRC"

finish "$TITLE"
