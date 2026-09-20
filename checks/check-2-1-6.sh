#!/usr/bin/env bash
# Задание п2.1.6 «Чтение по адресу».
# Таблица векторов по фиксированному адресу и регистр SIO GPIO_IN через volatile.
# Использование: check-2-1-6.sh <путь к репозиторию> [папка проекта]
set -u

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
. "$LIB/report.sh"
. "$LIB/build.sh"
. "$LIB/device.sh"

TITLE="Задание 2.1.6 — Чтение по адресу"
REPO="${1:-.}"
PROJECT="${2:-211-command-usb}"
SRC="$REPO/$PROJECT"

if [ ! -d "$SRC" ]; then
	fail "В репозитории нет папки проекта $PROJECT"
	finish "$TITLE"
	exit 1
fi
ok "Папка проекта $PROJECT найдена"

for f in memory/memory.c led/led.c led/led.h check-2-1-6.py device-2-1-6.log; do
	if [ -f "$SRC/$f" ]; then
		ok "Файл $f на месте"
	else
		fail "В проекте нет файла $f"
	fi
done

BODY="$SRC/memory/memory.c"
if [ -f "$BODY" ]; then
	BODY="$(normalize "$BODY")"

	match "$BODY" 'boot_info[[:space:]]*\(' \
		"memory.c: написана функция boot_info" \
		"memory.c: нет функции boot_info"
	match "$BODY" '0x10000100' \
		"memory.c: таблица векторов читается по адресу 0x10000100" \
		"memory.c: нет адреса таблицы векторов 0x10000100"

	if grep -Eq '\([[:space:]]*(const[[:space:]]+)?uint32_t[[:space:]]*\*[[:space:]]*\)' "$BODY"; then
		ok "memory.c: число превращается в указатель приведением типа"
	else
		fail "memory.c: не видно приведения числа к типу указателя"
		note "Адрес из документации — это просто число: (const uint32_t *)0x10000100."
	fi

	if grep -Eq '0xd0000004|SIO_GPIO_IN_OFFSET' "$BODY"; then
		ok "memory.c: назван адрес регистра SIO GPIO_IN"
	else
		fail "memory.c: не видно адреса регистра SIO GPIO_IN"
		note "Адрес складывается из SIO_BASE и SIO_GPIO_IN_OFFSET и равен 0xd0000004."
	fi

	if grep -Eq 'volatile[[:space:]]+uint32_t[[:space:]]*\*' "$BODY"; then
		ok "memory.c: указатель на регистр объявлен с volatile"
	else
		fail "memory.c: указатель на регистр объявлен без volatile"
		note "Регистр периферии без volatile компилятор прочитает один раз и дальше будет подставлять запомненное."
	fi

	if grep -Eq '>>[[:space:]]*led_pin[[:space:]]*\(|>>[[:space:]]*[a-z_]+' "$BODY" && grep -Eq '&[[:space:]]*1' "$BODY"; then
		ok "memory.c: разряд вывода достаётся из регистра сдвигом и маской"
	else
		fail "memory.c: не видно, как из регистра достаётся разряд вывода"
	fi

	match "$BODY" '~[[:space:]]*1' \
		"memory.c: у адреса обработчика сброса сбрасывается младший разряд" \
		"memory.c: адрес обработчика сброса не печатается со сброшенным признаком Thumb"
	match "$BODY" 'led_pin[[:space:]]*\(' \
		"memory.c: номер вывода светодиода спрашивается у модуля led" \
		"memory.c: нет вызова led_pin — номер вывода знает только модуль led"

	if grep -Eq 'LED_PIN' "$BODY"; then
		fail "memory.c: номер вывода светодиода взят из модуля led константой"
		note "Номер остаётся делом модуля led: наружу выдаётся ответ на вопрос, а не константа."
	else
		ok "memory.c: номер вывода светодиода не продублирован"
	fi
fi

HEADER="$SRC/led/led.h"
if [ -f "$HEADER" ]; then
	HEADER="$(normalize "$HEADER")"
	match "$HEADER" 'led_pin[[:space:]]*\([[:space:]]*void[[:space:]]*\)' \
		"led.h: объявлена функция led_pin" \
		"led.h: нет объявления led_pin"

	if grep -Eq 'LED_PIN' "$HEADER"; then
		fail "led.h: номер вывода вынесен из модуля наружу"
		note "Наружу выдаётся функция led_pin, а константа остаётся внутри led.c."
	else
		ok "led.h: номер вывода остался внутри модуля"
	fi
fi

BODY="$SRC/led/led.c"
if [ -f "$BODY" ]; then
	BODY="$(normalize "$BODY")"
	match "$BODY" 'led_pin[[:space:]]*\([[:space:]]*void[[:space:]]*\)' \
		"led.c: функция led_pin написана" \
		"led.c: нет функции led_pin"
fi

MAIN="$SRC/main.c"
if [ -f "$MAIN" ]; then
	MAIN="$(normalize "$MAIN")"
	match "$MAIN" '"boot_info"' \
		"main.c: команда boot_info есть в таблице команд" \
		"main.c: в таблице команд нет boot_info"
fi

