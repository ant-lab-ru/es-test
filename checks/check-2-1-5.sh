#!/usr/bin/env bash
# Задание п2.1.5 «Память массивов и структур».
# Раскладка полей структуры: offsetof и sizeof, заполнение, перестановка полей от больших к меньшим.
# Использование: check-2-1-5.sh <путь к репозиторию> [папка проекта]
set -u

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
. "$LIB/report.sh"
. "$LIB/build.sh"
. "$LIB/device.sh"

TITLE="Задание 2.1.5 — Память массивов и структур"
REPO="${1:-.}"
PROJECT="${2:-211-command-usb}"
SRC="$REPO/$PROJECT"

if [ ! -d "$SRC" ]; then
	fail "В репозитории нет папки проекта $PROJECT"
	finish "$TITLE"
	exit 1
fi
ok "Папка проекта $PROJECT найдена"

for f in device/device.h device/device.c main.c check-2-1-5.py device-2-1-5.log; do
	if [ -f "$SRC/$f" ]; then
		ok "Файл $f на месте"
	else
		fail "В проекте нет файла $f"
	fi
done

HEADER="$SRC/device/device.h"
if [ -f "$HEADER" ]; then
	HEADER="$(normalize "$HEADER")"
	FLAT="$(mktemp)"
	tr '\n' ' ' < "$HEADER" > "$FLAT"

	match "$FLAT" 'struct[[:space:]]+info_t[[:space:]]*\{' \
		"device.h: объявлен тип struct info_t" \
		"device.h: нет объявления struct info_t"

	MISSING=""
	for t in uint32_t uint8_t char; do
		grep -Eq "$t" "$HEADER" || MISSING="$MISSING $t"
	done
	if [ -z "$MISSING" ]; then
		ok "device.h: у полей структуры разные размеры"
	else
		fail "device.h: в структуре нет полей типов:$MISSING"
		note "Заполнение видно только тогда, когда размеры полей разные."
	fi

	if grep -Eq 'char[[:space:]]+[a-z_]+[[:space:]]*\[[0-9]+\]' "$HEADER"; then
		ok "device.h: у массива символов задана явная длина"
	else
		fail "device.h: у массива символов в структуре нет явной длины"
		note "Запись char name[] полем структуры не работает: у поля не будет размера."
	fi

	match "$HEADER" 'extern[[:space:]]+struct[[:space:]]+info_t[[:space:]]+device_card' \
		"device.h: переменная device_card объявлена внешней" \
		"device.h: нет объявления extern для device_card"

	match "$HEADER" 'void[[:space:]]+dev_info[[:space:]]*\([[:space:]]*void[[:space:]]*\)' \
		"device.h: объявлена функция dev_info" \
		"device.h: нет объявления dev_info"

	rm -f "$FLAT"
fi

BODY="$SRC/device/device.c"
if [ -f "$BODY" ]; then
	BODY="$(normalize "$BODY")"

	match "$BODY" 'struct[[:space:]]+info_t[[:space:]]+device_card[[:space:]]*=' \
		"device.c: переменная device_card заведена и заполнена" \
		"device.c: нет заполненной переменной device_card"
	match "$BODY" 'dev_info[[:space:]]*\([[:space:]]*void[[:space:]]*\)' \
		"device.c: написана функция dev_info" \
		"device.c: нет функции dev_info"
	match "$BODY" '#include[[:space:]]*<stddef\.h>' \
		"device.c: подключён <stddef.h> — в нём объявлен offsetof" \
		"device.c: нет #include <stddef.h>, без него offsetof не объявлен"

	OFFSETS="$(grep -Ec 'offsetof[[:space:]]*\(' "$BODY")"
	if [ "$OFFSETS" -ge 3 ]; then
		ok "device.c: смещение каждого поля берётся макросом offsetof"
	else
		fail "device.c: offsetof встречается $OFFSETS раза, а полей в структуре три"
		note "Считать смещения руками нельзя: как расставить поля, решает компилятор."
	fi

	match "$BODY" 'sizeof[[:space:]]*\([[:space:]]*device_card[[:space:]]*\)' \
		"device.c: размер структуры берётся оператором sizeof" \
		"device.c: нет sizeof(device_card)"
	match "$BODY" 'sizeof[[:space:]]*\([[:space:]]*device_card\.' \
		"device.c: размеры полей берутся оператором sizeof" \
		"device.c: размеры полей не берутся через sizeof"
