#!/usr/bin/env bash
# Задание п2.1.3 «Системная память».
# Модуль memory, символы линкера через extern и &, команда mem_info и её таблица.
# Использование: check-2-1-3.sh <путь к репозиторию> [папка проекта]
set -u

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
. "$LIB/report.sh"
. "$LIB/build.sh"
. "$LIB/cmake.sh"
. "$LIB/device.sh"

TITLE="Задание 2.1.3 — Системная память"
REPO="${1:-.}"
PROJECT="${2:-211-command-usb}"
SRC="$REPO/$PROJECT"

FLASH_START=$((0x10000000))
FLASH_END=$((0x10200000))
RAM_START=$((0x20000000))
RAM_END=$((0x20042000))

if [ ! -d "$SRC" ]; then
	fail "В репозитории нет папки проекта $PROJECT"
	finish "$TITLE"
	exit 1
fi
ok "Папка проекта $PROJECT найдена"

for f in memory/memory.h memory/memory.c check-2-1-3.py device-2-1-3.log; do
	if [ -f "$SRC/$f" ]; then
		ok "Файл $f на месте"
	else
		fail "В проекте нет файла $f"
	fi
done

BODY="$SRC/memory/memory.c"
if [ -f "$BODY" ]; then
	BODY="$(normalize "$BODY")"

	MISSING=""
	for sym in __flash_binary_end __boot2_end__ __etext __data_start__ __data_end__ \
		__bss_start__ __bss_end__ __HeapLimit __StackTop; do
		grep -Eq "extern[[:space:]]+char[[:space:]]+$sym" "$BODY" || MISSING="$MISSING \`$sym\`"
	done
	if [ -z "$MISSING" ]; then
		ok "memory.c: символы линкера объявлены через extern char"
	else
		fail "memory.c: не объявлены символами линкера:$MISSING"
		note "Символ объявляют как extern char и берут у него адрес — значения у него нет."
	fi

	if grep -Eq '&__(etext|data_start__|bss_start__|bss_end__|StackTop|StackBottom|HeapLimit|flash_binary_start|flash_binary_end|boot2_end__)' "$BODY"; then
		ok "memory.c: адрес символа берётся оператором &"
	else
		fail "memory.c: символы читаются как переменные, а не берутся через &"
		note "Без & вы прочитаете байт, лежащий ПО этому адресу, — то есть чужие данные."
	fi

	match "$BODY" 'mem_info[[:space:]]*\(' \
		"memory.c: написана функция mem_info" \
		"memory.c: нет функции mem_info"
	match "$BODY" 'XIP_BASE|0x10000000' \
		"memory.c: назван базовый адрес флеш-памяти" \
		"memory.c: не видно базового адреса флеш-памяти"
	match "$BODY" 'SRAM_BASE|0x20000000' \
		"memory.c: назван базовый адрес ОЗУ" \
		"memory.c: не видно базового адреса ОЗУ"
	match "$BODY" 'PICO_FLASH_SIZE_BYTES' \
		"memory.c: размер флеш-памяти взят из PICO_FLASH_SIZE_BYTES" \
		"memory.c: размер флеш-памяти вписан числом вместо PICO_FLASH_SIZE_BYTES"
fi

HEADER="$SRC/memory/memory.h"
if [ -f "$HEADER" ]; then
	HEADER="$(normalize "$HEADER")"
	match "$HEADER" 'void[[:space:]]+mem_info[[:space:]]*\(' \
		"memory.h: mem_info объявлена в заголовочном файле" \
		"memory.h: нет объявления mem_info"
fi

MAIN="$SRC/main.c"
if [ -f "$MAIN" ]; then
	MAIN="$(normalize "$MAIN")"
	match "$MAIN" '#include[[:space:]]*"memory\.h"' \
		"main.c: подключён заголовочный файл модуля памяти" \
		"main.c: нет #include \"memory.h\""
	match "$MAIN" '"mem_info"' \
		"main.c: команда mem_info есть в таблице команд" \
		"main.c: в таблице команд нет mem_info"
fi

CMAKE="$SRC/CMakeLists.txt"
if [ -f "$CMAKE" ]; then
	FLAT="$(cmake_flatten "$CMAKE")"
	if grep -Eo 'add_executable[[:space:]]*\([^)]*' "$FLAT" | grep -q 'memory\.c'; then
		ok "CMakeLists.txt: memory.c добавлен в список исходных файлов"
	else
		fail "CMakeLists.txt: memory.c не добавлен в add_executable"
	fi
	if grep -Eo 'target_include_directories[[:space:]]*\([^)]*' "$FLAT" | grep -q 'memory'; then
		ok "CMakeLists.txt: папка memory добавлена в пути поиска заголовочных файлов"
	else
		fail "CMakeLists.txt: папки memory нет в target_include_directories"
	fi
fi

