#!/usr/bin/env bash
# Имя проекта в описании сборки. Подключается проверками заданий, где проект
# заводится копированием предыдущего: check_project_name <папка проекта> <имя папки>.
#
# Правило курса: имя проекта повторяет имя папки, дефисы заменены на подчёркивания.
# Записывается оно один раз, в project(), а остальные команды берут его из ${PROJECT_NAME}.

# Команды CMake переносятся на несколько строк, поэтому файл читается со
# схлопнутыми переводами строк.
cmake_flatten() {
	local out
	out="$(mktemp)"
	tr '\n' ' ' < "$(normalize "$1")" > "$out"
	echo "$out"
}

check_project_name() {
	local src="$1"
	local project="$2"
	local file="$src/CMakeLists.txt"
	[ -f "$file" ] || return 0

	local text name count missing cmd
	text="$(cmake_flatten "$file")"
	name="$(echo "$project" | tr '-' '_')"

	if grep -Eq "project[[:space:]]*\([[:space:]]*$name[[:space:]]*\)" "$text"; then
		ok "CMakeLists.txt: имя проекта $name задано в project()"
	else
		fail "CMakeLists.txt: в project() не задано имя проекта $name"
		note "Имя проекта повторяет имя папки, дефисы заменены на подчёркивания."
	fi

	count="$(grep -o "$name" "$text" | wc -l | tr -d ' ')"
	if [ "$count" -eq 1 ]; then
		ok "CMakeLists.txt: имя проекта записано в файле один раз"
	elif [ "$count" -gt 1 ]; then
		fail "CMakeLists.txt: имя $name повторяется в файле, вхождений — $count"
		note "В project() имя пишется один раз, в остальных командах его подставляет \${PROJECT_NAME}."
	fi

	missing=""
	for cmd in add_executable target_link_libraries pico_set_linker_script pico_add_extra_outputs; do
		grep -Eo "$cmd[[:space:]]*\([^)]*" "$text" | grep -q 'PROJECT_NAME' || missing="$missing $cmd"
	done
	if [ -z "$missing" ]; then
		ok "CMakeLists.txt: цель во всех командах названа \${PROJECT_NAME}"
	else
		fail "CMakeLists.txt: имя цели не подставляется через \${PROJECT_NAME} в командах:$missing"
	fi
}