# Вершину стека спрашиваем у собранного образа: первое слово таблицы векторов
# обязано совпасть с символом линкера __StackTop.
STACK_TOP=""
BUILD_KEEP=1
if build_project "$SRC" && [ -n "${BUILD_ELF:-}" ]; then
	SYMBOLS="$(mktemp)"
	if arm-none-eabi-objdump -t "$BUILD_ELF" > "$SYMBOLS" 2>/dev/null; then
		STACK_TOP="$(awk '$NF == "__StackTop" {print "0x" $1; exit}' "$SYMBOLS")"
	else
		warn "Не удалось прочитать таблицу символов: нет arm-none-eabi-objdump"
	fi
	rm -f "$SYMBOLS"
fi
[ -n "${BUILD_DIR:-}" ] && rm -rf "$BUILD_DIR"

if device_log "$SRC/device-2-1-6.log" "2.1.6"; then
	RECEIVED="$(device_received "$DEVICE_LOG")"

	# boot_info печатает подписи в два слова, поэтому значения достаются по имени строки.
	field() { echo "$RECEIVED" | sed -n "s/^ *$1  *\([0-9][0-9a-fx]*\) *$/\1/p"; }

	CALLS="$(device_sent "$DEVICE_LOG" | grep -cx 'boot_info')"
	if [ "$CALLS" -ge 3 ]; then
		ok "Команда boot_info вызвана $CALLS раза: как есть, после enable и после disable"
	elif [ "$CALLS" -ge 2 ]; then
		warn "В логе только $CALLS вызова boot_info, задание просит три"
	else
		fail "В логе меньше двух вызовов boot_info"
		note "Разряд регистра меняется только вместе с состоянием светодиода: нужны вызовы до и после enable."
	fi

	for cmd in enable disable; do
		if device_sent "$DEVICE_LOG" | grep -qx "$cmd"; then
			ok "Скрипт переключил светодиод командой $cmd"
		else
			fail "В логе нет отправленной команды $cmd"
		fi
	done

	if echo "$RECEIVED" | grep -Eq '^vector table[[:space:]]+0x10000100'; then
		ok "Плата назвала адрес таблицы векторов 0x10000100"
	else
		fail "В ответе платы нет строки с адресом таблицы векторов 0x10000100"
	fi

	LOG_STACK="$(field 'stack top' | head -1)"
	if echo "$LOG_STACK" | grep -Eq '^0x2[0-9a-f]{7}$'; then
		ok "Первое слово таблицы векторов — адрес в ОЗУ: это начальное значение указателя стека"
	else
		fail "По первому слову таблицы векторов плата вернула «${LOG_STACK:-нет}», а не адрес в ОЗУ"
	fi

	if [ -n "$STACK_TOP" ] && [ -n "$LOG_STACK" ]; then
		if [ "$((LOG_STACK))" -eq "$((STACK_TOP))" ]; then
			ok "Вершина стека из образа совпала с прочитанной по адресу: $STACK_TOP"
		else
			fail "В логе вершина стека $LOG_STACK, а символ линкера __StackTop даёт $STACK_TOP"
			note "Прошивка прочитала собственное начало: числа обязаны совпасть."
		fi
	fi

	RESET="$(field 'reset' | head -1)"
	EVEN="$(field 'reset (even)' | head -1)"
	if echo "$RESET" | grep -Eq '^0x1[0-9a-f]{7}$'; then
		ok "Второе слово таблицы векторов — адрес во флеш-памяти: обработчик сброса"
	else
		fail "По второму слову таблицы векторов плата вернула «${RESET:-нет}», а не адрес во флеш-памяти"
	fi

	if [ -n "$RESET" ] && [ $(($RESET & 1)) -eq 1 ]; then
		ok "У адреса обработчика сброса стоит признак Thumb: адрес нечётный"
	else
		fail "Адрес обработчика сброса «${RESET:-нет}» чётный — признака Thumb в нём нет"
	fi

	if [ -n "$RESET" ] && [ -n "$EVEN" ] && [ "$((EVEN))" -eq "$((RESET & ~1))" ]; then
		ok "Рядом напечатан тот же адрес со сброшенным младшим разрядом"
	else
		fail "Адрес со сброшенным признаком Thumb «${EVEN:-нет}» не выводится из «${RESET:-нет}»"
	fi

	if [ -n "$EVEN" ] && [ "$((EVEN))" -gt "$((0x10000100))" ]; then
		ok "Обработчик сброса лежит во флеш-памяти сразу за таблицей векторов"
	else
		fail "Адрес обработчика сброса не попал во флеш-память за таблицу векторов"
	fi

	if echo "$RECEIVED" | grep -Eq '^gpio in[[:space:]]+0xd0000004'; then
		ok "Плата назвала адрес регистра GPIO_IN 0xd0000004"
	else
		fail "В ответе платы нет строки с адресом регистра 0xd0000004"
	fi

	BITS="$(field 'led bit')"
	GETS="$(field 'gpio_get')"
	BIT_STATES="$(echo "$BITS" | sort -u | grep -c .)"
	if [ "$BIT_STATES" -ge 2 ]; then
		ok "Разряд регистра принимает оба значения: он менялся вместе со светодиодом"
	else
		fail "Разряд регистра во всех вызовах одинаковый"
		note "Без volatile компилятор читает регистр один раз; проверьте и то, что boot_info вызвана после enable."
	fi

	if [ -n "$BITS" ] && [ "$BITS" = "$GETS" ]; then
		ok "Разряд регистра совпал с gpio_get во всех вызовах"
	else
		fail "Разряд регистра и gpio_get разошлись"
		note "gpio_get внутри читает тот же регистр: значения обязаны совпасть."
	fi
fi

finish "$TITLE"