fi

# Паспорт принадлежит модулю device: раскладку печатает он, а не модуль памяти.
BODY="$SRC/memory/memory.c"
if [ -f "$BODY" ]; then
	BODY="$(normalize "$BODY")"
	if grep -Eq 'device_card' "$BODY"; then
		fail "memory.c: модуль памяти знает про device_card"
		note "Структура — дело модуля device: раскладку печатает dev_info, а fw_info остаётся прежней."
	else
		ok "memory.c: модуль памяти про структуру не знает"
	fi
fi

MAIN="$SRC/main.c"
if [ -f "$MAIN" ]; then
	MAIN="$(normalize "$MAIN")"
	match "$MAIN" '"dev_info"' \
		"main.c: команда dev_info есть в таблице команд" \
		"main.c: в таблице команд нет dev_info"
fi

# Размер структуры спрашиваем у собранного образа: только он знает,
# что компилятор сделал с порядком полей на самом деле.
STRUCT_SIZE=""
BUILD_KEEP=1
if build_project "$SRC" && [ -n "${BUILD_ELF:-}" ]; then
	SYMBOLS="$(mktemp)"
	if arm-none-eabi-objdump -t "$BUILD_ELF" > "$SYMBOLS" 2>/dev/null; then
		LINE="$(awk '$NF == "device_card" {print; exit}' "$SYMBOLS")"
		if [ -n "$LINE" ]; then
			STRUCT_SIZE="$((16#$(echo "$LINE" | awk '{print $(NF-1)}')))"
			ok "В собранном образе под device_card отведено $STRUCT_SIZE байт"

			SECTION="$(echo "$LINE" | awk '{print $(NF-2)}')"
			if [ "$SECTION" = ".data" ]; then
				ok "Переменная device_card легла в секцию .data — она заполнена значениями"
			else
				fail "Переменная device_card легла в $SECTION, а должна в .data"
				note "Структуру полагается заполнить сведениями об устройстве: незаполненная уходит в .bss."
			fi
		else
			warn "В образе не нашлась переменная device_card"
		fi
	else
		warn "Не удалось прочитать таблицу символов: нет arm-none-eabi-objdump"
	fi
	rm -f "$SYMBOLS"
fi
[ -n "${BUILD_DIR:-}" ] && rm -rf "$BUILD_DIR"

