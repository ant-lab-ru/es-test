#!/usr/bin/env bash
# Задание п2.3.4 «Расчёт по шагам».
# Проверка статическая: расчёт π — задача pi-task, которая считает порцию членов ряда
# за вызов обработчика; команды pi_start и pi вместо calc_pi.
# Использование: check-2-3-4.sh <путь к репозиторию> [папка проекта]
set -u

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
. "$LIB/report.sh"
. "$LIB/code.sh"
. "$LIB/firmware.sh"

fw_start "Задание 2.3.4 — Расчёт по шагам" 231-firmware-template "${1:-.}" "${2:-}"

fw_need PI_H pi-task.h
fw_need PI_C pi-task.c

if [ -n "$PI_H" ]; then
	CODE="$(fw_code "$PI_H")"
	MISSING=""
	for fn in pi_task_start pi_task_handle pi_task_get_result; do
		grep -Eq "$fn[[:space:]]*\(" "$CODE" || MISSING="$MISSING $fn"
	done
	if [ -z "$MISSING" ]; then
		ok "pi-task.h: объявлены pi_task_start(), pi_task_handle() и pi_task_get_result()"
	else
		fail "pi-task.h: нет объявлений:$MISSING"
	fi
fi

if [ -n "$PI_C" ]; then
	CODE="$(fw_code "$PI_C")"
	BOTH="$(mktemp)"
	cat "$CODE" > "$BOTH"
	[ -n "$PI_H" ] && cat "$(fw_code "$PI_H")" >> "$BOTH"
	match "$BOTH" 'enum' \
		"pi-task: состояния задачи — перечисляемый тип" \
		"pi-task: нет перечисляемого типа состояний «не запускался», «считает», «готово»"
	match "$CODE" 'PI_TERMS_PER_CALL' \
		"pi-task.c: порция членов ряда задана константой PI_TERMS_PER_CALL" \
		"pi-task.c: нет константы PI_TERMS_PER_CALL"
	match "$CODE" '^[[:space:]]*static[[:space:]]+[a-z_0-9]+[[:space:]]+[a-z_0-9]+' \
		"pi-task.c: состояние расчёта в переменных файла со static" \
		"pi-task.c: нет переменных файла со static"
	if grep -Eq 'sleep_|busy_wait' "$CODE"; then
		fail "pi-task.c: в задаче есть пауза"
	else
		ok "pi-task.c: пауз нет"
	fi
fi

API="$(fw_join api.c api-callbacks.c)"
match "$API" '"pi_start"' "api: есть команда pi_start" "api: нет команды pi_start"
match "$API" '"pi"' "api: есть команда pi" "api: нет команды pi"
match "$API" 'pi is busy' \
	"api: повторный запуск во время расчёта — error: pi is busy" \
	"api: нет ответа error: pi is busy"
if grep -Eq '"calc_pi"' "$API"; then
	fail "api: осталась команда calc_pi"
	note "Расчёт целиком за один вызов держит ядро секунды. Его заменяют команды pi_start и pi."
else
	ok "api: команды calc_pi больше нет"
fi

MAIN="$FW_SRC/main.c"
if [ -f "$MAIN" ]; then
	match "$(fw_code "$MAIN")" 'pi_task_handle[[:space:]]*\(' \
		"main.c: суперцикл вызывает pi_task_handle()" \
		"main.c: нет вызова pi_task_handle()"
fi

finish "$TITLE"
