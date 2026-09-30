#!/usr/bin/env bash
# Текст программы без комментариев. Подключается проверками, которые ищут в коде
# то, чего там быть не должно: запрещённый вызов, упомянутый в комментарии,
# не должен заваливать задание.
#
# code_only <нормализованный файл> — печатает путь к копии без комментариев // и /* */.
# Строки не склеиваются и не сдвигаются: номера строк совпадают с исходным файлом.

code_only() {
	local out
	out="$(mktemp)"
	awk '
		{
			line = $0
			result = ""
			while (length(line) > 0) {
				if (in_block) {
					end = index(line, "*/")
					if (end == 0) { line = ""; break }
					line = substr(line, end + 2)
					in_block = 0
					continue
				}
				slash = index(line, "//")
				block = index(line, "/*")
				if (slash && (!block || slash < block)) { result = result substr(line, 1, slash - 1); line = ""; break }
				if (block) { result = result substr(line, 1, block - 1); line = substr(line, block + 2); in_block = 1; continue }
				result = result line
				line = ""
			}
			print result
		}
	' "$1" > "$out"
	echo "$out"
}

# function_body <нормализованный файл> <имя функции> — строки тела функции,
# от строки с её именем до первой закрывающей скобки в начале строки.
function_body() {
	awk -v name="$2" '
		!on && $0 ~ name "[[:space:]]*\\(" && $0 !~ /;[[:space:]]*$/ { on = 1 }
		on { print }
		on && /^}/ { exit }
	' "$1"
}
