#!/usr/bin/env bash
# Задание п2.1.4 «Память программы».
# Адреса кода, таблицы команд, констант, стека и кучи; сброс признака Thumb; malloc с проверкой.
# Использование: check-2-1-4.sh <путь к репозиторию> [папка проекта]
set -u

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
. "$LIB/report.sh"
. "$LIB/build.sh"
. "$LIB/cmake.sh"
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

for f in memory/memory.c command.h check-2-1-4.py device-2-1-4.log; do
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
	match "$BODY" '#include[[:space:]]*<stdlib\.h>' \
		"memory.c: подключён <stdlib.h> — в нём объявлены malloc и free" \
		"memory.c: нет #include <stdlib.h>, без него malloc не объявлен"
	match "$BODY" 'malloc[[:space:]]*\(' \
		"memory.c: блок памяти берётся в куче вызовом malloc" \
		"memory.c: нет вызова malloc"

	if grep -Eq 'NULL' "$BODY"; then
		ok "memory.c: результат malloc проверяется на NULL"
	else
		fail "memory.c: результат malloc не проверяется на NULL"
		note "malloc возвращает нулевой указатель, когда места нет; запись по нему роняет прошивку."
	fi

	# Закомментированный вызов — не вызов: строка не должна начинаться с //
	if grep -Eq '^[^/]*free[[:space:]]*\([[:space:]]*heap' "$BODY"; then
		ok "memory.c: блок возвращается в кучу вызовом free"
	else
		fail "memory.c: нет парного free — взятый блок не возвращён"
		note "Лог снимается с возвращённым блоком: без free адреса в куче поползут, и опыт шага 6 потеряет смысл."
	fi

	match "$BODY" 'int[[:space:]]+main[[:space:]]*\(' \
		"memory.c: main объявлена, чтобы взять её адрес" \
		"memory.c: нет объявления main — взять её адрес из другого файла не получится"

	match "$BODY" 'uint32_t[[:space:]]+data_variable[[:space:]]*=[[:space:]]*[1-9]' \
		"memory.c: data_variable заведена с ненулевым начальным значением" \
		"memory.c: нет data_variable с ненулевым начальным значением"
	if grep -Eq 'uint32_t[[:space:]]+bss_variable[[:space:]]*;' "$BODY"; then
		ok "memory.c: bss_variable заведена без начального значения"
	else
		fail "memory.c: нет bss_variable без начального значения"
		note "Начальное значение отправило бы её в .data, и разницы между секциями не увидеть."
	fi

	if grep -Eq 'commands\[[A-Za-z_]' "$BODY" && grep -Eq 'command_count' "$BODY"; then
		ok "memory.c: таблица команд обходится по command_count"
	else
		fail "memory.c: нет обхода массива commands по command_count"
	fi
fi

HEADER="$SRC/command.h"
if [ -f "$HEADER" ]; then
	HEADER="$(normalize "$HEADER")"
	FLAT="$(mktemp)"
	tr '\n' ' ' < "$HEADER" > "$FLAT"

	match "$HEADER" 'typedef[[:space:]]+void[[:space:]]*\([[:space:]]*\*[[:space:]]*command_handler_t' \
		"command.h: тип обработчика перенесён в заголовок" \
		"command.h: нет typedef command_handler_t"
	match "$FLAT" 'struct[[:space:]]+command_t[[:space:]]*\{' \
		"command.h: тип команды перенесён в заголовок" \
		"command.h: нет объявления struct command_t"
	match "$HEADER" 'extern[[:space:]]+const[[:space:]]+struct[[:space:]]+command_t[[:space:]]+commands[[:space:]]*\[' \
		"command.h: таблица объявлена внешней" \
		"command.h: нет объявления extern для массива commands"

	if grep -Eq 'extern[[:space:]]+const[[:space:]]+uint[[:space:]]+command_count' "$HEADER"; then
		ok "command.h: длина таблицы объявлена внешней"
	elif grep -Eq 'const[[:space:]]+uint[[:space:]]+command_count' "$HEADER"; then
		fail "command.h: у command_count нет extern — это определение, а не объявление"
		note "Без extern переменная заводится в каждом включившем файле, и компоновщик остановится на multiple definition."
	else
		fail "command.h: нет объявления command_count"
	fi

	rm -f "$FLAT"
fi

