#!/usr/bin/env bash
# Задание п2.3.2 «Задача светодиода».
# Проверка статическая: мигание ушло из суперцикла в задачу led-task с перечисляемым типом
# состояний, обработчиком на switch и проверкой периода от прошлого срабатывания.
# Проверка периода в 2.3.6 переезжает в библиотеку systime, задача — в logic/.
# Использование: check-2-3-2.sh <путь к репозиторию> [папка проекта]
set -u

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
. "$LIB/report.sh"
. "$LIB/code.sh"
. "$LIB/cmake.sh"
. "$LIB/firmware.sh"

fw_start "Задание 2.3.2 — Задача светодиода" 231-firmware-template "${1:-.}" "${2:-}"

fw_need LED_H led-task.h
fw_need LED_C led-task.c

if [ -n "$LED_H" ]; then
	CODE="$(fw_code "$LED_H")"
	FLAT="$(fw_flat "$CODE")"
	if grep -Eq 'typedef[[:space:]]+enum[^}]*LED_STATE_OFF[^}]*\}[[:space:]]*led_state_t' "$FLAT" &&
		grep -Eq 'LED_STATE_ON' "$CODE" && grep -Eq 'LED_STATE_BLINK' "$CODE"; then
		ok "led-task.h: перечисляемый тип led_state_t с состояниями OFF, ON и BLINK"
	else
		fail "led-task.h: нет перечисляемого типа led_state_t с LED_STATE_OFF, LED_STATE_ON и LED_STATE_BLINK"
		note "Тип дан дословно в шаге 1 задания п2.3.2."
	fi
	MISSING=""
	for fn in led_task_init led_task_handle led_task_set_state led_task_get_state led_task_set_period_ms led_task_get_period_ms; do
		grep -Eq "$fn[[:space:]]*\(" "$CODE" || MISSING="$MISSING $fn"
	done
	if [ -z "$MISSING" ]; then
		ok "led-task.h: объявлены функции задачи светодиода"
	else
		fail "led-task.h: нет объявлений:$MISSING"
		note "Заголовок задачи разобран в т2.3.5, к нему добавляется led_task_get_period_ms()."
	fi
fi

if [ -n "$LED_C" ]; then
	CODE="$(fw_code "$LED_C")"
	HANDLE="$(mktemp)"
	function_body "$CODE" 'led_task_handle' > "$HANDLE"
	match "$HANDLE" 'switch[[:space:]]*\(' \
		"led-task.c: обработчик выбирает действие по состоянию, switch" \
		"led-task.c: в led_task_handle() нет switch по состоянию"
	match "$HANDLE" 'period_elapsed[[:space:]]*\(' \
		"led-task.c: мигание по проверке периода" \
		"led-task.c: в led_task_handle() нет вызова проверки периода period_elapsed()"
	SET="$(mktemp)"
	function_body "$CODE" 'led_task_set_state' > "$SET"
	if grep -Eq 'switch|LED_STATE_ON' "$SET"; then
		ok "led-task.c: действие при входе — в функции смены состояния"
	else
		fail "led-task.c: в led_task_set_state() не видно действия при входе в состояние"
		note "Включить или выключить светодиод нужно один раз, в момент перехода, а не на каждой итерации."
	fi
	if grep -Eq 'sleep_|busy_wait' "$CODE"; then
		fail "led-task.c: в задаче есть пауза"
		note "Обработчик не ждёт: вместо паузы он сверяет часы с меткой (т2.3.3)."
	else
		ok "led-task.c: пауз нет"
	fi
fi

# Проверка периода: сначала в led-task.c, с 2.3.6 — в библиотеке systime
PERIOD="$(mktemp)"
for f in $(find "$FW_SRC" "$FW_LIBS" -type f -name '*.c' -not -path '*/build/*' 2>/dev/null); do
	function_body "$(fw_code "$f")" 'period_elapsed' >> "$PERIOD"
done
if [ ! -s "$PERIOD" ]; then
	fail "Нет функции проверки периода period_elapsed()"
	note "Проверка периода разобрана в т2.3.3, раздел «Периодические задачи»."
elif grep -Eq '\+=' "$PERIOD"; then
	ok "Следующее срабатывание отсчитывается от прошлого: last += period"
else
	fail "В проверке периода нет сдвига метки на период"
	note "С last = now каждое срабатывание опаздывает на долю итерации, и ошибка копится."
fi

API="$(fw_join api.c api-callbacks.c)"
for cmd in led_enable led_disable led_blink led_period; do
	match "$API" "\"$cmd\"" \
		"api: есть команда $cmd" \
		"api: нет команды $cmd"
done
match "$API" 'usage led_period' \
	"api: ошибка в записи периода — error: usage led_period <period_ms>" \
	"api: нет ответа error: usage led_period <period_ms>"

CMAKE="$FW_SRC/CMakeLists.txt"
if [ -f "$CMAKE" ]; then
	match "$(normalize "$CMAKE")" '[-]Wall' \
		"CMakeLists.txt: проект собирается с ключом -Wall" \
		"CMakeLists.txt: нет ключа -Wall"
fi

MAIN="$FW_SRC/main.c"
if [ -f "$MAIN" ]; then
	CODE="$(fw_code "$MAIN")"
	match "$CODE" 'led_task_handle[[:space:]]*\(' \
		"main.c: суперцикл вызывает led_task_handle()" \
		"main.c: нет вызова led_task_handle()"
	if grep -Eq 'gpio_put|led_toggle|time_us_' "$CODE"; then
		fail "main.c: мигание осталось в суперцикле"
		note "Светодиодом теперь управляет задача. В main.c только её запуск и вызов обработчика."
	else
		ok "main.c: мигания в суперцикле нет"
	fi
fi

finish "$TITLE"