# Строка таблицы: имя области (может быть из двух слов), два адреса и размер.
# area_field <имя> <start|end|size> — печатает поле или пустую строку.
area_field() {
	echo "$RECEIVED" | awk -v want="$1" -v field="$2" '
		NF >= 4 && $(NF-2) ~ /^0x[0-9a-fA-F]+$/ && $(NF-1) ~ /^0x[0-9a-fA-F]+$/ && $NF ~ /^[0-9]+$/ {
			name = ""
			for (i = 1; i <= NF - 3; i++) name = (i == 1 ? $i : name " " $i)
			if (name != want) next
			if (field == "start") print $(NF-2)
			else if (field == "end") print $(NF-1)
			else print $NF
			exit
		}'
}

# Число из строки итога: total_value <первое слово> <второе слово>
total_value() {
	echo "$RECEIVED" | awk -v a="$1" -v b="$2" '$1 == a && $2 == b {print $3; exit}'
}

dec() { [ -n "$1" ] && printf '%d' "$(($1))" || echo ""; }

if device_log "$SRC/device-2-1-3.log" "2.1.3"; then
	RECEIVED="$(device_received "$DEVICE_LOG")"

	if device_sent "$DEVICE_LOG" | grep -qx 'mem_info'; then
		ok "Скрипт отправил команду mem_info"
	else
		fail "В логе нет отправленной команды mem_info"
	fi

	MISSING=""
	for area in flash sram rom image free boot2 text "data flash" "data ram" bss heap stack; do
		[ -n "$(area_field "$area" start)" ] || MISSING="$MISSING «${area}»"
	done
	if [ -z "$MISSING" ]; then
		ok "Плата перечислила все двенадцать областей с началом, концом и размером"
	else
		fail "В ответе платы нет строк по областям:$MISSING"
		note "Каждая строка — имя области, начало, конец и размер, как в примере задания."
	fi

	OUT_OF_RANGE=""
	for area in image free boot2 text "data flash"; do
		V="$(dec "$(area_field "$area" start)")"
		[ -n "$V" ] && { [ "$V" -ge "$FLASH_START" ] && [ "$V" -le "$FLASH_END" ]; } || OUT_OF_RANGE="$OUT_OF_RANGE «${area}»"
	done
	if [ -z "$OUT_OF_RANGE" ]; then
		ok "Области образа лежат во флеш-памяти"
	else
		fail "За пределами флеш-памяти оказались области:$OUT_OF_RANGE"
	fi

	OUT_OF_RANGE=""
	for area in "data ram" bss heap stack; do
		V="$(dec "$(area_field "$area" start)")"
		[ -n "$V" ] && { [ "$V" -ge "$RAM_START" ] && [ "$V" -le "$RAM_END" ]; } || OUT_OF_RANGE="$OUT_OF_RANGE «${area}»"
	done
	if [ -z "$OUT_OF_RANGE" ]; then
		ok "Области времени работы лежат в ОЗУ"
	else
		fail "За пределами ОЗУ оказались области:$OUT_OF_RANGE"
	fi

	BOOT2_SIZE="$(dec "$(area_field boot2 size)")"
	if [ "${BOOT2_SIZE:-0}" = "256" ]; then
		ok "Загрузчик второй стадии занимает ровно 256 байт"
	else
		fail "Размер загрузчика второй стадии — «${BOOT2_SIZE:-нет}», а он занимает ровно 256 байт"
	fi

	STACK_SIZE="$(dec "$(area_field stack size)")"
	STACK_TOP="$(dec "$(area_field stack end)")"
	if [ "${STACK_SIZE:-0}" = "2048" ] && [ "${STACK_TOP:-0}" = "$RAM_END" ]; then
		ok "Под стек отведено 2048 байт, его вершина — конец банка SCRATCH_Y"
	else
		fail "Стек в ответе платы — «${STACK_SIZE:-нет}» байт с вершиной «$(area_field stack end)»"
		note "Линкер-скрипт отводит стеку ядра 0 ровно 2 КБ, вершина совпадает с концом ОЗУ, 0x20042000."
	fi

	HEAP_END="$(dec "$(area_field heap end)")"
	if [ "${HEAP_END:-0}" = "$((0x20040000))" ]; then
		ok "Потолок кучи — конец региона RAM, 0x20040000"
	else
		fail "Конец кучи — «$(area_field heap end)», а регион RAM кончается на 0x20040000"
	fi

	DATA_FLASH_SIZE="$(dec "$(area_field "data flash" size)")"
	DATA_RAM_SIZE="$(dec "$(area_field "data ram" size)")"
	if [ -n "$DATA_FLASH_SIZE" ] && [ "$DATA_FLASH_SIZE" = "$DATA_RAM_SIZE" ]; then
		ok "У .data два адреса и один размер: $DATA_RAM_SIZE байт во флеш и столько же в ОЗУ"
	else
		fail "Размеры .data во флеш и в ОЗУ разошлись: «${DATA_FLASH_SIZE}» и «${DATA_RAM_SIZE}»"
		note "Стартап-код копирует секцию байт в байт: сколько её хранится, столько и работает."
	fi

	# Области идут встык: в этом смысл таблицы, и это не зависит ни от версии
	# компилятора, ни от размера программы.
	GAPS=""
	check_joint() {
		local left="$1" right="$2" a b
		a="$(dec "$(area_field "$left" end)")"
		b="$(dec "$(area_field "$right" start)")"
		[ -n "$a" ] && [ -n "$b" ] && [ "$a" = "$b" ] || GAPS="$GAPS «$left → ${right}»"
	}
	check_joint boot2 text
	check_joint text "data flash"
	check_joint "data flash" free
	check_joint "data ram" bss
	check_joint bss heap
	if [ -z "$GAPS" ]; then
		ok "Области стыкуются без пропусков: код за загрузчиком, .bss за .data, куча за .bss"
	else
		fail "Между областями есть разрыв:$GAPS"
	fi

	IMAGE_SIZE="$(dec "$(area_field image size)")"
	TEXT_SIZE="$(dec "$(area_field text size)")"
	if [ -n "$IMAGE_SIZE" ] && [ "$IMAGE_SIZE" = "$((BOOT2_SIZE + TEXT_SIZE + DATA_FLASH_SIZE))" ]; then
		ok "Образ сложился из загрузчика, кода с константами и .data: $IMAGE_SIZE байт"
	else
		fail "Размер образа «${IMAGE_SIZE}» не равен сумме boot2, text и data flash"
	fi

	if echo "$RECEIVED" | grep -Eq '^total[[:space:]]*$'; then
		ok "За таблицей идёт итог"
	else
		fail "В ответе платы нет итога — строки total за таблицей"
	fi

	MISMATCH=""
	T_IMAGE="$(total_value flash image)"
	T_FREE="$(total_value flash free)"
	T_USED="$(total_value ram used)"
	T_RAM_FREE="$(total_value ram free)"
	BSS_SIZE="$(dec "$(area_field bss size)")"
	HEAP_SIZE="$(dec "$(area_field heap size)")"
	FREE_SIZE="$(dec "$(area_field free size)")"

	[ "$T_IMAGE" = "$IMAGE_SIZE" ] || MISMATCH="$MISMATCH «flash image»"
	[ "$T_FREE" = "$FREE_SIZE" ] || MISMATCH="$MISMATCH «flash free»"
	[ -n "$T_USED" ] && [ "$T_USED" = "$((DATA_RAM_SIZE + BSS_SIZE))" ] || MISMATCH="$MISMATCH «ram used»"
	[ "$T_RAM_FREE" = "$HEAP_SIZE" ] || MISMATCH="$MISMATCH «ram free»"

	if [ -z "$MISMATCH" ]; then
		ok "Числа в итоге сошлись с таблицей: образ, свободная флеш-память, занятое и свободное ОЗУ"
	else
		fail "Итог расходится с таблицей в строках:$MISMATCH"
		note "Итог складывается из тех же размеров: свободное ОЗУ — это куча и стек из таблицы, а не остаток от 264 КБ."
	fi
