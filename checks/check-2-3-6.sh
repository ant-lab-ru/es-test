#!/usr/bin/env bash
# Задание п2.3.6 «Библиотеки».
# Проверка статическая: общие модули — библиотеки CMake в libs/ в корне репозитория,
# каждая описывает свою сборку, SDK подключён как PRIVATE, заголовки подключаются
# с именем библиотеки, профилирование выключается при сборке.
# Использование: check-2-3-6.sh <путь к репозиторию> [папка проекта]
set -u

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
. "$LIB/report.sh"
. "$LIB/code.sh"
. "$LIB/cmake.sh"
. "$LIB/firmware.sh"

fw_start "Задание 2.3.6 — Библиотеки" 231-firmware-template "${1:-.}" "${2:-}"

LIBRARIES="stdio-text-protocol systime profiling device logging button"
SOURCES="stdio-text-protocol.c systime.c profiling.c device.c log.c button.c"

if [ ! -d "$FW_LIBS" ]; then
	fail "В корне репозитория нет папки libs"
	finish "$TITLE"
	exit 1
fi
ok "Папка libs в корне репозитория"

if [ -f "$FW_LIBS/CMakeLists.txt" ]; then
	CODE="$(normalize "$FW_LIBS/CMakeLists.txt")"
	MISSING=""
	for name in $LIBRARIES; do
		grep -Eq "add_subdirectory[[:space:]]*\([[:space:]]*$name[[:space:]]*\)" "$CODE" || MISSING="$MISSING $name"
	done
	if [ -z "$MISSING" ]; then
		ok "libs/CMakeLists.txt: к сборке добавлены все шесть библиотек"
	else
		fail "libs/CMakeLists.txt: нет add_subdirectory() для:$MISSING"
	fi
else
	fail "Нет файла libs/CMakeLists.txt"
fi

for name in $LIBRARIES; do
	DIR="$FW_LIBS/$name"
	if [ ! -f "$DIR/CMakeLists.txt" ]; then
		fail "libs/$name: нет CMakeLists.txt"
		continue
	fi
	FLAT="$(cmake_flatten "$DIR/CMakeLists.txt")"
	if ! grep -Eq 'add_library[[:space:]]*\(' "$FLAT"; then
		fail "libs/$name: в CMakeLists.txt нет add_library()"
	elif ! ls "$DIR/include/$name/"*.h > /dev/null 2>&1 || ! ls "$DIR/src/"*.c > /dev/null 2>&1; then
		fail "libs/$name: файлы не разложены по include/$name/ и src/"
	else
		ok "libs/$name: библиотека со своим CMakeLists.txt, include/$name/ и src/"
	fi
	if grep -Eq 'PUBLIC[^)]*pico_' "$FLAT"; then
		fail "libs/$name: библиотека SDK подключена как PUBLIC"
		note "Пользователь модуля не должен узнавать о SDK: подключайте его как PRIVATE."
	fi
done

for name in logging button; do
	[ -f "$FW_LIBS/$name/CMakeLists.txt" ] || continue
	if grep -Eq 'pico_|hardware_' "$(normalize "$FW_LIBS/$name/CMakeLists.txt")"; then
		fail "libs/$name: библиотека подключает SDK"
		note "Журналу и подавлению дребезга SDK не нужен. Без него сборка сама проверяет эту границу."
	else
		ok "libs/$name: SDK не подключён"
	fi
done

HEADERS="$(mktemp)"
find "$FW_LIBS" -path '*/include/*' -name '*.h' | sort | while read -r f; do cat "$(fw_code "$f")"; done > "$HEADERS"
if grep -Eq '#include[[:space:]]*[<"](pico|hardware)/' "$HEADERS"; then
	fail "Заголовок в libs подключает заголовок SDK"
	note "Заголовок — для того, кто вызывает модуль. SDK нужен только реализации, в файле .c."
else
	ok "Ни один заголовок в libs не подключает заголовков SDK"
fi

LEFT=""
for f in $SOURCES; do
	[ -n "$(find "$FW_SRC" -name "$f" -not -path '*/build/*')" ] && LEFT="$LEFT $f"
done
if [ -z "$LEFT" ]; then
	ok "В папке проекта не осталось исходников библиотек"
else
	fail "В папке проекта остались исходники библиотек:$LEFT"
fi

CMAKE="$FW_SRC/CMakeLists.txt"
if [ -f "$CMAKE" ]; then
	FLAT="$(cmake_flatten "$CMAKE")"
	match "$FLAT" 'add_subdirectory[[:space:]]*\([[:space:]]*\.\./libs[[:space:]]+[^)[:space:]]+' \
		"CMakeLists.txt: libs подключена с каталогом сборки, add_subdirectory(../libs …)" \
		"CMakeLists.txt: нет add_subdirectory(../libs \${CMAKE_BINARY_DIR}/libs)"
	if grep -Eq 'libs/[^ )]*\.c' "$FLAT"; then
		fail "CMakeLists.txt: пути к исходникам библиотек"
		note "Проект подключает библиотеки по именам в target_link_libraries()."
	else
		ok "CMakeLists.txt: библиотеки подключены по именам"
	fi
	match "$FLAT" 'target_compile_definitions[[:space:]]*\([[:space:]]*profiling[[:space:]]+PUBLIC[^)]*PROFILING_ENABLED' \
		"CMakeLists.txt: выключатель профилирования одной строкой, PROFILING_ENABLED" \
		"CMakeLists.txt: нет target_compile_definitions(profiling PUBLIC PROFILING_ENABLED=1)"
fi

fw_need SYSTIME_H systime.h
if [ -n "$SYSTIME_H" ]; then
	CODE="$(fw_code "$SYSTIME_H")"
	MISSING=""
	for fn in systime_us systime_ms systime_period_elapsed; do
		grep -Eq "$fn[[:space:]]*\(" "$CODE" || MISSING="$MISSING $fn"
	done
	if [ -z "$MISSING" ]; then
		ok "systime.h: объявлены systime_us(), systime_ms() и systime_period_elapsed()"
	else
		fail "systime.h: нет объявлений:$MISSING"
	fi
fi

fw_need PROFILING_H profiling.h
if [ -n "$PROFILING_H" ]; then
	match "$(normalize "$PROFILING_H")" '#ifndef[[:space:]]+PROFILING_ENABLED' \
		"profiling.h: значение PROFILING_ENABLED по умолчанию задано через #ifndef" \
		"profiling.h: нет #ifndef PROFILING_ENABLED"
fi

if [ -f "$FW_SRC/firmware.h" ]; then
	ok "Файл firmware.h с именем и версией прошивки в папке проекта"
else
	fail "В папке проекта нет firmware.h"
fi

CODE="$(fw_project_code)"
if grep -Eq '#include[[:space:]]*"(stdio-text-protocol|systime|profiling|device|log|button)\.h"' "$CODE"; then
	fail "Заголовок библиотеки подключён без имени библиотеки"
	note "Пишите #include \"logging/log.h\": имена заголовков разных библиотек не должны сталкиваться."
else
	ok "Заголовки библиотек подключаются с именем библиотеки"
fi
if grep -Eq 'time_us_(32|64)[[:space:]]*\(' "$CODE"; then
	fail "Проект читает часы функциями SDK"
	note "Время задачам и команде uptime даёт библиотека systime."
else
	ok "Время в проекте берётся из systime"
fi

API="$(fw_join api.c api-callbacks.c)"
match "$API" 'profiling is disabled' \
	"api: в сборке без профилирования profiling отвечает, что оно выключено" \
	"api: нет ответа profiling is disabled in this build"

finish "$TITLE"
