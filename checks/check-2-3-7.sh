#!/usr/bin/env bash
# Задание п2.3.7 «Железо и логика».
# Проверка статическая: железо прибора — в модуле platform, задачи и команды — в библиотеке
# logic без SDK, api из механизма и обработчиков, main.c без SDK, правила заголовков.
# Использование: check-2-3-7.sh <путь к репозиторию> [папка проекта]
set -u

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
. "$LIB/report.sh"
. "$LIB/code.sh"
. "$LIB/cmake.sh"
. "$LIB/firmware.sh"

fw_start "Задание 2.3.7 — Железо и логика" 231-firmware-template "${1:-.}" "${2:-}"

for f in platform/platform.h platform/platform.c logic/api/api.h logic/api/api.c \
	logic/api/api-commands.h logic/api/api-callbacks.c \
	logic/led-task/led-task.h logic/led-task/led-task.c \
	logic/button-task/button-task.h logic/button-task/button-task.c \
	logic/pi-task/pi-task.h logic/pi-task/pi-task.c firmware.h main.c; do
	if [ -f "$FW_SRC/$f" ]; then
		ok "Файл $f на месте"
	else
		fail "В проекте нет файла $f"
		note "Раскладка проекта задана в разделе 1 части 2 ТЗ."
	fi
done

PLATFORM_H="$FW_SRC/platform/platform.h"
if [ -f "$PLATFORM_H" ]; then
	CODE="$(fw_code "$PLATFORM_H")"
	MISSING=""
	for fn in platform_init platform_led_set platform_button_read; do
		grep -Eq "$fn[[:space:]]*\(" "$CODE" || MISSING="$MISSING $fn"
	done
	if [ -z "$MISSING" ]; then
		ok "platform.h: объявлены platform_init(), platform_led_set() и platform_button_read()"
	else
		fail "platform.h: нет объявлений:$MISSING"
		note "Интерфейс platform дан в шаге 1 задания п2.3.7."
	fi
	if grep -Eq '#include[[:space:]]*[<"](pico|hardware)/' "$CODE"; then
		fail "platform.h: заголовок подключает SDK"
		note "SDK нужен только platform.c. Заголовок подключает лишь то, что нужно ему самому."
	else
		ok "platform.h: заголовок не подключает SDK"
	fi
fi

CMAKE="$FW_SRC/CMakeLists.txt"
if [ -f "$CMAKE" ]; then
	FLAT="$(cmake_flatten "$CMAKE")"
	match "$FLAT" 'add_library[[:space:]]*\([[:space:]]*platform[[:space:]]' \
		"CMakeLists.txt: platform собирается библиотекой" \
		"CMakeLists.txt: нет add_library(platform …)"
	match "$FLAT" 'add_library[[:space:]]*\([[:space:]]*logic[[:space:]]' \
		"CMakeLists.txt: задачи и команды собираются библиотекой logic" \
		"CMakeLists.txt: нет add_library(logic …)"
	LOGIC_LINK="$(grep -Eo 'target_link_libraries[[:space:]]*\([[:space:]]*logic[[:space:]][^)]*' "$FLAT")"
	if echo "$LOGIC_LINK" | grep -Eq 'pico_|hardware_'; then
		fail "CMakeLists.txt: библиотека logic подключает SDK"
		note "Логика работает с железом только через platform. Уберите pico_* из target_link_libraries(logic)."
	else
		ok "CMakeLists.txt: библиотека logic собирается без SDK"
	fi
	if echo "$LOGIC_LINK" | grep -Eq 'PUBLIC[[:space:]]+stdio[-_]text[-_]protocol'; then
		ok "CMakeLists.txt: logic подключает stdio_text_protocol как PUBLIC — ради command_t в api.h"
	else
		fail "CMakeLists.txt: logic не подключает stdio_text_protocol как PUBLIC"
		note "api.h подключает заголовок протокола ради command_t, поэтому пользователям logic он тоже нужен."
	fi
fi

LOGIC="$(mktemp)"
find "$FW_SRC/logic" -type f \( -name '*.c' -o -name '*.h' \) 2>/dev/null | sort | while read -r f; do cat "$(fw_code "$f")"; done > "$LOGIC"
if grep -Eq '#include[[:space:]]*[<"](pico|hardware)/|gpio_|time_us_' "$LOGIC"; then
	fail "logic: код логики обращается к SDK"
	note "Выводы и часы — в platform и systime. Логика говорит в единицах задачи."
else
	ok "logic: ни заголовков SDK, ни gpio_, ни time_us_"
fi

MAIN="$FW_SRC/main.c"
if [ -f "$MAIN" ]; then
	if grep -Eq '#include[[:space:]]*[<"](pico|hardware)/' "$(fw_code "$MAIN")"; then
		fail "main.c: подключает заголовки SDK"
		note "Всё железо запускает platform_init(), main.c SDK не нужен (правило П7)."
	else
		ok "main.c: заголовков SDK нет"
	fi
