#!/usr/bin/env bash
# Задание п1.2.1 «Мигание светодиодом через регистр».
# Состав проекта, отсутствие gpio_put, обращение к регистрам SIO, имя проекта, сборка.
# Мигание светодиода в CI не проверяется.
# Использование: check-1-2-1.sh <путь к репозиторию> [папка проекта]
set -u

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
. "$LIB/report.sh"
. "$LIB/build.sh"
. "$LIB/cmake.sh"

TITLE="Задание 1.2.1 — Мигание светодиодом через регистр"
REPO="${1:-.}"
PROJECT="${2:-121-blink-reg}"
SRC="$REPO/$PROJECT"

if [ ! -d "$SRC" ]; then
	fail "В репозитории нет папки проекта $PROJECT"
	finish "$TITLE"
	exit 1
fi
ok "Папка проекта $PROJECT найдена"

EXPECTED="main.c CMakeLists.txt memmap_rp2040.ld pico_sdk_import.cmake"
for f in $EXPECTED; do
	if [ -f "$SRC/$f" ]; then
		ok "Файл $f на месте"
	else
		fail "В проекте нет файла $f"
	fi
done

EXTRA=""
for f in "$SRC"/*; do
	[ -f "$f" ] || continue
	name="$(basename "$f")"
	case " $EXPECTED " in
		*" $name "*) ;;
		*) EXTRA="$EXTRA $name" ;;
	esac
done
[ -z "$EXTRA" ] && ok "В проекте ровно четыре файла" || warn "В проекте есть лишние файлы:$EXTRA"

MAIN="$SRC/main.c"
if [ -f "$MAIN" ]; then
	MAIN="$(normalize "$MAIN")"

	if grep -Eq 'gpio_put[[:space:]]*\(' "$MAIN"; then
		fail "main.c: вызов gpio_put остался — светодиодом по-прежнему управляет функция SDK"
		note "Задание в том, чтобы заменить его записью числа по адресу регистра."
	else
		ok "main.c: вызовов gpio_put нет"
	fi

	match "$MAIN" 'SIO_BASE|0[xX][dD]0000000' \
		"main.c: используется базовый адрес блока SIO" \
		"main.c: нет обращения к базовому адресу блока SIO"
	match "$MAIN" 'SIO_GPIO_OUT_SET_OFFSET|0[xX][dD]0000014' \
		"main.c: есть обращение к регистру GPIO_OUT_SET" \
		"main.c: нет обращения к регистру GPIO_OUT_SET — нечем зажечь светодиод"
	match "$MAIN" 'SIO_GPIO_OUT_CLR_OFFSET|0[xX][dD]0000018' \
		"main.c: есть обращение к регистру GPIO_OUT_CLR" \
		"main.c: нет обращения к регистру GPIO_OUT_CLR — нечем погасить светодиод"
	match "$MAIN" 'gpio_set_dir[[:space:]]*\(.*GPIO_OUT' \
		"main.c: вывод светодиода настроен на выход" \
		"main.c: нет настройки вывода через gpio_set_dir с GPIO_OUT"
	match "$MAIN" 'sleep_ms[[:space:]]*\(' \
		"main.c: есть задержка между переключениями" "main.c: нет вызова sleep_ms"
	match "$MAIN" 'while[[:space:]]*\([[:space:]]*(1|true)[[:space:]]*\)|for[[:space:]]*\([[:space:]]*;[[:space:]]*;[[:space:]]*\)' \
		"main.c: есть бесконечный цикл" "main.c: нет бесконечного цикла — функция main завершится"
fi

check_project_name "$SRC" "$PROJECT"

build_project "$SRC"

note "Мигание светодиода проверяется на плате: в CI такой проверки нет."
finish "$TITLE"
