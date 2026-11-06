#!/usr/bin/env bash
# Текст программы без комментариев. Комментарий — не живой код: он не заваливает задание
# и не засчитывается вместо кода. Поэтому исходники читаются только через эти функции:
#
# code_only <файл>   — C: снимает // и /* */
# cmake_only <файл>  — CMake: снимает # и #[[ ]]
# python_only <файл> — Python: снимает #
#
# Файл уже нормализован (normalize из report.sh), на выходе — путь к копии. Кавычки
# учитываются: ссылка "https://…" в строке — это не комментарий. Строки не склеиваются
# и не сдвигаются: номера совпадают с исходным файлом, строка из одного комментария
# становится пустой. Разметка в кодировке ASCII, поэтому awk читает файл байтами.

code_only() {
	local out
	out="$(mktemp)"
	LC_ALL=C awk '
		{
			result = ""
			n = length($0)
			for (i = 1; i <= n; i++) {
				c = substr($0, i, 1)
				two = substr($0, i, 2)
				if (in_block) {
					if (two == "*/") { in_block = 0; i++ }
				} else if (quote != "") {
					result = result c
					if (c == "\\") { i++; result = result substr($0, i, 1) }
					else if (c == quote) quote = ""
				} else if (two == "//") {
					break
				} else if (two == "/*") {
					in_block = 1
					i++
					result = result " "
				} else {
					result = result c
					if (c == "\"" || c == "\047") quote = c
				}
			}
			# незакрытая кавычка живёт только в строке с переносом: апостроф в #error строку не открывает
			if (substr($0, n, 1) != "\\") quote = ""
			sub(/[ \t]+$/, "", result)
			print result
		}
	' "$1" > "$out"
	echo "$out"
}

cmake_only() {
	local out
	out="$(mktemp)"
	LC_ALL=C awk '
		{
			result = ""
			n = length($0)
			for (i = 1; i <= n; i++) {
				c = substr($0, i, 1)
				if (closing != "") {
					if (substr($0, i, length(closing)) == closing) { i += length(closing) - 1; closing = "" }
				} else if (in_string) {
					result = result c
					if (c == "\\") { i++; result = result substr($0, i, 1) }
					else if (c == "\"") in_string = 0
				} else if (c == "#") {
					rest = substr($0, i)
					if (!match(rest, /^#\[=*\[/)) break
					closing = "]" substr(rest, 3, RLENGTH - 3) "]"
					i += RLENGTH - 1
				} else {
					result = result c
					if (c == "\"") in_string = 1
				}
			}
			sub(/[ \t]+$/, "", result)
			print result
		}
	' "$1" > "$out"
	echo "$out"
}

python_only() {
	local out
	out="$(mktemp)"
	LC_ALL=C awk '
		{
			result = ""
			quote = ""
			n = length($0)
			for (i = 1; i <= n; i++) {
				c = substr($0, i, 1)
				if (quote != "") {
					result = result c
					if (c == "\\") { i++; result = result substr($0, i, 1) }
					else if (c == quote) quote = ""
				} else if (c == "#") {
					break
				} else {
					result = result c
					if (c == "\"" || c == "\047") quote = c
				}
			}
			sub(/[ \t]+$/, "", result)
			print result
		}
	' "$1" > "$out"
	echo "$out"
}

# same_code <файл> <файл> — совпадает ли код двух файлов на C: комментарии и пустые
# строки не считаются
same_code() {
	[ "$(grep . "$(code_only "$(normalize "$1")")")" = "$(grep . "$(code_only "$(normalize "$2")")")" ]
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