fi

# Сверка с собственной сборкой. Версия компилятора на сервере и у вас различается,
# поэтому расхождение адресов — повод посмотреть, а не ошибка задания.
BUILD_KEEP=1
if build_project "$SRC" && [ -n "${BUILD_ELF:-}" ] && [ -n "${DEVICE_LOG:-}" ]; then
	SYMBOLS="$(mktemp)"
	if arm-none-eabi-objdump -t "$BUILD_ELF" > "$SYMBOLS" 2>/dev/null; then
		symbol_addr() { awk -v n="$1" '$NF == n {print "0x" $1; exit}' "$SYMBOLS"; }

		DIFF=""
		compare() {
			local area="$1" field="$2" sym="$3" from_log from_elf
			from_log="$(dec "$(area_field "$area" "$field")")"
			from_elf="$(dec "$(symbol_addr "$sym")")"
			[ -n "$from_log" ] && [ -n "$from_elf" ] && [ "$from_log" = "$from_elf" ] || DIFF="$DIFF \`$sym\`"
		}
		compare image start __flash_binary_start
		compare image end __flash_binary_end
		compare text end __etext
		compare "data ram" start __data_start__
		compare bss end __bss_end__
		compare stack start __StackBottom

		if [ -z "$DIFF" ]; then
			ok "Границы областей совпали с собранным здесь образом"
		else
			warn "Границы в логе разошлись со сборкой на сервере: $DIFF"
			note "Так бывает, когда лог снят до последней правки кода или другой версией компилятора."
		fi
	else
		warn "Не удалось прочитать таблицу символов: нет arm-none-eabi-objdump"
	fi
	rm -f "$SYMBOLS"

	BIN="$(ls "$BUILD_DIR"/*.bin 2>/dev/null | head -1)"
	if [ -n "$BIN" ] && [ -n "${T_IMAGE:-}" ]; then
		BIN_SIZE="$(wc -c < "$BIN" | tr -d ' ')"
		if [ "$BIN_SIZE" = "$T_IMAGE" ]; then
			ok "Итог сошёлся с размером файла прошивки: $BIN_SIZE байт"
		else
			warn "Образ в итоге — $T_IMAGE байт, а собранный здесь .bin — $BIN_SIZE байт"
			note "Сумма считается до последнего байта; разойтись она может из-за другой версии компилятора."
		fi
	fi
fi
[ -n "${BUILD_DIR:-}" ] && rm -rf "$BUILD_DIR"

finish "$TITLE"
