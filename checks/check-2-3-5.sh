#!/usr/bin/env bash
# Задание п2.3.5 «Данные вместо печати».
# Проверка статическая: device возвращает сведения структурой, журнал не зависит от device,
# profiling — набор секундомеров по номерам, печатает только api.
# Использование: check-2-3-5.sh <путь к репозиторию> [папка проекта]
set -u

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
. "$LIB/report.sh"
. "$LIB/code.sh"
. "$LIB/firmware.sh"

fw_start "Задание 2.3.5 — Данные вместо печати" 231-firmware-template "${1:-.}" "${2:-}"

fw_need DEVICE_H device.h
fw_need DEVICE_C device.c
fw_need PROFILING_H profiling.h
fw_need PROFILING_C profiling.c
fw_need LOG_C log.c

if [ -n "$DEVICE_H" ]; then
	CODE="$(fw_code "$DEVICE_H")"
	match "$CODE" 'device_get_info[[:space:]]*\([^)]*\*' \
		"device.h: device_get_info() заполняет сведения по указателю" \
		"device.h: нет функции device_get_info(), которая получает указатель на структуру"
	match "$CODE" 'struct' \
		"device.h: сведения о плате — структура" \
		"device.h: нет структуры со сведениями о плате"
fi

for f in "$DEVICE_C" "$PROFILING_C"; do
	[ -n "$f" ] || continue
	if grep -Eq 'printf|puts[[:space:]]*\(' "$(fw_code "$f")"; then
		fail "$(basename "$f"): модуль печатает сам"
		note "Модуль возвращает данные. Ответ на команду печатает api."
	else
		ok "$(basename "$f"): модуль не печатает, только возвращает данные"
	fi
done

LOGGING="$(fw_join log.c log.h)"
if grep -Eq 'device|DEVICE_' "$LOGGING"; then
	fail "logging: журнал зависит от device"
	note "Имя и версию прошивки при запуске выводит main.c макросом LOG_INF."
else
	ok "logging: журнал не зависит от device"
fi

if [ -n "$PROFILING_H" ]; then
	CODE="$(fw_code "$PROFILING_H")"
	MISSING=""
	for fn in profiling_stopwatch_init profiling_start profiling_stop profiling_get profiling_reset; do
		grep -Eq "$fn[[:space:]]*\(" "$CODE" || MISSING="$MISSING $fn"
	done
	if [ -z "$MISSING" ]; then
		ok "profiling.h: объявлены функции секундомеров"
	else
		fail "profiling.h: нет объявлений:$MISSING"
	fi
fi

MAIN="$FW_SRC/main.c"
if [ -f "$MAIN" ]; then
	CODE="$(fw_code "$MAIN")"
	match "$CODE" 'enum' \
		"main.c: номера секундомеров — перечисляемый тип" \
		"main.c: нет перечисляемого типа с номерами секундомеров"
	STARTS="$(grep -Eo 'profiling_start[[:space:]]*\(' "$CODE" | wc -l | tr -d ' ')"
	if [ "$STARTS" -ge 4 ]; then
		ok "main.c: секундомеры обрамляют итерацию и обработчики задач ($STARTS)"
	else
		fail "main.c: секундомеров $STARTS, а нужны итерация и каждая задача"
	fi
	match "$CODE" 'LOG_INF[[:space:]]*\(' \
		"main.c: при запуске журнал получает имя и версию прошивки" \
		"main.c: нет вызова LOG_INF при запуске"
	if grep -Eq 'time_us_|>>' "$CODE"; then
		fail "main.c: в main.c вычисления профилирования"
	else
		ok "main.c: только вызовы функций profiling"
	fi
fi

API="$(fw_join api.c api-callbacks.c)"
match "$API" '"profiling"' "api: есть команда profiling" "api: нет команды profiling"
match "$API" '"profiling_reset"' "api: есть команда profiling_reset" "api: нет команды profiling_reset"
match "$API" 'device_get_info[[:space:]]*\(' \
	"api: паспорт печатает обработчик команды info" \
	"api: обработчик info не вызывает device_get_info()"
if grep -Eq '"main_time_(exec|reset)"' "$API"; then
	fail "api: остались команды main_time_exec и main_time_reset"
else
	ok "api: команды main_time_* заменены командами profiling"
fi

finish "$TITLE"
