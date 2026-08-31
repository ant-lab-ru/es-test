#!/usr/bin/env bash
# Задание п1.2.2 «Светодиод и кнопка».
# Состав проекта, настройка вывода кнопки на вход с подтяжкой, чтение вывода, сборка.
# Поведение кнопки и светодиода в CI не проверяется.
# Использование: check-1-2-2.sh <путь к репозиторию> [папка проекта]
set -u

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
. "$LIB/report.sh"
. "$LIB/build.sh"

TITLE="Задание 1.2.2 — Светодиод и кнопка"
REPO="${1:-.}"
PROJECT="${2:-122-led-button}"
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

	match "$MAIN" 'gpio_set_dir[[:space:]]*\(.*GPIO_OUT' \
		"main.c: вывод светодиода настроен на выход" \
		"main.c: нет настройки вывода на выход через gpio_set_dir с GPIO_OUT"
	match "$MAIN" 'gpio_set_dir[[:space:]]*\(.*GPIO_IN' \
		"main.c: вывод кнопки настроен на вход" \
		"main.c: нет настройки вывода на вход через gpio_set_dir с GPIO_IN"
	match "$MAIN" 'gpio_pull_up[[:space:]]*\(|gpio_pull_down[[:space:]]*\(|gpio_set_pulls[[:space:]]*\(' \
		"main.c: на выводе кнопки включена подтяжка" \
		"main.c: подтяжка не включена — отпущенная кнопка будет читаться случайно"
	match "$MAIN" 'gpio_get[[:space:]]*\(' \
		"main.c: состояние вывода кнопки считывается" \
		"main.c: нет вызова gpio_get — кнопка не опрашивается"
	match "$MAIN" 'gpio_put[[:space:]]*\(' \
		"main.c: состояние светодиода переключается" "main.c: нет вызова gpio_put"
	match "$MAIN" 'while[[:space:]]*\([[:space:]]*(1|true)[[:space:]]*\)|for[[:space:]]*\([[:space:]]*;[[:space:]]*;[[:space:]]*\)' \
		"main.c: есть бесконечный цикл" "main.c: нет бесконечного цикла — функция main завершится"

	# Опрос кнопки должен идти в суперцикле, а не один раз до него.
	if awk '/while[ \t]*\([ \t]*(1|true)[ \t]*\)|for[ \t]*\([ \t]*;[ \t]*;[ \t]*\)/{f=1} f' "$MAIN" | grep -Eq 'gpio_get[[:space:]]*\('; then
		ok "main.c: кнопка опрашивается внутри бесконечного цикла"
	else
		fail "main.c: внутри бесконечного цикла нет чтения вывода кнопки"
		note "Прочитанное один раз до цикла состояние больше не обновится."
	fi
fi

build_project "$SRC"

note "Переключение светодиода по нажатию проверяется на плате: в CI такой проверки нет."
finish "$TITLE"
