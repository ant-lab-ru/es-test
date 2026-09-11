#!/usr/bin/env bash
# Задание п1.3.3 «Вывод состояния светодиода».
# Кнопка с подавлением дребезга, вывод состояния в USB при изменении, имя проекта,
# сборка и лог прогона на устройстве, снятый скриптом задания.
# Использование: check-1-3-3.sh <путь к репозиторию> [папка проекта]
set -u

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
. "$LIB/report.sh"
. "$LIB/build.sh"
. "$LIB/cmake.sh"
. "$LIB/device.sh"

TITLE="Задание 1.3.3 — Вывод состояния светодиода"
REPO="${1:-.}"
PROJECT="${2:-133-led-button-usb}"
SRC="$REPO/$PROJECT"

if [ ! -d "$SRC" ]; then
	fail "В репозитории нет папки проекта $PROJECT"
	finish "$TITLE"
	exit 1
fi
ok "Папка проекта $PROJECT найдена"

for f in main.c CMakeLists.txt memmap_rp2040.ld pico_sdk_import.cmake check-1-3-3.py device-1-3-3.log; do
	if [ -f "$SRC/$f" ]; then
		ok "Файл $f на месте"
	else
		fail "В проекте нет файла $f"
	fi
done

CMAKE="$SRC/CMakeLists.txt"
if [ -f "$CMAKE" ]; then
	CMAKE="$(normalize "$CMAKE")"
	match "$CMAKE" 'pico_enable_stdio_usb[[:space:]]*\([^)]*1[[:space:]]*\)' \
		"CMakeLists.txt: вывод через USB включён" \
		"CMakeLists.txt: нет pico_enable_stdio_usb с единицей — вывод в USB не попадёт"
fi

MAIN="$SRC/main.c"
if [ -f "$MAIN" ]; then
	MAIN="$(normalize "$MAIN")"

	match "$MAIN" '#include[[:space:]]*<stdio\.h>' \
		"main.c: подключён заголовочный файл stdio.h" \
		"main.c: нет #include <stdio.h> — printf объявлен в нём"
	match "$MAIN" 'stdio_init_all[[:space:]]*\(' \
		"main.c: стандартный ввод-вывод инициализирован" \
		"main.c: нет вызова stdio_init_all — канал не откроется"
	match "$MAIN" 'gpio_pull_up[[:space:]]*\(|gpio_pull_down[[:space:]]*\(|gpio_set_pulls[[:space:]]*\(' \
		"main.c: на выводе кнопки включена подтяжка" \
		"main.c: подтяжка не включена — отпущенная кнопка будет читаться случайно"
	match "$MAIN" 'bool[[:space:]]+get_button_debounce[[:space:]]*\([[:space:]]*uint[[:space:]]+[A-Za-z_]' \
		"main.c: подавление дребезга из прошлого задания на месте" \
		"main.c: нет функции bool get_button_debounce(uint pin) — она переносится из п1.2.3"
	match "$MAIN" 'printf[[:space:]]*\(' \
		"main.c: состояние печатается вызовом printf" "main.c: нет ни одного вызова printf"

	# Печать состояния идёт по событию: она стоит внутри условия, а не отдельной
	# строкой суперцикла. Условие переключения ищется вместе со следующими строками.
	if awk '/if[ \t]*\(/{c=6} c>0 {print; c--}' "$MAIN" | grep -Eq 'printf[[:space:]]*\(|set_led[[:space:]]*\('; then
		ok "main.c: состояние печатается внутри условия — при изменении"
	else
		fail "main.c: печать состояния не привязана к условию переключения"
		note "Строка должна уходить в порт при изменении, а не в каждом проходе суперцикла."
	fi
fi

check_project_name "$SRC" "$PROJECT"

if device_log "$SRC/device-1-3-3.log" "1.3.3"; then
	STATES="$(device_received "$DEVICE_LOG" | grep -Eo 'led (on|off)')"
	COUNT="$(echo "$STATES" | grep -c 'led')"
	if [ "$COUNT" -ge 4 ]; then
		ok "Плата сообщила о состоянии светодиода $COUNT раз"
	else
		fail "В логе только $COUNT сообщений о состоянии — нужно не меньше четырёх"
		note "Скрипт ждёт нажатий: нажмите кнопку столько раз, сколько он просит."
	fi

	if [ "$(echo "$STATES" | uniq | wc -l | tr -d ' ')" = "$COUNT" ]; then
		ok "Состояние менялось при каждом нажатии: on и off чередуются"
	else
		fail "В логе два одинаковых состояния подряд"
		note "Одно нажатие — одно переключение: два on подряд означают потерянное нажатие или дребезг."
	fi

	SPACING="$(awk '
		/<--/ { t = $1 + 0; if (n > 0 && t - p < 0.2) bad++; p = t; n++ }
		END { print (bad == 0) ? "ok" : "bad" }' "$DEVICE_LOG")"
	if [ "$SPACING" = "ok" ]; then
		ok "Строки шли по событию, а не потоком"
	else
		fail "Строки в логе идут сплошным потоком"
		note "Похоже, состояние печатается в каждом проходе суперцикла, а не при изменении."
	fi
fi

build_project "$SRC"

finish "$TITLE"
