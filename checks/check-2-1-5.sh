#!/usr/bin/env bash
# Задание п2.1.5 «Чтение по адресу».
# Таблица векторов по фиксированному адресу и регистр SIO GPIO_IN через volatile.
# Использование: check-2-1-5.sh <путь к репозиторию> [папка проекта]
set -u

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
. "$LIB/report.sh"
. "$LIB/build.sh"
. "$LIB/device.sh"

TITLE="Задание 2.1.5 — Чтение по адресу"
REPO="${1:-.}"
PROJECT="${2:-211-command-usb}"
SRC="$REPO/$PROJECT"

if [ ! -d "$SRC" ]; then
	fail "В репозитории нет папки проекта $PROJECT"
	finish "$TITLE"
	exit 1
fi
ok "Папка проекта $PROJECT найдена"

for f in memory/memory.c check-2-1-5.py device-2-1-5.log; do
	if [ -f "$SRC/$f" ]; then
		ok "Файл $f на месте"
	else
		fail "В проекте нет файла $f"
	fi
done

BODY="$SRC/memory/memory.c"
if [ -f "$BODY" ]; then
	BODY="$(normalize "$BODY")"

	match "$BODY" '0x10000100' \
		"memory.c: таблица векторов читается по адресу 0x10000100" \
		"memory.c: нет адреса таблицы векторов 0x10000100"
	match "$BODY" 'vectors[[:space:]]*\(' \
		"memory.c: написана функция vectors" \
		"memory.c: нет функции vectors"
	match "$BODY" 'gpio_raw[[:space:]]*\(' \
		"memory.c: написана функция чтения регистра" \
		"memory.c: нет функции, читающей регистр GPIO"

	if grep -Eq 'SIO_GPIO_IN_OFFSET|0xd0000004' "$BODY"; then
		ok "memory.c: назван адрес регистра SIO GPIO_IN"
	else
		fail "memory.c: не видно адреса регистра SIO GPIO_IN"
		note "Адрес складывается из SIO_BASE и SIO_GPIO_IN_OFFSET и равен 0xd0000004."
	fi

	VOLATILE="$(grep -Ec 'volatile[[:space:]]+uint32_t[[:space:]]*\*' "$BODY")"
	if [ "$VOLATILE" -ge 2 ]; then
		ok "memory.c: указатели на память вне программы объявлены с volatile"
	elif [ "$VOLATILE" -eq 1 ]; then
		fail "memory.c: volatile стоит только у одного указателя из двух"
		note "Регистр периферии без volatile компилятор прочитает один раз и запомнит навсегда."
	else
		fail "memory.c: нет ни одного указателя с volatile"
	fi

	if grep -Eq '>>[[:space:]]*pin|>>[[:space:]]*[0-9]+' "$BODY" && grep -Eq '&[[:space:]]*1' "$BODY"; then
		ok "memory.c: разряд кнопки достаётся сдвигом и маской"
	else
		fail "memory.c: не видно, как из регистра достаётся разряд кнопки"
	fi
fi

MAIN="$SRC/main.c"
if [ -f "$MAIN" ]; then
	MAIN="$(normalize "$MAIN")"
	for cmd in vectors gpio; do
		match "$MAIN" "\"$cmd\"" \
			"main.c: разобрана команда $cmd" \
			"main.c: нет разбора команды $cmd"
	done
fi

if device_log "$SRC/device-2-1-5.log" "2.1.5"; then
	RECEIVED="$(device_received "$DEVICE_LOG")"

	if device_sent "$DEVICE_LOG" | grep -qx 'vectors'; then
		ok "Скрипт отправил команду vectors"
	else
		fail "В логе нет отправленной команды vectors"
	fi

	if echo "$RECEIVED" | grep -Eq '^0x10000100[[:space:]]+0x2[0-9a-f]{7}'; then
		ok "Первое слово таблицы векторов — адрес в ОЗУ: это начальное значение SP"
	else
		fail "По адресу 0x10000100 плата не вернула адрес в ОЗУ"
		note "Первым словом таблицы лежит вершина стека, она же конец области stack."
	fi

	if echo "$RECEIVED" | grep -Eq '^0x10000104[[:space:]]+0x1[0-9a-f]{7}'; then
		ok "Второе слово — адрес во флеш: обработчик сброса"
	else
		fail "По адресу 0x10000104 плата не вернула адрес во флеш-памяти"
	fi

	RESET="$(echo "$RECEIVED" | awk '$1 == "0x10000104" {print $2}' | head -1)"
	case "$RESET" in
		*[13579bdf]) ok "Адрес обработчика сброса нечётный — в нём признак набора команд Thumb" ;;
		"") fail "В логе нет значения по адресу 0x10000104" ;;
		*) warn "Адрес обработчика сброса чётный: обычно в таблице векторов он с признаком Thumb" ;;
	esac

	GPIO_CALLS="$(device_sent "$DEVICE_LOG" | grep -cx 'gpio')"
	if [ "$GPIO_CALLS" -ge 2 ]; then
		ok "Команда gpio вызвана $GPIO_CALLS раза"
	else
		fail "В логе меньше двух вызовов gpio"
	fi

	BUTTON="$(echo "$RECEIVED" | awk '$1 == "button" {print $2}')"
	BUTTON_STATES="$(echo "$BUTTON" | sort -u | grep -c .)"
	if [ "$BUTTON_STATES" -ge 2 ]; then
		ok "Разряд кнопки в логе принимает оба значения: кнопку нажимали на живой плате"
	else
		fail "Разряд кнопки в обоих вызовах одинаковый"
		note "Между двумя вызовами gpio кнопку нужно нажать и удерживать — иначе регистр не изменится."
	fi

	if echo "$RECEIVED" | grep -Eq '^0xd0000004[[:space:]]+0x[0-9a-f]{8}'; then
		ok "Плата назвала адрес регистра и его содержимое"
	else
		fail "В логе нет строки с адресом 0xd0000004"
	fi
fi

build_project "$SRC"

finish "$TITLE"
