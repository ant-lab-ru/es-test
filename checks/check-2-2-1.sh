#!/usr/bin/env bash
# Задание п2.2.1 «Тактовые частоты».
# Проект 221-command-time, модуль clock, настроенные и измеренные частоты тактовых сигналов.
# Использование: check-2-2-1.sh <путь к репозиторию> [папка проекта]
set -u

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
. "$LIB/report.sh"
. "$LIB/build.sh"
. "$LIB/cmake.sh"
. "$LIB/device.sh"
. "$LIB/exchange.sh"

TITLE="Задание 2.2.1 — Тактовые частоты"
REPO="${1:-.}"
PROJECT="${2:-221-command-time}"
SRC="$REPO/$PROJECT"

if [ ! -d "$SRC" ]; then
	fail "В репозитории нет папки проекта $PROJECT"
	note "Проект занятия заводится копированием 211-command-usb под новым именем."
	finish "$TITLE"
	exit 1
fi
ok "Папка проекта $PROJECT найдена"

for f in main.c clock/clock.c clock/clock.h device/device.h check-2-2-1.py device-2-2-1.log; do
	if [ -f "$SRC/$f" ]; then
		ok "Файл $f на месте"
	else
		fail "В проекте нет файла $f"
	fi
done

LEFT="$(cd "$SRC" && ls check-2-1-*.py device-2-1-*.log 2>/dev/null | tr '\n' ' ')"
if [ -z "$LEFT" ]; then
	ok "Скрипты и логи занятия 2.1 в новый проект не перенесены"
else
	warn "В проекте остались файлы занятия 2.1: $LEFT"
	note "Они относятся к 211-command-usb. В копии их удаляют вместе с папкой build."
fi

check_project_name "$SRC" "$PROJECT"

CMAKE="$SRC/CMakeLists.txt"
if [ -f "$CMAKE" ]; then
	FLAT="$(cmake_flatten "$CMAKE")"
	match "$FLAT" 'add_executable[[:space:]]*\([^)]*clock/clock\.c' \
		"CMakeLists.txt: clock/clock.c добавлен в сборку" \
		"CMakeLists.txt: clock/clock.c не добавлен в add_executable"
	match "$FLAT" 'target_include_directories[[:space:]]*\([^)]*/clock([[:space:]]|\))' \
		"CMakeLists.txt: папка clock есть в путях заголовков" \
		"CMakeLists.txt: папки clock нет в target_include_directories"
fi

HEADER="$SRC/device/device.h"
if [ -f "$HEADER" ]; then
	HEADER="$(normalize "$HEADER")"
	match "$HEADER" 'DEVICE_PROJECT[[:space:]]+"221-command-time"' \
		"device.h: имя проекта в паспорте — 221-command-time" \
		"device.h: в DEVICE_PROJECT осталось имя проекта прошлого занятия"
	if grep -Eq 'FIRMWARE_VERSION[[:space:]]+"1\.0\.0"' "$HEADER"; then
		warn "device.h: версия прошивки осталась 1.0.0"
		note "У прибора появятся новые команды, поэтому задание просит поднять версию до 1.1.0."
	else
		ok "device.h: версия прошивки поднята"
	fi
fi

BODY="$SRC/clock/clock.c"
if [ -f "$BODY" ]; then
	BODY="$(normalize "$BODY")"
	match "$BODY" '#include[[:space:]]*"hardware/clocks\.h"' \
		"clock.c: подключён hardware/clocks.h" \
		"clock.c: нет #include \"hardware/clocks.h\" — в нём функции тактовых сигналов"
	match "$BODY" 'clk_info[[:space:]]*\(' \
		"clock.c: написана функция clk_info" \
		"clock.c: нет функции clk_info"
	match "$BODY" 'clock_get_hz[[:space:]]*\(' \
		"clock.c: настроенные частоты берутся функцией clock_get_hz" \
		"clock.c: нет вызова clock_get_hz"
	match "$BODY" 'frequency_count_khz[[:space:]]*\(' \
		"clock.c: частоты измеряются функцией frequency_count_khz" \
		"clock.c: нет вызова frequency_count_khz"

	MISSING=""
	for signal in REF SYS PERI USB ADC; do
		grep -Eq "CLOCKS_FC0_SRC_VALUE_CLK_$signal" "$BODY" || MISSING="$MISSING clk_$(echo "$signal" | tr 'A-Z' 'a-z')"
	done
	if [ -z "$MISSING" ]; then
		ok "clock.c: для всех пяти сигналов взяты константы SDK из FC0_SRC"
	else
		fail "clock.c: нет константы измеряемого источника для:$MISSING"
		note "Коды источников — в описании регистра FC0_SRC, константы с теми же значениями — в hardware/regs/clocks.h."
	fi

	if grep -Eq 'CLOCKS_FC0_SRC_VALUE_ROSC_CLKSRC([^_]|$)' "$BODY"; then
		ok "clock.c: частота ROSC измеряется по коду CLOCKS_FC0_SRC_VALUE_ROSC_CLKSRC"
	else
		fail "clock.c: не видно измерения ROSC константой CLOCKS_FC0_SRC_VALUE_ROSC_CLKSRC"
	fi