fi

API_C="$FW_SRC/logic/api/api.c"
if [ -f "$API_C" ]; then
	if grep -Eq '"(info|uptime|led_[a-z]+|button|pi|pi_start|profiling|profiling_reset)"' "$(fw_code "$API_C")"; then
		fail "api.c: в механизме есть имена команд прибора"
		note "Новая команда — правка только api-callbacks.c. В api.c из имён остаётся только help."
	else
		ok "api.c: из имён команд только help"
	fi
fi
COMMANDS_H="$FW_SRC/logic/api/api-commands.h"
if [ -f "$COMMANDS_H" ]; then
	match "$(fw_code "$COMMANDS_H")" 'extern[[:space:]]+const' \
		"api-commands.h: таблица объявлена через extern const" \
		"api-commands.h: нет объявления таблицы с extern const"
fi
CALLBACKS="$FW_SRC/logic/api/api-callbacks.c"
if [ -f "$CALLBACKS" ]; then
	OPEN="$(grep -E '^[a-z_][a-z_0-9 \*]*[[:space:]\*][a-z_0-9]+[[:space:]]*\([^;]*$' "$(fw_code "$CALLBACKS")" | grep -Ev '^static' | head -1)"
	if [ -z "$OPEN" ]; then
		ok "api-callbacks.c: обработчики определены со static"
	else
		fail "api-callbacks.c: функция без static: $OPEN"
		note "Обработчики видит только таблица в этом же файле."
	fi
fi

# свой заголовок — первым
FIRST_BAD=""
for f in $(find "$FW_SRC/logic" "$FW_SRC/platform" -name '*.c' 2>/dev/null | sort); do
	OWN="$(basename "$f" .c).h"
	# у api-callbacks.c своего заголовка нет: его интерфейс — таблица в api-commands.h
	[ -f "$(dirname "$f")/$OWN" ] || continue
	FIRST="$(grep -Em1 '^[[:space:]]*#include' "$(fw_code "$f")")"
	echo "$FIRST" | grep -q "$OWN" || FIRST_BAD="$FIRST_BAD $(basename "$f")"
done
if [ -z "$FIRST_BAD" ]; then
	ok "Каждый файл .c подключает свой заголовок первым"
else
	fail "Свой заголовок подключается не первым:$FIRST_BAD"
	note "Если заголовок первый, сборка проверяет, что он подключает всё нужное ему самому."
fi

NO_ONCE=""
for f in $(find "$FW_SRC" "$FW_LIBS" -name '*.h' -not -path '*/build/*' 2>/dev/null | sort); do
	grep -Eq '^[[:space:]]*#pragma[[:space:]]+once' "$(normalize "$f")" || NO_ONCE="$NO_ONCE $(basename "$f")"
done
if [ -z "$NO_ONCE" ]; then
	ok "Все заголовки защищены #pragma once"
else
	fail "Нет #pragma once в заголовках:$NO_ONCE"
	note "Каждый заголовок начинается с #pragma once (правило П10)."
fi

# задачи не подключают заголовки друг друга
CROSS=""
for dir in $(find "$FW_SRC/logic" -mindepth 1 -maxdepth 1 -type d -name '*-task' 2>/dev/null); do
	name="$(basename "$dir")"
	for f in "$dir"/*.c "$dir"/*.h; do
		[ -f "$f" ] || continue
		grep -Eo '#include[[:space:]]*"[a-z0-9-]+-task/' "$(fw_code "$f")" | grep -v "\"$name/" > /dev/null && CROSS="$CROSS $(basename "$f")"
	done
done
if [ -z "$CROSS" ]; then
	ok "Задачи не подключают заголовки друг друга"
else
	fail "Задача подключает заголовок другой задачи:$CROSS"
	note "О событии задача сообщает функцией, переданной ей при запуске. Связи задаёт main.c."
fi

BUTTON_DIR="$FW_SRC/logic/button-task"
if [ -f "$BUTTON_DIR/button-task.c" ]; then
	if grep -Eq '(^|[^a-z])led' "$(fw_join button-task.c button-task.h)"; then
		fail "Задача кнопки знает о светодиоде"
		note "О нажатии задача сообщает функцией, переданной при запуске. Какой, решает main.c."
	else
		ok "Задача кнопки о светодиоде не знает: о нажатии сообщает функцией"
	fi
fi
if [ -f "$MAIN" ]; then
	match "$(fw_flat "$(fw_code "$MAIN")")" 'button_task_init[[:space:]]*\([^)]*led_task_next_state' \
		"main.c: связь кнопки со светодиодом задаёт button_task_init(led_task_next_state)" \
		"main.c: нет связи кнопки со светодиодом button_task_init(led_task_next_state)"
fi

finish "$TITLE"
