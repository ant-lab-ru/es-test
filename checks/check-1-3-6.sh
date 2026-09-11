#!/usr/bin/env bash
# Задание п1.3.6 «Макросы логирования».
# Модуль logging, макросы уровней, строка версии по команде v и перевод вывода проекта на них.
# Использование: check-1-3-6.sh <путь к репозиторию> [папка проекта]
set -u

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
. "$LIB/report.sh"
. "$LIB/build.sh"
. "$LIB/cmake.sh"
. "$LIB/device.sh"

TITLE="Задание 1.3.6 — Макросы логирования"
REPO="${1:-.}"
PROJECT="${2:-134-led-module}"
SRC="$REPO/$PROJECT"

if [ ! -d "$SRC" ]; then
	fail "В репозитории нет папки проекта $PROJECT"
	finish "$TITLE"
	exit 1
fi
ok "Папка проекта $PROJECT найдена"

for f in logging/log.h logging/log.c check-1-3-6.py device-1-3-6.log; do
	if [ -f "$SRC/$f" ]; then
		ok "Файл $f на месте"
	else
		fail "В проекте нет файла $f"
	fi
done

HEADER="$SRC/logging/log.h"
if [ -f "$HEADER" ]; then
	HEADER="$(normalize "$HEADER")"
	MISSING=""
	for macro in LOG_ERR LOG_INF LOG_DBG; do
		grep -Eq "#define[[:space:]]+$macro" "$HEADER" || MISSING="$MISSING $macro"
	done
	if [ -z "$MISSING" ]; then
		ok "log.h: определены макросы LOG_ERR, LOG_INF и LOG_DBG"
	else
		fail "log.h: не определены макросы:$MISSING"
	fi

	match "$HEADER" 'LOG_LEVEL' \
		"log.h: задан порог вывода LOG_LEVEL" \
		"log.h: нет порога LOG_LEVEL — отключить отладочные сообщения будет нечем"
	match "$HEADER" '__func__' \
		"log.h: в сообщение подставляется имя функции" \
		"log.h: макросы не передают __func__"
	match "$HEADER" '__LINE__' \
		"log.h: в сообщение подставляется номер строки" \
		"log.h: макросы не передают __LINE__"
	match "$HEADER" '__VA_ARGS__' \
		"log.h: макрос принимает текст сообщения с аргументами" \
		"log.h: в макросах нет __VA_ARGS__ — печатать будет нечего"
fi

BODY="$SRC/logging/log.c"
if [ -f "$BODY" ]; then
	BODY="$(normalize "$BODY")"
	match "$BODY" '__DATE__' \
		"log.c: в строке версии печатается дата сборки" "log.c: нет __DATE__"
	match "$BODY" '__TIME__' \
		"log.c: в строке версии печатается время сборки" "log.c: нет __TIME__"
	match "$BODY" 'log_version[[:space:]]*\(' \
		"log.c: написана функция log_version" "log.c: нет функции log_version"
	match "$BODY" 'log_prefix[[:space:]]*\(' \
		"log.c: написана функция log_prefix" "log.c: нет функции log_prefix"
fi

MAIN="$SRC/main.c"
if [ -f "$MAIN" ]; then
	MAIN="$(normalize "$MAIN")"
	match "$MAIN" '#include[[:space:]]*"log\.h"' \
		"main.c: подключён заголовочный файл модуля журнала" \
		"main.c: нет #include \"log.h\""
	match "$MAIN" 'log_version[[:space:]]*\(' \
		"main.c: строка версии печатается вызовом log_version" \
		"main.c: нет вызова log_version"
	match "$MAIN" "'v'" \
		"main.c: команда v разобрана" \
		"main.c: нет разбора команды v — версию не спросить"
	match "$MAIN" 'LOG_(ERR|INF|DBG)[[:space:]]*\(' \
		"main.c: сообщения выводятся макросами журнала" \
		"main.c: нет ни одного вызова LOG_ERR, LOG_INF или LOG_DBG"

	if grep -Eq 'printf[[:space:]]*\(' "$MAIN"; then
		fail "main.c: остались прямые вызовы printf"
		note "Весь вывод проекта идёт через макросы журнала — иначе часть сообщений не отключится порогом."
	else
		ok "main.c: прямых вызовов printf не осталось"
	fi
fi

CMAKE="$SRC/CMakeLists.txt"
if [ -f "$CMAKE" ]; then
	FLAT="$(cmake_flatten "$CMAKE")"
	if grep -Eo 'add_executable[[:space:]]*\([^)]*' "$FLAT" | grep -q 'log\.c'; then
		ok "CMakeLists.txt: log.c добавлен в список исходных файлов"
	else
		fail "CMakeLists.txt: log.c не добавлен в add_executable"
	fi
	if grep -Eo 'target_include_directories[[:space:]]*\([^)]*' "$FLAT" | grep -q 'logging'; then
		ok "CMakeLists.txt: папка logging добавлена в пути поиска заголовочных файлов"
	else
		fail "CMakeLists.txt: папки logging нет в target_include_directories"
	fi
fi

if device_log "$SRC/device-1-3-6.log" "1.3.6"; then
	RECEIVED="$(device_received "$DEVICE_LOG")"

	if device_sent "$DEVICE_LOG" | grep -q '^v$'; then
		ok "Скрипт спросил у платы версию командой v"
	else
		fail "В логе нет отправленной команды v"
	fi

	if echo "$RECEIVED" | grep -Eq 'built .+log level [0-9]+'; then
		ok "Плата ответила строкой версии с датой сборки и уровнем журнала"
	else
		fail "В логе нет строки версии"
		note "По команде v прошивка печатает имя, версию, дату и время сборки и текущий уровень."
	fi

	SIGNED="$(echo "$RECEIVED" | grep -Ec '^(err|inf|dbg) [A-Za-z_][A-Za-z0-9_]*:[0-9]+ ')"
	if [ "$SIGNED" -ge 2 ]; then
		ok "Сообщения журнала подписаны уровнем, функцией и номером строки: таких строк $SIGNED"
	else
		fail "В логе нет подписанных сообщений журнала"
		note "Каждое сообщение макроса начинается с уровня, имени функции и номера строки: inf main:57 led on."
	fi

	if echo "$RECEIVED" | grep -Eq '^inf [A-Za-z_][A-Za-z0-9_]*:[0-9]+ led (on|off)$'; then
		ok "Состояние светодиода печатается уровнем inf"
	else
		fail "В логе нет сообщения о светодиоде с уровнем inf"
	fi

	if echo "$RECEIVED" | grep -Eq '^err [A-Za-z_][A-Za-z0-9_]*:[0-9]+ unknown command'; then
		ok "Неизвестная команда печатается уровнем err"
	else
		fail "В логе нет сообщения о неизвестной команде с уровнем err"
		note "Скрипт посылает символ q: прошивка должна сообщить об этом уровнем err."
	fi
fi

build_project "$SRC"

note "Разницу вывода при разных LOG_LEVEL смотрит человек на плате."
finish "$TITLE"
