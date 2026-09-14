#!/usr/bin/env bash
# Задание п2.1.4 «Память программы».
# Адреса кода, констант, стека и кучи; сброс признака Thumb; malloc с проверкой.
# Использование: check-2-1-4.sh <путь к репозиторию> [папка проекта]
set -u

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
. "$LIB/report.sh"
. "$LIB/build.sh"
. "$LIB/device.sh"

TITLE="Задание 2.1.4 — Память программы"
REPO="${1:-.}"
PROJECT="${2:-211-command-usb}"
SRC="$REPO/$PROJECT"

if [ ! -d "$SRC" ]; then
	fail "В репозитории нет папки проекта $PROJECT"
	finish "$TITLE"
	exit 1
fi
ok "Папка проекта $PROJECT найдена"

for f in memory/memory.c check-2-1-4.py device-2-1-4.log; do
	if [ -f "$SRC/$f" ]; then
		ok "Файл $f на месте"
	else
		fail "В проекте нет файла $f"
	fi
done

BODY="$SRC/memory/memory.c"
if [ -f "$BODY" ]; then
	BODY="$(normalize "$BODY")"

	match "$BODY" 'fw_info[[:space:]]*\(' \
		"memory.c: написана функция fw_info" \
		"memory.c: нет функции fw_info"

	# Адресов функций в задании два, и маску надо снять с каждого:
	# забытая на одном из них останавливает прошивку так же надёжно, как на обоих.
	THUMB="$(grep -Ec '~[[:space:]]*1' "$BODY")"
	if [ "$THUMB" -ge 2 ]; then
		ok "memory.c: признак Thumb сбрасывается у обоих адресов функций"
	elif [ "$THUMB" -eq 1 ]; then
		fail "memory.c: признак Thumb сброшен только у одного адреса функции из двух"
		note "Чтение по нечётному адресу останавливает прошивку ошибкой HardFault — маска нужна обеим."
	else
		fail "memory.c: адрес функции читается без сброса младшего разряда"
		note "Чтение по нечётному адресу останавливает прошивку ошибкой HardFault."
	fi

	match "$BODY" 'uint16_t' \
		"memory.c: команда кода читается как двухбайтное число" \
		"memory.c: нет чтения через uint16_t — команда Thumb занимает два байта"
	match "$BODY" 'malloc[[:space:]]*\(' \
		"memory.c: блок памяти берётся в куче вызовом malloc" \
		"memory.c: нет вызова malloc"

	if grep -Eq 'NULL' "$BODY"; then
		ok "memory.c: результат malloc проверяется на NULL"
	else
		fail "memory.c: результат malloc не проверяется на NULL"
		note "malloc возвращает нулевой указатель, когда места нет; запись по нему роняет прошивку."
	fi

	match "$BODY" 'int[[:space:]]+main[[:space:]]*\(' \
		"memory.c: main объявлена, чтобы взять её адрес" \
		"memory.c: нет объявления main — взять её адрес из другого файла не получится"
fi

MAIN="$SRC/main.c"
if [ -f "$MAIN" ]; then
	MAIN="$(normalize "$MAIN")"
	match "$MAIN" '"fw_info"' \
		"main.c: разобрана команда fw_info" \
		"main.c: нет разбора команды fw_info"
fi

if device_log "$SRC/device-2-1-4.log" "2.1.4"; then
	RECEIVED="$(device_received "$DEVICE_LOG")"

	CALLS="$(device_sent "$DEVICE_LOG" | grep -cx 'fw_info')"
	if [ "$CALLS" -ge 2 ]; then
		ok "Команда fw_info вызвана $CALLS раза подряд"
	else
		fail "В логе меньше двух вызовов fw_info"
		note "Два вызова нужны, чтобы увидеть, как ведут себя адреса стека и кучи."
	fi

	MISSING=""
	for obj in main fw_info DEVICE_TAG boot_marker stack_variable heap_variable; do
		echo "$RECEIVED" | grep -Eq "^$obj[[:space:]]+0x[0-9a-f]{8}" || MISSING="$MISSING $obj"
	done
	if [ -z "$MISSING" ]; then
		ok "Плата напечатала адреса всех шести объектов"
	else
		fail "В ответе платы нет адресов:$MISSING"
	fi

	if echo "$RECEIVED" | grep -Eq '^main[[:space:]]+0x1000'; then
		ok "Код лежит во флеш-памяти"
	else
		fail "Адрес main не похож на адрес флеш-памяти (0x1000…)"
	fi

	if echo "$RECEIVED" | grep -Eq '^boot_marker[[:space:]]+0x2000'; then
		ok "Переменная с начальным значением работает из ОЗУ"
	else
		fail "Адрес boot_marker не похож на адрес ОЗУ (0x2000…)"
	fi

	if echo "$RECEIVED" | grep -Eq '^stack_variable[[:space:]]+0x2004'; then
		ok "Локальная переменная лежит на стеке, в конце ОЗУ"
	else
		fail "Адрес локальной переменной не похож на адрес стека (0x2004…)"
	fi

	HEAP="$(echo "$RECEIVED" | awk '$1 == "heap_variable" {print $2}')"
	HEAP_UNIQUE="$(echo "$HEAP" | sort -u | wc -l | tr -d ' ')"
	HEAP_COUNT="$(echo "$HEAP" | grep -c .)"
	if [ "$HEAP_COUNT" -ge 2 ] && [ "$HEAP_UNIQUE" -ge 2 ]; then
		ok "При повторном вызове адрес в куче сдвинулся: прошлый блок не возвращён"
	elif [ "$HEAP_COUNT" -ge 2 ]; then
		fail "Адрес в куче не изменился между вызовами"
		note "Без free() каждый вызов malloc берёт новый блок — адрес обязан вырасти."
	else
		fail "В логе меньше двух строк heap_variable"
	fi

	STACK="$(echo "$RECEIVED" | awk '$1 == "stack_variable" {print $2}' | sort -u | wc -l | tr -d ' ')"
	if [ "$STACK" = "1" ]; then
		ok "Адрес локальной переменной у обоих вызовов один и тот же"
	else
		warn "Адрес локальной переменной между вызовами изменился — глубина вызова была разной"
	fi
fi

build_project "$SRC"

finish "$TITLE"
