#!/usr/bin/env bash
# Задание п2.1.2 «Карта секций прошивки».
# Три объекта разных секций, отчёт по секциям, цена вывода в терминал.
# Плата в этом задании не нужна: проверка собирает образ и смотрит в него сама.
# Использование: check-2-1-2.sh <путь к репозиторию> [папка проекта]
set -u

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
. "$LIB/report.sh"
. "$LIB/build.sh"

TITLE="Задание 2.1.2 — Карта секций прошивки"
REPO="${1:-.}"
PROJECT="${2:-211-command-usb}"
SRC="$REPO/$PROJECT"

if [ ! -d "$SRC" ]; then
	fail "В репозитории нет папки проекта $PROJECT"
	finish "$TITLE"
	exit 1
fi
ok "Папка проекта $PROJECT найдена"

for f in device/device.c device/device.h sections-2-1-2.md; do
	if [ -f "$SRC/$f" ]; then
		ok "Файл $f на месте"
	else
		fail "В проекте нет файла $f"
	fi
done

DEVICE="$SRC/device/device.c"
if [ -f "$DEVICE" ]; then
	DEVICE="$(normalize "$DEVICE")"
	match "$DEVICE" 'const[[:space:]]+char[[:space:]]+DEVICE_TAG[[:space:]]*\[' \
		"device.c: заведена константа-массив DEVICE_TAG" \
		"device.c: нет константы DEVICE_TAG"
	match "$DEVICE" 'uint32_t[[:space:]]+boot_marker[[:space:]]*=[[:space:]]*0x' \
		"device.c: заведена переменная boot_marker с начальным значением" \
		"device.c: нет переменной boot_marker с ненулевым начальным значением"
fi

# Главный пункт задания: где объекты оказались на самом деле.
# Секцию спрашиваем у собранного образа, а не у текста программы.
BUILD_KEEP=1
if build_project "$SRC" && [ -n "${BUILD_ELF:-}" ]; then
	SYMBOLS="$(mktemp)"
	if arm-none-eabi-objdump -t "$BUILD_ELF" > "$SYMBOLS" 2>/dev/null; then
		check_section() {
			local name="$1" want="$2" got
			got="$(awk -v n="$name" '$NF == n {print $(NF-2)}' "$SYMBOLS" | head -1)"
			if [ "$got" = "$want" ]; then
				ok "$name лежит в секции $want"
			elif [ -z "$got" ]; then
				fail "$name не найден в собранном образе"
			else
				fail "$name лежит в $got, а должен в $want"
			fi
		}
		check_section DEVICE_TAG .rodata
		check_section boot_marker .data
		check_section line .bss
	else
		warn "Не удалось прочитать таблицу символов: нет arm-none-eabi-objdump"
	fi
	rm -f "$SYMBOLS"
fi
[ -n "${BUILD_DIR:-}" ] && rm -rf "$BUILD_DIR"

REPORT="$SRC/sections-2-1-2.md"
if [ -f "$REPORT" ]; then
	REPORT="$(normalize "$REPORT")"

	MISSING=""
	for s in '\.boot2' '\.text' '\.rodata' '\.data' '\.bss'; do
		grep -Eq "$s" "$REPORT" || MISSING="$MISSING $(echo "$s" | tr -d '\\')"
	done
	if [ -z "$MISSING" ]; then
		ok "Отчёт: названы все пять секций"
	else
		fail "Отчёт: не названы секции:$MISSING"
	fi

	for obj in DEVICE_TAG boot_marker line; do
		if grep -E "$obj" "$REPORT" | grep -Eq '0x[0-9a-fA-F]{8}'; then
			ok "Отчёт: у объекта $obj записан адрес"
		else
			fail "Отчёт: у объекта $obj нет адреса вида 0x…"
		fi
	done

	if grep -Eq '[Сс]умма' "$REPORT" && grep -Eq 'сходится|совпад|равн' "$REPORT"; then
		ok "Отчёт: сумма хранимых секций сведена с размером .bin"
	else
		fail "Отчёт: нет строки о том, что сумма секций сошлась с размером .bin"
		note "Сложите .boot2, .text, .rodata, .binary_info и .data — выйдет размер файла .bin."
	fi

	if grep -Eq '[Цц]ена вывода' "$REPORT" && grep -Eq '[0-9]{4,}' "$REPORT"; then
		ok "Отчёт: цена вывода в терминал измерена в байтах"
	else
		fail "Отчёт: нет измеренной цены вывода в терминал"
		note "Соберите проект с pico_enable_stdio_usb 1 и 0 и сравните размеры."
	fi

	if grep -Eq '\.bss' "$REPORT" && grep -Eq 'нигде|не хранится|не занимает|отсутств' "$REPORT"; then
		ok "Отчёт: сказано, что .bss в образе не хранится"
	else
		warn "Отчёт: не сказано, почему .bss не участвует в сумме"
	fi
fi

CMAKE="$SRC/CMakeLists.txt"
if [ -f "$CMAKE" ]; then
	if grep -Eq 'pico_enable_stdio_usb[[:space:]]*\([^)]*1[[:space:]]*\)' "$CMAKE"; then
		ok "CMakeLists.txt: вывод в USB включён обратно"
	else
		fail "CMakeLists.txt: вывод в USB остался выключенным после замера"
		note "Верните pico_enable_stdio_usb(\${PROJECT_NAME} 1) — иначе следующие задания не заработают."
	fi
fi

finish "$TITLE"
