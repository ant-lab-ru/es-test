#!/usr/bin/env bash
# Задание п1.3.2 «Скрипт проверки на устройстве».
# Скрипт опроса платы и лог прогона, снятый им с прошивки задания 1.3.1.
# Прошивка здесь не собирается: её состав и сборку проверяет 1.3.1.
# Использование: check-1-3-2.sh <путь к репозиторию> [папка проекта]
set -u

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
. "$LIB/report.sh"
. "$LIB/device.sh"

TITLE="Задание 1.3.2 — Скрипт проверки на устройстве"
REPO="${1:-.}"
PROJECT="${2:-131-hello-usb}"
SRC="$REPO/$PROJECT"

if [ ! -d "$SRC" ]; then
	fail "В репозитории нет папки проекта $PROJECT"
	finish "$TITLE"
	exit 1
fi
ok "Папка проекта $PROJECT найдена"

SCRIPT="$SRC/check-1-3-2.py"
if [ -f "$SCRIPT" ]; then
	ok "Файл check-1-3-2.py на месте"
	SCRIPT="$(normalize "$SCRIPT")"

	match "$SCRIPT" 'import[[:space:]]+serial|from[[:space:]]+serial' \
		"check-1-3-2.py: подключена библиотека работы с портом" \
		"check-1-3-2.py: нет обращения к библиотеке serial"
	match "$SCRIPT" 'list_ports' \
		"check-1-3-2.py: порты компьютера перебираются списком" \
		"check-1-3-2.py: нет перебора портов через list_ports"
	match "$SCRIPT" '0[xX]2[eE]8[aA]' \
		"check-1-3-2.py: плата ищется по коду производителя Raspberry Pi" \
		"check-1-3-2.py: в скрипте нет кода производителя 0x2E8A"
	match "$SCRIPT" '\.vid|\.pid' \
		"check-1-3-2.py: сверяются коды USB-устройства, а не имя порта" \
		"check-1-3-2.py: плата не опознаётся по коду устройства"
	match "$SCRIPT" 'timeout[[:space:]]*=' \
		"check-1-3-2.py: у порта задано предельное время ожидания" \
		"check-1-3-2.py: нет timeout — скрипт зависнет на молчащей плате"
	match "$SCRIPT" 'serial_number' \
		"check-1-3-2.py: в лог пишется серийный номер платы" \
		"check-1-3-2.py: серийный номер платы не читается"
	match "$SCRIPT" 'encoding[[:space:]]*=[[:space:]]*"utf-8"|encoding[[:space:]]*=[[:space:]]*.utf-8.' \
		"check-1-3-2.py: лог пишется в кодировке UTF-8" \
		"check-1-3-2.py: у файла лога не задана кодировка utf-8"
else
	fail "В проекте нет файла check-1-3-2.py"
	note "Скрипт задания лежит рядом с main.c проекта $PROJECT."
fi

if device_log "$SRC/device-1-3-2.log" "1.3.2"; then
	COUNT="$(device_received "$DEVICE_LOG" | grep -c '^Hello, world!$')"
	if [ "$COUNT" -ge 5 ]; then
		ok "Плата прислала строку Hello, world! $COUNT раз"
	else
		fail "В логе только $COUNT строк Hello, world! — нужно не меньше пяти"
		note "Скрипт слушает порт десять секунд: за это время строк набирается около десяти."
	fi

	PERIOD="$(awk '
		/<--/ { t = $1 + 0; if (n > 0) { d = t - p; if (d < 0.7 || d > 1.4) bad++ } p = t; n++ }
		END { print (n > 1 && bad == 0) ? "ok" : "bad" }' "$DEVICE_LOG")"
	if [ "$PERIOD" = "ok" ]; then
		ok "Строки приходили раз в секунду"
	else
		fail "Строки приходили не раз в секунду"
		note "Между соседними метками времени в логе должна быть примерно секунда."
	fi

	if grep -Eq '^проект: 131-hello-usb[[:space:]]*$' "$DEVICE_LOG"; then
		ok "Лог снят с проекта 131-hello-usb"
	else
		warn "В шапке лога другое имя проекта"
	fi
fi

note "Прошивка в этой проверке не собирается: её состав и сборку проверяет задание 1.3.1."
finish "$TITLE"
