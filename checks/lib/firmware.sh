#!/usr/bin/env bash
# Файлы проекта, который растёт по вехам и меняет раскладку. Подключается проверками
# занятия 2.3: модуль за занятие переезжает из папки проекта в logic/ или в libs/ в корне
# репозитория, поэтому файл ищется по имени, а не по пути. Так проверка ранней вехи
# проходит и до, и после того, как проект перестроили.
#
# Перед подключением проверка задаёт FW_SRC (папка проекта) и FW_LIBS (папка libs).
# Сборка в build не просматривается.

# fw_find <имя файла> — путь к первому файлу с таким именем в проекте или в libs
fw_find() {
	find "$FW_SRC" "$FW_LIBS" -type f -name "$1" -not -path '*/build/*' 2>/dev/null | sort | head -1
}

# fw_need <переменная> <имя файла> — пункт «файл есть»; путь к файлу кладёт в переменную,
# пустую, если файла нет
fw_need() {
	local path
	path="$(fw_find "$2")"
	printf -v "$1" '%s' "$path"
	if [ -n "$path" ]; then
		ok "Файл $2 на месте: ${path#$FW_REPO/}"
	else
		fail "Нет файла $2 ни в папке проекта, ни в libs"
	fi
}

# fw_code <файл> — путь к копии без комментариев, в UTF-8 и с переводами строк LF
fw_code() {
	code_only "$(normalize "$1")"
}

# fw_join <имя файла>... — код всех найденных файлов с такими именами одним файлом
fw_join() {
	local out name path
	out="$(mktemp)"
	for name in "$@"; do
		find "$FW_SRC" "$FW_LIBS" -type f -name "$name" -not -path '*/build/*' 2>/dev/null | sort |
			while read -r path; do cat "$(fw_code "$path")"; done >> "$out"
	done
	echo "$out"
}

# fw_flat <файл> — тот же текст в одну строку: объявления занимают несколько строк
fw_flat() {
	local out
	out="$(mktemp)"
	tr '\n' ' ' < "$1" > "$out"
	echo "$out"
}

# fw_project_code — код всех .c и .h проекта без комментариев одним файлом
fw_project_code() {
	local out path
	out="$(mktemp)"
	find "$FW_SRC" -type f \( -name '*.c' -o -name '*.h' \) -not -path '*/build/*' | sort |
		while read -r path; do cat "$(fw_code "$path")"; done > "$out"
	echo "$out"
}

# fw_start <заголовок> <папка проекта по умолчанию> <репозиторий> [папка проекта] —
# заводит FW_REPO, FW_SRC, FW_LIBS и проверяет, что папка проекта есть
fw_start() {
	TITLE="$1"
	FW_REPO="${3:-.}"
	PROJECT="${4:-$2}"
	FW_SRC="$FW_REPO/$PROJECT"
	FW_LIBS="$FW_REPO/libs"

	if [ ! -d "$FW_SRC" ]; then
		fail "В репозитории нет папки проекта $PROJECT"
		finish "$TITLE"
		exit 1
	fi
	ok "Папка проекта $PROJECT найдена"
}
