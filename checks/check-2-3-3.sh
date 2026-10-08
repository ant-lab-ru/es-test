#!/usr/bin/env bash
# Задание п2.3.3 «Кнопка без ожидания».
# Проверка статическая: подавление дребезга — машина состояний в задаче button-task без пауз,
# новый уровень принимается через 20 мс, нажатие переключает светодиод по кругу.
# В 2.3.7 задача переезжает в logic/, вывод кнопки — в platform.
# Использование: check-2-3-3.sh <путь к репозиторию> [папка проекта]
set -u

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
. "$LIB/report.sh"
. "$LIB/code.sh"
. "$LIB/firmware.sh"

fw_start "Задание 2.3.3 — Кнопка без ожидания" 231-firmware-template "${1:-.}" "${2:-}"

fw_need BUTTON_H button-task.h
fw_need BUTTON_C button-task.c

if [ -n "$BUTTON_H" ]; then
	CODE="$(fw_code "$BUTTON_H")"
	MISSING=""
	for fn in button_task_init button_task_handle button_task_is_pressed button_task_get_press_count; do
		grep -Eq "$fn[[:space:]]*\(" "$CODE" || MISSING="$MISSING $fn"
	done
	if [ -z "$MISSING" ]; then
		ok "button-task.h: объявлены функции задачи кнопки"
	else
		fail "button-task.h: нет объявлений:$MISSING"
		note "Интерфейс задачи кнопки — button_task_init(), button_task_handle(), button_task_is_pressed() и button_task_get_press_count()."
	fi
fi

if [ -n "$BUTTON_C" ]; then
	CODE="$(fw_code "$BUTTON_C")"
	if grep -Eq 'enum' "$CODE" && grep -Eq 'switch[[:space:]]*\(' "$CODE"; then
		ok "button-task.c: подавление дребезга — машина состояний, enum и switch"
	else
		fail "button-task.c: нет машины состояний: перечисляемого типа и switch"
		note "Машина из четырёх состояний разобрана в т2.3.4, раздел «Переходы по времени»."
	fi
	if grep -Eq 'sleep_|busy_wait' "$CODE"; then
		fail "button-task.c: в задаче кнопки есть пауза"
		note "Обработчик сверяет уровень и часы с условиями перехода и сразу возвращается."
	else
		ok "button-task.c: пауз нет"
	fi
fi

CODE="$(fw_join '*.c' '*.h')"
if grep -Eq '\b20000\b|\b20[[:space:]]*\*[[:space:]]*1000\b' "$CODE"; then
	ok "Время дребезга 20 мс задано константой"
else
	fail "Не видно времени дребезга 20 мс: 20000 мкс или 20 * 1000"
	note "Задайте время дребезга константой в микросекундах."
fi
match "$CODE" 'gpio_pull_up[[:space:]]*\(' \
	"Вывод кнопки подтянут к питанию, gpio_pull_up()" \
	"Нет подтяжки вывода кнопки к питанию gpio_pull_up()"

fw_need LED_H led-task.h
if [ -n "$LED_H" ]; then
	match "$(fw_code "$LED_H")" 'led_task_next_state[[:space:]]*\(' \
		"led-task.h: объявлена led_task_next_state() — следующее состояние по кругу" \
		"led-task.h: нет функции led_task_next_state()"
fi

API="$(fw_join api.c api-callbacks.c)"
match "$API" '"button"' \
	"api: есть команда button" \
	"api: нет команды button"
match "$API" 'presses' \
	"api: ответ button сообщает число нажатий" \
	"api: в ответе button нет числа нажатий presses"

MAIN="$FW_SRC/main.c"
if [ -f "$MAIN" ]; then
	match "$(fw_code "$MAIN")" 'button_task_handle[[:space:]]*\(' \
		"main.c: суперцикл вызывает обработчик задачи кнопки" \
		"main.c: нет вызова button_task_handle()"
fi

finish "$TITLE"