MAIN="$SRC/main.c"
if [ -f "$MAIN" ]; then
	MAIN="$(normalize "$MAIN")"
	match "$MAIN" '#include[[:space:]]*"command\.h"' \
		"main.c: подключён command.h" \
		"main.c: нет #include \"command.h\""
	match "$MAIN" 'const[[:space:]]+uint[[:space:]]+command_count[[:space:]]*=[[:space:]]*sizeof' \
		"main.c: длина таблицы посчитана из самого массива" \
		"main.c: нет определения command_count через sizeof"

	if grep -Eq 'COMMAND_COUNT' "$MAIN"; then
		fail "main.c: остался макрос COMMAND_COUNT"
		note "Из другого файла макрос не виден — в этом задании его место занимает переменная command_count."
	else
		ok "main.c: макрос COMMAND_COUNT заменён переменной"
	fi

	match "$MAIN" '"fw_info"' \
		"main.c: команда fw_info есть в таблице команд" \
		"main.c: в таблице команд нет fw_info"
fi

CMAKE="$SRC/CMakeLists.txt"
if [ -f "$CMAKE" ]; then
	FLAT="$(cmake_flatten "$CMAKE")"
	if grep -Eo 'target_include_directories[[:space:]]*\([^)]*' "$FLAT" |
		grep -Eq 'CMAKE_CURRENT_SOURCE_DIR\}[[:space:]]'; then
		ok "CMakeLists.txt: папка проекта добавлена в пути поиска заголовков"
	else
		fail "CMakeLists.txt: папки проекта нет в target_include_directories"
		note "Без неё memory/memory.c не найдёт command.h: он лежит рядом с main.c, а не в папке модуля."
	fi
fi

# obj_field <имя объекта> <2|3> — колонка адреса или значения, все вхождения
obj_field() {
	echo "$RECEIVED" | awk -v n="$1" -v c="$2" '$1 == n && $2 ~ /^0x[0-9a-fA-F]+$/ {print $c}'
}

if device_log "$SRC/device-2-1-4.log" "2.1.4"; then
	RECEIVED="$(device_received "$DEVICE_LOG")"

	CALLS="$(device_sent "$DEVICE_LOG" | grep -cx 'fw_info')"
	if [ "$CALLS" -ge 3 ]; then
		ok "Команда fw_info вызвана $CALLS раза подряд"
	elif [ "$CALLS" -ge 2 ]; then
		warn "В логе только $CALLS вызова fw_info, задание просит три"
	else
		fail "В логе меньше двух вызовов fw_info"
		note "Повторные вызовы нужны, чтобы увидеть, как ведут себя адреса стека и кучи."
	fi

	MISSING=""
	for obj in main fw_info commands DEVICE_PROJECT DEVICE_BOARD \
		data_variable bss_variable stack_variable heap_variable; do
		echo "$RECEIVED" | grep -Eq "^${obj}[[:space:]]+0x[0-9a-f]{8}" || MISSING="$MISSING ${obj}"
	done
	if [ -z "$MISSING" ]; then
		ok "Плата напечатала адреса всех девяти объектов"
	else
		fail "В ответе платы нет адресов:$MISSING"
	fi

	in_range() { # in_range <адрес> <начало> <конец>
		local v="$(($1))"
		[ "$v" -ge "$(($2))" ] && [ "$v" -lt "$(($3))" ]
	}

	WRONG=""
	for obj in main fw_info commands DEVICE_PROJECT DEVICE_BOARD; do
		A="$(obj_field "$obj" 2 | head -1)"
		[ -n "$A" ] && in_range "$A" 0x10000000 0x10200000 || WRONG="$WRONG ${obj}"
	done
	if [ -z "$WRONG" ]; then
		ok "Код, таблица команд и константы лежат во флеш-памяти"
	else
		fail "Не во флеш-памяти оказались:$WRONG"
	fi

	WRONG=""
	for obj in data_variable bss_variable heap_variable; do
		A="$(obj_field "$obj" 2 | head -1)"
		[ -n "$A" ] && in_range "$A" 0x20000000 0x20040000 || WRONG="$WRONG ${obj}"
	done
	if [ -z "$WRONG" ]; then
		ok "Переменные в ОЗУ и блок в куче лежат в регионе RAM"
	else
		fail "За пределами региона RAM оказались:$WRONG"
		note "Блок кучи печатается своим адресом: heap_variable, а не &heap_variable."
	fi

	A="$(obj_field stack_variable 2 | head -1)"
	if [ -n "$A" ] && in_range "$A" 0x20041000 0x20042000; then
		ok "Локальная переменная лежит на стеке, в банке SCRATCH_Y"
	else
		fail "Адрес локальной переменной «${A:-нет}» не попал в банк стека 0x20041000…0x20042000"
	fi

	ODD=""
	for obj in main fw_info; do
		A="$(obj_field "$obj" 2 | head -1)"
		[ -n "$A" ] && [ $(( $A & 1 )) -eq 1 ] || ODD="$ODD ${obj}"
	done
	if [ -z "$ODD" ]; then
		ok "У адресов функций стоит признак Thumb: адреса нечётные"
	else
		fail "Адрес функции без признака Thumb:$ODD"
	fi

	for obj in stack_variable heap_variable; do
		UNIQUE="$(obj_field "$obj" 2 | sort -u | grep -c .)"
		COUNT="$(obj_field "$obj" 2 | grep -c .)"
		if [ "$COUNT" -lt 2 ]; then
			fail "В логе меньше двух строк ${obj}"
		elif [ "$UNIQUE" = "1" ]; then
			ok "Адрес ${obj} одинаков во всех вызовах"
		elif [ "$obj" = "heap_variable" ]; then
			fail "Адрес блока в куче менялся от вызова к вызову"
			note "Лог снимается с возвращённым free(): аллокатор отдаёт тот же блок снова. Растущий адрес — это опыт шага 6, а не результат задания."
		else
			warn "Адрес локальной переменной между вызовами изменился — глубина вызова была разной"
		fi
	done

	for obj in data_variable bss_variable; do
		SEQ="$(obj_field "$obj" 3)"
		STEPS="$(echo "$SEQ" | awk 'NR > 1 && $1 != prev + 1 {bad++} {prev = $1} END {print bad + 0}')"
		COUNT="$(echo "$SEQ" | grep -c .)"
		if [ "$COUNT" -lt 2 ]; then
			fail "В логе меньше двух значений ${obj}"
		elif [ "$STEPS" = "0" ]; then
			ok "Значение ${obj} растёт на единицу за вызов"
		else
			fail "Значение ${obj} растёт не на единицу за вызов"
		fi
	done

	DATA_V="$(obj_field data_variable 3 | head -1)"
	BSS_V="$(obj_field bss_variable 3 | head -1)"
	if [ -n "$DATA_V" ] && [ -n "$BSS_V" ] && [ "$DATA_V" -gt "$BSS_V" ]; then
		ok "Счёт у переменных начался с разного: $DATA_V против $BSS_V"
	else
		warn "Значения data_variable и bss_variable не расходятся — начальное значение .data не видно"
	fi