fi

HEADER="$SRC/clock/clock.h"
if [ -f "$HEADER" ]; then
	HEADER="$(normalize "$HEADER")"
	match "$HEADER" 'clk_info[[:space:]]*\([[:space:]]*void[[:space:]]*\)' \
		"clock.h: объявлена функция clk_info" \
		"clock.h: нет объявления clk_info"
fi

MAIN="$SRC/main.c"
if [ -f "$MAIN" ]; then
	MAIN="$(normalize "$MAIN")"
	match "$MAIN" '#include[[:space:]]*"clock\.h"' \
		"main.c: подключён заголовок модуля часов" \
		"main.c: нет #include \"clock.h\""
	match "$MAIN" '"clk_info"' \
		"main.c: команда clk_info есть в таблице команд" \
		"main.c: в таблице команд нет clk_info"
fi

build_project "$SRC"

if device_log "$SRC/device-2-2-1.log" "2.2.1"; then
	RECEIVED="$(device_received "$DEVICE_LOG")"

	if [ "$(exchange_calls "$DEVICE_LOG" clk_info)" -ge 1 ]; then
		ok "Скрипт отправил команду clk_info"
	else
		fail "В логе нет отправленной команды clk_info"
	fi

	# Строка таблицы: имя сигнала, настроенная и измеренная частоты в килогерцах.
	# Столбцы отделяют пробелы или табуляция — годится любое.
	row() { echo "$RECEIVED" | awk -v name="$1" '$1 == name && $2 ~ /^[0-9]+$/ && $3 ~ /^[0-9]+$/ { print $2, $3; exit }'; }

	for pair in clk_ref:12000 clk_sys:125000 clk_peri:125000 clk_usb:48000 clk_adc:48000; do
		name="${pair%%:*}"
		want="${pair##*:}"
		ROW="$(row "$name")"
		if [ -z "$ROW" ]; then
			fail "В ответе платы нет строки $name с двумя частотами"
			note "Строка таблицы — имя сигнала, настроенная частота и измеренная, обе в килогерцах."
			continue
		fi
		SET="${ROW%% *}"
		MEASURED="${ROW##* }"
		# После смены частоты ядра в п2.2.5 SDK переводит clk_peri на PLL для USB, и до
		# перезагрузки платы он остаётся на 48 МГц. Лог, переснятый после п2.2.5, это покажет.
		if [ "$name" = "clk_peri" ] && [ "$SET" -eq 48000 ]; then
			want=48000
			ok "$name: настроенная частота 48000 кГц — на плате уже меняли частоту ядра, как в п2.2.5"
		elif [ "$SET" -eq "$want" ]; then
			ok "$name: настроенная частота $SET кГц"
		elif [ "$SET" -eq "$((want * 1000))" ]; then
			fail "$name: настроенная частота $SET — это герцы, а таблица в килогерцах"
			note "clock_get_hz() возвращает герцы: разделите значение на 1000."
		else
			fail "$name: настроенная частота $SET кГц, ожидалось $want"
		fi
		DIFF=$((MEASURED > want ? MEASURED - want : want - MEASURED))
		if [ "$((DIFF * 100))" -le "$want" ]; then
			ok "$name: измеренная частота $MEASURED кГц сходится с настроенной"
		else
			fail "$name: измеренная частота $MEASURED кГц расходится с ожидаемой $want больше чем на 1 %"
			note "Проверьте код источника в frequency_count_khz(): он выбирает, какой сигнал считать."
		fi
	done

	ROSC="$(echo "$RECEIVED" | awk '$1 == "rosc" && $NF ~ /^[0-9]+$/ { print $NF; exit }')"
	if [ -z "$ROSC" ]; then
		fail "В ответе платы нет строки rosc с измеренной частотой"
	elif [ "$ROSC" -ge 1800 ] && [ "$ROSC" -le 12000 ]; then
		ok "Частота ROSC $ROSC кГц лежит в допустимом диапазоне 1,8–12 МГц"
	else
		fail "Частота ROSC $ROSC кГц вне диапазона 1,8–12 МГц"
		note "Диапазон гарантирует RP2040 Datasheet. Ноль значит, что измерен не тот источник."
	fi

	if echo "$RECEIVED" | grep -Eq '^project:[[:space:]]*221-command-time'; then
		ok "Паспорт называет проект 221-command-time: на плате прошивка нового проекта"
	else
		fail "В логе нет строки project: 221-command-time"
		note "Скрипт спрашивает паспорт командой info. Проверьте DEVICE_PROJECT и то, что на плату записана свежая прошивка."
	fi
fi

finish "$TITLE"
