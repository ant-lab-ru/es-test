#!/usr/bin/env bash
# Задание п2.1.6 «Память структуры».
# Структура паспорта, offsetof и sizeof, перестановка полей от больших к меньшим.
# Использование: check-2-1-6.sh <путь к репозиторию> [папка проекта]
set -u

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
. "$LIB/report.sh"
. "$LIB/build.sh"
. "$LIB/device.sh"

TITLE="Задание 2.1.6 — Память структуры"
REPO="${1:-.}"
PROJECT="${2:-211-command-usb}"
SRC="$REPO/$PROJECT"

if [ ! -d "$SRC" ]; then
	fail "В репозитории нет папки проекта $PROJECT"
	finish "$TITLE"
	exit 1
fi
ok "Папка проекта $PROJECT найдена"

for f in device/device.h device/device.c check-2-1-6.py device-2-1-6.log; do
	if [ -f "$SRC/$f" ]; then
		ok "Файл $f на месте"
	else
		fail "В проекте нет файла $f"
	fi
done

HEADER="$SRC/device/device.h"
if [ -f "$HEADER" ]; then
	HEADER="$(normalize "$HEADER")"

	match "$HEADER" 'struct[[:space:]]+info_t' \
		"device.h: объявлен тип struct info_t" \
		"device.h: нет типа struct info_t"

	MISSING=""
	for t in uint32_t uint16_t uint8_t char; do
		grep -Eq "$t" "$HEADER" || MISSING="$MISSING $t"
	done
	if [ -z "$MISSING" ]; then
		ok "device.h: в структуре поля разного размера"
	else
		fail "device.h: в структуре нет полей типов:$MISSING"
		note "Разрыв между полями виден только тогда, когда размеры разные."
	fi

	if grep -Eq 'char[[:space:]]+name[[:space:]]*\[[0-9]+\]' "$HEADER"; then
		ok "device.h: у массива name задана длина"
	else
		fail "device.h: у массива name нет явной длины"
		note "Запись char name[] в структуре не работает: у поля не будет размера."
	fi

	match "$HEADER" 'extern[[:space:]]+struct[[:space:]]+info_t' \
		"device.h: объявлена глобальная переменная-паспорт" \
		"device.h: нет объявления переменной типа struct info_t"
fi

BODY="$SRC/device/device.c"
if [ -f "$BODY" ]; then
	BODY="$(normalize "$BODY")"
	match "$BODY" '#include[[:space:]]*<stddef\.h>' \
		"device.c: подключён <stddef.h> ради offsetof" \
		"device.c: нет #include <stddef.h>"
	match "$BODY" 'offsetof[[:space:]]*\(' \
		"device.c: смещение поля берётся макросом offsetof" \
		"device.c: нет offsetof — смещения посчитаны руками"
	match "$BODY" 'sizeof[[:space:]]*\(' \
		"device.c: размеры берутся оператором sizeof" \
		"device.c: нет sizeof"
	match "$BODY" 'struct[[:space:]]+info_t[[:space:]]+[a-z_]+[[:space:]]*=' \
		"device.c: переменная-паспорт заполнена значениями" \
		"device.c: переменная типа struct info_t не заполнена"
fi

MAIN="$SRC/main.c"
if [ -f "$MAIN" ]; then
	MAIN="$(normalize "$MAIN")"
	match "$MAIN" '"card"' \
		"main.c: разобрана команда card" \
		"main.c: нет разбора команды card"
fi

# Размер структуры спрашиваем у собранного образа: только он знает,
# что компилятор сделал с порядком полей на самом деле.
STRUCT_SIZE=""
BUILD_KEEP=1
if build_project "$SRC" && [ -n "${BUILD_ELF:-}" ]; then
	SYMBOLS="$(mktemp)"
	if arm-none-eabi-objdump -t "$BUILD_ELF" > "$SYMBOLS" 2>/dev/null; then
		HEX="$(awk '$NF == "device_card" {print $(NF-1)}' "$SYMBOLS" | head -1)"
		if [ -n "$HEX" ]; then
			STRUCT_SIZE="$((16#$HEX))"
			ok "В собранном образе под структуру отведено $STRUCT_SIZE байт"
		else
			warn "В образе не нашлась переменная device_card"
		fi
	fi
	rm -f "$SYMBOLS"
fi
[ -n "${BUILD_DIR:-}" ] && rm -rf "$BUILD_DIR"

if device_log "$SRC/device-2-1-6.log" "2.1.6"; then
	RECEIVED="$(device_received "$DEVICE_LOG")"

	if device_sent "$DEVICE_LOG" | grep -qx 'card'; then
		ok "Скрипт отправил команду card"
	else
		fail "В логе нет отправленной команды card"
	fi

	FIELDS="$(echo "$RECEIVED" | grep -Ec '^\.[a-z_]+[[:space:]]+0x[0-9a-f]{8}[[:space:]]+[0-9]+[[:space:]]+[0-9]+')"
	if [ "$FIELDS" -ge 4 ]; then
		ok "Плата напечатала раскладку всех четырёх полей: адрес, смещение, размер"
	else
		fail "В ответе платы строк по полям меньше четырёх (нашлось $FIELDS)"
	fi

	SUMMARY="$(echo "$RECEIVED" | grep -E 'сумма полей' | head -1)"
	if [ -n "$SUMMARY" ]; then
		ok "Плата назвала сумму размеров полей и sizeof структуры"

		LOG_SIZEOF="$(echo "$SUMMARY" | sed -n 's/.*sizeof[^0-9]*\([0-9]\{1,\}\).*/\1/p')"
		LOG_SUM="$(echo "$SUMMARY" | sed -n 's/.*сумма полей[^0-9]*\([0-9]\{1,\}\).*/\1/p')"

		if [ -n "$STRUCT_SIZE" ] && [ -n "$LOG_SIZEOF" ]; then
			if [ "$LOG_SIZEOF" = "$STRUCT_SIZE" ]; then
				ok "sizeof из лога совпал с размером структуры в собранном образе"
			else
				fail "В логе sizeof $LOG_SIZEOF, а в образе структура занимает $STRUCT_SIZE байт"
				note "Лог снят с другой сборки: снимите его заново на той прошивке, что в репозитории."
			fi
		fi

		if [ -n "$LOG_SUM" ] && [ -n "$LOG_SIZEOF" ]; then
			if [ "$LOG_SUM" = "$LOG_SIZEOF" ]; then
				ok "После перестановки полей разрывов не осталось: сумма равна sizeof"
			else
				fail "Сумма полей $LOG_SUM и sizeof $LOG_SIZEOF всё ещё расходятся"
				note "Переставьте поля от больших к меньшим и снимите лог заново."
			fi
		fi
	else
		fail "В ответе платы нет строки с суммой полей и sizeof"
	fi

	OFFSETS="$(echo "$RECEIVED" | awk '$1 ~ /^\./ {print $3}' | head -1)"
	if [ "$OFFSETS" = "0" ]; then
		ok "Первое поле стоит по смещению 0"
	else
		warn "Первое поле в таблице стоит не по смещению 0"
	fi
fi

finish "$TITLE"
