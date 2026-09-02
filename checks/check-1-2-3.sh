#!/usr/bin/env bash
# Задание п1.2.3 «Программное избавление от дребезга».
# Состав проекта, функция подавления дребезга и её вызов в суперцикле, имя проекта, сборка.
# Устойчивость переключения в CI не проверяется.
# Использование: check-1-2-3.sh <путь к репозиторию> [папка проекта]
set -u

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
. "$LIB/report.sh"
. "$LIB/build.sh"
. "$LIB/cmake.sh"

TITLE="Задание 1.2.3 — Программное избавление от дребезга"
REPO="${1:-.}"
PROJECT="${2:-123-led-button-debounce}"
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

	match "$MAIN" 'bool[[:space:]]+get_button_debounce[[:space:]]*\([[:space:]]*uint[[:space:]]+[A-Za-z_]' \
		"main.c: объявлена функция bool get_button_debounce(uint pin)" \
		"main.c: нет функции с сигнатурой bool get_button_debounce(uint pin)"
	match "$MAIN" 'sleep_ms[[:space:]]*\(' \
		"main.c: в подавлении дребезга есть выдержка по времени" \
		"main.c: нет вызова sleep_ms — уровень читается без выдержки"
	match "$MAIN" 'gpio_pull_up[[:space:]]*\(|gpio_pull_down[[:space:]]*\(|gpio_set_pulls[[:space:]]*\(' \
		"main.c: на выводе кнопки включена подтяжка" \
		"main.c: подтяжка не включена — отпущенная кнопка будет читаться случайно"
	match "$MAIN" 'while[[:space:]]*\([[:space:]]*(1|true)[[:space:]]*\)|for[[:space:]]*\([[:space:]]*;[[:space:]]*;[[:space:]]*\)' \
		"main.c: есть бесконечный цикл" "main.c: нет бесконечного цикла — функция main завершится"

	LOOP="$(awk '/while[ \t]*\([ \t]*(1|true)[ \t]*\)|for[ \t]*\([ \t]*;[ \t]*;[ \t]*\)/{f=1} f' "$MAIN")"

	if echo "$LOOP" | grep -Eq 'get_button_debounce[[:space:]]*\('; then
		ok "main.c: кнопка опрашивается вызовом get_button_debounce"
	else
		fail "main.c: в бесконечном цикле нет вызова get_button_debounce"
		note "Функция объявлена, но опрос по-прежнему идёт мимо неё."
	fi

	if echo "$LOOP" | grep -Eq 'gpio_get[[:space:]]*\('; then
		fail "main.c: в бесконечном цикле остался прямой вызов gpio_get"
		note "Чтение вывода должно идти только через get_button_debounce."
	else
		ok "main.c: прямого вызова gpio_get в бесконечном цикле не осталось"
	fi
fi

check_project_name "$SRC" "$PROJECT"

build_project "$SRC"

note "Устойчивость переключения проверяется на плате: в CI такой проверки нет."
finish "$TITLE"
