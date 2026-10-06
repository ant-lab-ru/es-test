#!/usr/bin/env bash
# Задание п2.3.9 «Изменение требований».
# Проверка статическая: проект 239-two-buttons — копия шаблона с новым именем;
# вторая кнопка меняет период мигания по кругу 250 → 500 → 1000 мс, а правки легли
# только туда, куда указывают правила шаблона: механизм api.c и задача π не изменились.
# Использование: check-2-3-9.sh <путь к репозиторию> [папка проекта] [папка шаблона]
set -u

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
. "$LIB/report.sh"
. "$LIB/code.sh"
. "$LIB/cmake.sh"
. "$LIB/firmware.sh"

fw_start "Задание 2.3.9 — Изменение требований" 239-two-buttons "${1:-.}" "${2:-}"
TEMPLATE="$FW_REPO/${3:-231-firmware-template}"

if [ -d "$TEMPLATE" ]; then
	ok "Шаблон ${TEMPLATE#$FW_REPO/} остался на месте"
else
	fail "Нет папки шаблона ${TEMPLATE#$FW_REPO/}"
	note "Новый проект — копия папки шаблона. Сам шаблон остаётся в репозитории."
fi

CMAKE="$FW_SRC/CMakeLists.txt"
if [ -f "$CMAKE" ]; then
	match "$(cmake_flatten "$CMAKE")" 'project[[:space:]]*\([[:space:]]*239_two_buttons[[:space:]]*\)' \
		"CMakeLists.txt: проект назван 239_two_buttons" \
		"CMakeLists.txt: в project() не 239_two_buttons"
fi
if [ -f "$FW_SRC/firmware.h" ]; then
	match "$(normalize "$FW_SRC/firmware.h")" '"239-two-buttons"' \
		"firmware.h: имя проекта 239-two-buttons" \
		"firmware.h: имя проекта не 239-two-buttons"
else
	fail "В проекте нет firmware.h"
fi

# что не должно было измениться
for f in logic/api/api.c logic/api/api.h logic/api/api-commands.h logic/pi-task/pi-task.c logic/pi-task/pi-task.h; do
	if [ ! -f "$FW_SRC/$f" ] || [ ! -f "$TEMPLATE/$f" ]; then
		fail "Нет файла $f в проекте или в шаблоне"
	elif diff -q "$(normalize "$FW_SRC/$f")" "$(normalize "$TEMPLATE/$f")" > /dev/null; then
		ok "$f не изменился"
	else
		fail "$f отличается от шаблона"
		note "Новая кнопка — это железо и поведение. Механизм команд и расчёт π её не касаются."
	fi
done

# что должно было измениться
for f in platform/platform.c main.c; do
	if [ -f "$FW_SRC/$f" ] && [ -f "$TEMPLATE/$f" ] &&
		! diff -q "$(normalize "$FW_SRC/$f")" "$(normalize "$TEMPLATE/$f")" > /dev/null; then
		ok "$f изменился: здесь новая кнопка"
	else
		fail "$f не отличается от шаблона"
	fi
done

PLATFORM="$(fw_code "$FW_SRC/platform/platform.c" 2>/dev/null)"
if [ -f "$FW_SRC/platform/platform.c" ]; then
	PINS="$(grep -Eo '\b([0-9]|1[0-9]|2[0-8])\b' "$PLATFORM" | sort -u | wc -l | tr -d ' ')"
	TEMPLATE_PINS="$(grep -Eo '\b([0-9]|1[0-9]|2[0-8])\b' "$(fw_code "$TEMPLATE/platform/platform.c")" | sort -u | wc -l | tr -d ' ')"
	if [ "$PINS" -gt "$TEMPLATE_PINS" ]; then
		ok "platform.c: у платы появился ещё один вывод"
	else
		fail "platform.c: не видно вывода второй кнопки"
		note "Номер вывода кнопки знает только platform.c."
	fi
fi

LOGIC="$(mktemp)"
find "$FW_SRC/logic" -type f \( -name '*.c' -o -name '*.h' \) 2>/dev/null | sort | while read -r f; do cat "$(fw_code "$f")"; done > "$LOGIC"
if grep -Eq '\b250\b' "$LOGIC" && grep -Eq '\b500\b' "$LOGIC" && grep -Eq '\b1000\b' "$LOGIC"; then
	ok "logic: период мигания по кругу 250, 500 и 1000 мс"
else
	fail "logic: не видно круга периодов 250 → 500 → 1000 мс"
	note "Какой период следующий — поведение светодиода, его место в logic/."
fi

COUNT="$(grep -Eo 'button_init[[:space:]]*\(' "$(fw_code "$FW_SRC/main.c")" | wc -l | tr -d ' ')"
if [ "$COUNT" -ge 2 ] || grep -Eq 'for[[:space:]]*\(' "$(fw_code "$FW_SRC/main.c")"; then
	ok "main.c: связи обеих кнопок задаёт main.c"
else
	fail "main.c: связь второй кнопки не задана"
	note "Что делает нажатие, решает main.c: он передаёт кнопке функцию при запуске."
fi

if grep -Eq 'led|period' "$(fw_join button.c button.h)"; then
	fail "Библиотека кнопки знает, что делает нажатие"
else
	ok "Библиотека кнопки по-прежнему не знает, что делает нажатие"
fi

finish "$TITLE"
