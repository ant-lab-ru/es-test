#!/usr/bin/env bash
# Дополнительное задание п2.3.9д «Долгое нажатие».
# Проверка статическая: долгое нажатие — ещё одно событие кнопки. Его распознаёт машина
# задачи button-task проекта 239-two-buttons и сообщает о нём второй функцией,
# переданной при запуске; порог — 1 с; действие долгого нажатия задаёт main.c.
# Использование: check-2-3-9d.sh <путь к репозиторию> [папка проекта]
set -u

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
. "$LIB/report.sh"
. "$LIB/code.sh"
. "$LIB/firmware.sh"

fw_start "Задание 2.3.9д — Долгое нажатие" 239-two-buttons "${1:-.}" "${2:-}"

BUTTON_H="$FW_SRC/logic/button-task/button-task.h"
BUTTON_C="$FW_SRC/logic/button-task/button-task.c"
if [ ! -f "$BUTTON_H" ] || [ ! -f "$BUTTON_C" ]; then
	fail "В проекте нет задачи кнопки logic/button-task"
	note "Долгое нажатие распознаёт машина задачи кнопки."
	finish "$TITLE"
	exit 1
fi
ok "Задача кнопки logic/button-task на месте"

CODE="$(fw_code "$BUTTON_C")"
if grep -Eq '\b1000000\b|\b1000[[:space:]]*\*[[:space:]]*1000\b|\b1000\b' "$CODE"; then
	ok "button-task.c: порог долгого нажатия — 1 с"
else
	fail "button-task.c: не видно порога долгого нажатия в 1 с"
	note "Задайте порог константой: 1000000 мкс или 1000 мс."
fi
if grep -Eq 'enum' "$CODE" && grep -Eq 'switch[[:space:]]*\(' "$CODE"; then
	ok "button-task.c: долгое нажатие распознаёт машина состояний, enum и switch"
else
	fail "button-task.c: нет машины состояний: перечисляемого типа и switch"
	note "Переходы для долгого нажатия добавляются в машину кнопки из п2.3.3."
fi
match "$CODE" 'systime_' \
	"button-task.c: время удержания берётся из systime" \
	"button-task.c: время удержания берётся не из systime"
if grep -Eq 'sleep_|busy_wait|while' "$CODE"; then
	fail "button-task.c: распознавание долгого нажатия ждёт в цикле или на паузе"
	note "Машина сверяет часы с моментом нажатия на каждом вызове и сразу возвращается."
else
	ok "button-task.c: распознавание долгого нажатия не ждёт"
fi

# button_task_init получает две функции: на нажатие и на долгое нажатие
INIT="$(grep -Eo 'button_task_init[[:space:]]*\([^)]*\)' "$(fw_flat "$(fw_code "$BUTTON_H")")" | head -1)"
COMMAS="$(echo "$INIT" | tr -cd ',' | wc -c | tr -d ' ')"
if [ "$COMMAS" -ge 2 ]; then
	ok "button-task.h: button_task_init() получает вторую функцию — для долгого нажатия"
else
	fail "button-task.h: button_task_init() не получает функцию для долгого нажатия"
	note "О долгом нажатии задача сообщает второй функцией, переданной ей при запуске."
fi

if sed 's/systime_period_elapsed//g' "$(fw_join button-task.c button-task.h)" | grep -Eq '(^|[^a-z])led|period'; then
	fail "Задача кнопки знает, что делают нажатия"
	note "Действия короткого и долгого нажатия задаёт main.c."
else
	ok "Задача кнопки не знает, что делают нажатия"
fi

MAIN="$FW_SRC/main.c"
if [ -f "$MAIN" ]; then
	match "$(fw_flat "$(fw_code "$MAIN")")" 'button_task_init[[:space:]]*\([^)]*led_task_blink' \
		"main.c: долгое нажатие первой кнопки переводит светодиод в мигание, led_task_blink" \
		"main.c: нет действия долгого нажатия led_task_blink в button_task_init()"
fi

finish "$TITLE"
