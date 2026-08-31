#!/usr/bin/env bash
# Сборка проекта обучающегося. Подключается проверками, которым нужно убедиться,
# что проект собирается: build_project <путь к папке проекта>.
#
# Без PICO_SDK_PATH сборка не выполняется, и проверка об этом сообщает замечанием —
# остальные пункты, читающие файлы, при этом отрабатывают как обычно.

build_project() {
	local src="$1"

	if [ -z "${PICO_SDK_PATH:-}" ]; then
		note "Сборка не проверялась: не задан PICO_SDK_PATH."
		return 0
	fi

	# В Windows make исполняет рецепты через sh, как только видит его в PATH — а в Git Bash
	# он там всегда. Себя в рекурсивный вызов make подставляет полным путём и без кавычек,
	# поэтому установка по умолчанию, «C:\Program Files (x86)\GnuWin32\bin», разваливает
	# команду на скобках. Возврат к cmd.exe снимает это; в остальных системах переменная пуста.
	local make_shell=""
	case "$(uname -s)" in
		MINGW*|MSYS*|CYGWIN*) make_shell="SHELL=cmd.exe" ;;
	esac

	local build
	build="$(mktemp -d)"

	if cmake -S "$src" -B "$build" -G "Unix Makefiles" > "$build/cmake.log" 2>&1; then
		ok "Конфигурация сборки завершается без ошибок"
	else
		fail "Конфигурация сборки завершается с ошибкой"
		note "Последние строки вывода cmake:"
		tail -20 "$build/cmake.log"
		rm -rf "$build"
		return 1
	fi

	if make -C "$build" --no-print-directory $make_shell > "$build/make.log" 2>&1; then
		ok "Сборка проходит без ошибок"
	else
		fail "Сборка завершается с ошибкой"
		note "Последние строки вывода make:"
		tail -30 "$build/make.log"
		rm -rf "$build"
		return 1
	fi

	rm -rf "$build"
	return 0
}
