#!/usr/bin/env bash
# Дополнительное задание п2.3.9д «Долгое нажатие».
# Проверка статическая: распознавание долгого нажатия — поведение прибора, оно лежит
# в logic/ проекта 239-two-buttons, а не в библиотеке кнопки; порог — 1 с.
# Использование: check-2-3-9d.sh <путь к репозиторию> [папка проекта]
set -u

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
. "$LIB/report.sh"
. "$LIB/code.sh"
. "$LIB/firmware.sh"

fw_start "Задание 2.3.9д — Долгое нажатие" 239-two-buttons "${1:-.}" "${2:-}"

TASKS="$(find "$FW_SRC/logic" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | grep -Ev '/(api|led-task|pi-task)$')"
if [ -n "$TASKS" ]; then
	ok "logic: новый модуль для жестов кнопки: $(basename "$TASKS" | tr '\n' ' ')"
else
	fail "logic: нет нового модуля, который распознаёт долгое нажатие"
	note "Истолкование жестов — поведение прибора. Его место в logic/, рядом с задачами."
fi

GESTURE="$(mktemp)"
for d in $TASKS; do
	find "$d" -type f \( -name '*.c' -o -name '*.h' \) | while read -r f; do cat "$(fw_code "$f")"; done
done > "$GESTURE"
if grep -Eq '\b1000000\b|\b1000[[:space:]]*\*[[:space:]]*1000\b|\b1000\b' "$GESTURE"; then
	ok "Порог долгого нажатия — 1 с"
else
	fail "Не видно порога долгого нажатия в 1 с"
fi
if grep -Eq 'enum' "$GESTURE" && grep -Eq 'switch[[:space:]]*\(' "$GESTURE"; then
	ok "Долгое нажатие — машина состояний, enum и switch"
else
	fail "Долгое нажатие распознаётся не машиной состояний"
fi
match "$GESTURE" 'systime_' \
	"Время удержания берётся из systime" \
	"Время удержания берётся не из systime"
if grep -Eq 'sleep_|busy_wait|while' "$GESTURE"; then
	fail "Распознавание долгого нажатия ждёт в цикле или на паузе"
else
	ok "Распознавание долгого нажатия не ждёт"
fi

if grep -Eiq 'long' "$(fw_join button.c button.h)"; then
	fail "Долгое нажатие распознаёт библиотека кнопки"
	note "Библиотека подавляет дребезг для любого прибора. Что значит удержание, решает этот прибор."
else
	ok "Библиотека кнопки о долгом нажатии не знает"
fi

finish "$TITLE"