fi

# Секцию объекту отводит компилятор, и это не обмануть правкой комментария.
BUILD_KEEP=1
if build_project "$SRC" && [ -n "${BUILD_ELF:-}" ]; then
	SYMBOLS="$(mktemp)"
	if arm-none-eabi-objdump -t "$BUILD_ELF" > "$SYMBOLS" 2>/dev/null; then
		check_section() {
			local name="$1" want="$2" got
			got="$(awk -v n="$name" '$NF == n {print $(NF-2)}' "$SYMBOLS" | head -1)"
			if [ "$got" = "$want" ]; then
				ok "Переменная \`$name\` легла в секцию $want"
			elif [ -z "$got" ]; then
				fail "Переменной \`$name\` нет в собранном образе"
			else
				fail "Переменная \`$name\` легла в $got, а должна в $want"
			fi
		}
		check_section data_variable .data
		check_section bss_variable .bss

		if [ -n "${RECEIVED:-}" ]; then
			BSS_END="$(awk '$NF == "__bss_end__" {print "0x" $1; exit}' "$SYMBOLS")"
			HEAP_A="$(obj_field heap_variable 2 | head -1)"
			if [ -n "$BSS_END" ] && [ -n "$HEAP_A" ]; then
				if [ "$(($HEAP_A))" -ge "$(($BSS_END))" ]; then
					ok "Блок кучи взят за концом .bss, из свободной области ОЗУ"
				else
					warn "Адрес блока кучи $HEAP_A лежит до конца .bss ($BSS_END) в здешней сборке"
					note "Так бывает, когда лог снят другой сборкой: у неё .bss кончалась в другом месте."
				fi
			fi
		fi
	else
		warn "Не удалось прочитать таблицу символов: нет arm-none-eabi-objdump"
	fi
	rm -f "$SYMBOLS"
fi
[ -n "${BUILD_DIR:-}" ] && rm -rf "$BUILD_DIR"

finish "$TITLE"
