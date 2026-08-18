#!/usr/bin/env bash
# Задание П1.1.3 «Запуск прошивки».
# Сборка проекта и появление файлов прошивки. Мигание светодиода в CI не проверяется.
# Использование: check-1-1-3.sh <путь к репозиторию> [папка проекта]
set -u

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/report.sh"

TITLE="Задание 1.1.3 — Запуск прошивки"
REPO="${1:-.}"
PROJECT="${2:-112-blink}"
SRC="$REPO/$PROJECT"

if [ ! -d "$SRC" ]; then
	fail "В репозитории нет папки проекта $PROJECT"
	finish "$TITLE"
	exit 1
fi

if [ -z "${PICO_SDK_PATH:-}" ]; then
	fail "Сборка не выполнялась: не задан PICO_SDK_PATH"
	finish "$TITLE"
	exit 1
fi

# В Windows make исполняет рецепты через sh, как только видит его в PATH — а в Git Bash
# он там всегда. Себя в рекурсивный вызов make подставляет полным путём и без кавычек,
# поэтому установка по умолчанию, «C:\Program Files (x86)\GnuWin32\bin», разваливает
# команду на скобках. Возврат к cmd.exe снимает это; в остальных системах переменная пуста.
MAKE_SHELL=""
case "$(uname -s)" in
	MINGW*|MSYS*|CYGWIN*) MAKE_SHELL="SHELL=cmd.exe" ;;
esac

BUILD="$(mktemp -d)"
if cmake -S "$SRC" -B "$BUILD" -G "Unix Makefiles" > "$BUILD/cmake.log" 2>&1; then
	ok "Конфигурация сборки завершается без ошибок"
else
	fail "Конфигурация сборки завершается с ошибкой"
	tail -20 "$BUILD/cmake.log"
	rm -rf "$BUILD"
	finish "$TITLE"
	exit 1
fi

if make -C "$BUILD" --no-print-directory $MAKE_SHELL > "$BUILD/make.log" 2>&1; then
	ok "Сборка проходит без ошибок"
else
	fail "Сборка завершается с ошибкой"
	note "Последние строки вывода make:"
	tail -30 "$BUILD/make.log"
	rm -rf "$BUILD"
	finish "$TITLE"
	exit 1
fi

UF2="$(find "$BUILD" -maxdepth 1 -name '*.uf2' | head -1)"
BIN="$(find "$BUILD" -maxdepth 1 -name '*.bin' | head -1)"

if [ -n "$UF2" ]; then
	ok "Получен файл прошивки $(basename "$UF2")"
else
	fail "После сборки не появился файл .uf2"
	note "Формат .uf2 генерирует вызов pico_add_extra_outputs в CMakeLists.txt."
fi

if [ -n "$BIN" ]; then
	ok "Получен двоичный образ $(basename "$BIN")"
else
	fail "После сборки не появился файл .bin"
fi

note "Мигание светодиода проверяется на плате: в CI такой проверки нет."
rm -rf "$BUILD"

finish "$TITLE"