if device_log "$SRC/device-2-1-5.log" "2.1.5"; then
	RECEIVED="$(device_received "$DEVICE_LOG")"

	if device_sent "$DEVICE_LOG" | grep -qx 'dev_info'; then
		ok "Скрипт отправил команду dev_info"
	else
		fail "В логе нет отправленной команды dev_info"
	fi

	# Первый блок раскладки: от шапки таблицы до итоговой строки.
	BLOCK="$(echo "$RECEIVED" | awk '/^struct[[:space:]]+address/ {on = 1; next} on && /^fields / {exit} on {print}')"
	SUMMARY="$(echo "$RECEIVED" | grep -E '^fields [0-9]+, sizeof [0-9]+, padding [0-9]+' | head -1)"

	STRUCT_ADDR="$(echo "$BLOCK" | awk '$1 == "device_card" && $2 ~ /^0x[0-9a-f]+$/ {print $2; exit}')"
	LOG_SIZE="$(echo "$BLOCK" | awk '$1 == "device_card" && $2 ~ /^0x[0-9a-f]+$/ {print $3; exit}')"
	FIELDS="$(echo "$BLOCK" | awk 'NF >= 5 && $1 == "-" && $3 ~ /^0x[0-9a-f]+$/ {print $2, $3, $4, $5}')"
	FIELD_COUNT="$(echo "$FIELDS" | grep -c .)"

	if [ -n "$STRUCT_ADDR" ] && [ -n "$LOG_SIZE" ]; then
		ok "Плата напечатала адрес структуры $STRUCT_ADDR и её размер $LOG_SIZE"
	else
		fail "В ответе платы нет строки с адресом и размером структуры"
	fi

	if [ "$FIELD_COUNT" -ge 3 ]; then
		ok "Плата напечатала раскладку всех трёх полей: адрес, размер, смещение"
	else
		fail "В ответе платы строк по полям меньше трёх (нашлось $FIELD_COUNT)"
		note "На каждое поле нужна строка: адрес, размер, смещение и значение."
	fi

	if [ -n "$STRUCT_ADDR" ] && [ "$FIELD_COUNT" -ge 3 ]; then
		WRONG=""
		while read -r NAME ADDR SIZE OFFSET; do
			[ "$((ADDR))" -eq "$((STRUCT_ADDR + OFFSET))" ] || WRONG="$WRONG $NAME"
		done <<< "$FIELDS"
		if [ -z "$WRONG" ]; then
			ok "Адрес каждого поля равен адресу структуры плюс смещение"
		else
			fail "Адрес не сходится со смещением у полей:$WRONG"
			note "Адрес поля — это адрес структуры плюс offsetof: сверьте, что печатается именно он."
		fi

		GAPS="$(echo "$FIELDS" | awk '
			NR > 1 && ($4 + 0) != prev { print $1 }
			{ prev = $4 + $3 }')"
		if [ -z "$GAPS" ]; then
			ok "Разрывов между полями не осталось: поля переставлены от строгого выравнивания к слабому"
		else
			fail "Перед полями остался разрыв: $(echo "$GAPS" | tr '\n' ' ')"
			note "Объявите поля от строгого выравнивания к слабому и снимите лог заново: заполнение между полями исчезнет."
		fi
	fi

	if [ -n "$SUMMARY" ]; then
		ok "Плата сама подвела итог: сумма полей, sizeof и заполнение"

		LOG_FIELDS="$(echo "$SUMMARY" | sed -n 's/^fields \([0-9]\{1,\}\).*/\1/p')"
		LOG_SIZEOF="$(echo "$SUMMARY" | sed -n 's/.*sizeof \([0-9]\{1,\}\).*/\1/p')"
		LOG_PADDING="$(echo "$SUMMARY" | sed -n 's/.*padding \([0-9]\{1,\}\).*/\1/p')"

		if [ "$((LOG_FIELDS + LOG_PADDING))" = "$LOG_SIZEOF" ]; then
			ok "Итог сходится сам с собой: $LOG_FIELDS + $LOG_PADDING = $LOG_SIZEOF"
		else
			fail "Итог не сходится: сумма полей $LOG_FIELDS плюс заполнение $LOG_PADDING не равны sizeof $LOG_SIZEOF"
		fi

		if [ "$FIELD_COUNT" -ge 3 ]; then
			SUM="$(echo "$FIELDS" | awk '{s += $3} END {print s + 0}')"
			if [ "$SUM" = "$LOG_FIELDS" ]; then
				ok "Сумма размеров полей совпала с размерами из таблицы"
			else
				fail "В итоге сумма полей $LOG_FIELDS, а по таблице выходит $SUM"
			fi
		fi

		if [ -n "$LOG_SIZE" ] && [ "$LOG_SIZE" != "$LOG_SIZEOF" ]; then
			fail "В таблице размер структуры $LOG_SIZE, а в итоге sizeof $LOG_SIZEOF"
		fi

		if [ -n "$STRUCT_SIZE" ] && [ -n "$LOG_SIZEOF" ]; then
			if [ "$LOG_SIZEOF" = "$STRUCT_SIZE" ]; then
				ok "sizeof из лога совпал с размером структуры в собранном образе"
			else
				fail "В логе sizeof $LOG_SIZEOF, а в образе структура занимает $STRUCT_SIZE байт"
				note "Лог снят с другой сборки: запишите прошивку из репозитория и снимите лог заново."
			fi
		fi
	else
		fail "В ответе платы нет итоговой строки с суммой полей, sizeof и заполнением"
		note "Итог считает прибор: fields, sizeof и padding одной строкой."
	fi
fi

finish "$TITLE"
