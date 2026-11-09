#!/usr/bin/env bash
# Задание п2.1.2 «Таблица команд».
# Тип обработчика, массив пар «имя — функция», поиск по нему и вызов по указателю.
# Использование: check-2-1-2.sh <путь к репозиторию> [папка проекта]
set -u

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
. "$LIB/report.sh"
. "$LIB/build.sh"
. "$LIB/cmake.sh"
. "$LIB/device.sh"

TITLE="Задание 2.1.2 — Таблица команд"
REPO="${1:-.}"
PROJECT="${2:-211-command-usb}"
SRC="$REPO/$PROJECT"

if [ ! -d "$SRC" ]; then
	fail "В репозитории нет папки проекта $PROJECT"
	finish "$TITLE"
	exit 1
fi
ok "Папка проекта $PROJECT найдена"

for f in main.c check-2-1-2.py device-2-1-2.log; do
	if [ -f "$SRC/$f" ]; then
		ok "Файл $f на месте"
	else
		fail "В проекте нет файла $f"
	fi
done

MAIN="$SRC/main.c"

# Объявление типа, таблица и сборка ищутся по всем .c и .h рядом с main.c и в его
# подпапках: тип команды переезжает в api (п2.3.1), таблица обходится из memory
# (п2.1.4). Путь от этого не меняется: из main.c объявления видны всегда —
# через #include или прямо в файле.
SOURCES="$(mktemp)"
find "$SRC" -type f \( -name '*.c' -o -name '*.h' \) -not -path '*/build/*' -print0 2>/dev/null |
	sort -z | xargs -0 -r -n 1 bash -c '. "$1"; cat "$(normalize "$2")"' sh "$LIB/report.sh" > "$SOURCES"
FLAT="$(mktemp)"
tr '\n' ' ' < "$SOURCES" > "$FLAT"

match "$SOURCES" 'typedef[[:space:]]+void[[:space:]]*\([[:space:]]*\*[[:space:]]*command_handler_t[[:space:]]*\)[[:space:]]*\([[:space:]]*void[[:space:]]*\)' \
	"Объявлен тип command_handler_t — указатель на функцию без аргументов" \
	"Нет typedef указателя на функцию command_handler_t"

if grep -Eq 'struct[[:space:]]+command_t[[:space:]]*\{[^}]*name[^}]*handler[^}]*\}|struct[[:space:]]+command_t[[:space:]]*\{[^}]*handler[^}]*name[^}]*\}' "$FLAT"; then
	ok "Объявлен тип command_t с именем команды и её обработчиком"
else
	fail "Нет типа command_t с полями имени и обработчика"
	note "Команда прибора — пара: слово, которое набирает человек, и функция, которая на него отвечает."
fi

# Таблица, показанная memory в п2.1.4, — та же: объявление в заголовке,
# определение с const в одном из файлов проекта.
if grep -Eq 'const[[:space:]]+struct[[:space:]]+command_t[[:space:]]+commands[[:space:]]*\[' "$FLAT"; then
	ok "Таблица команд объявлена с const"
else
	fail "Нет массива commands, объявленного с const"
	note "Без const таблица займёт ОЗУ, которого в микроконтроллере в двадцать раз меньше флеш-памяти."
fi

# Имена команд и их обработчики берём из самой таблицы: важно не как они названы,
# а что у каждой команды есть своя функция.
TABLE="$(sed -n 's/.*struct[[:space:]]\{1,\}command_t[[:space:]]\{1,\}commands[[:space:]]*\[[^{]*{\(.*\)/\1/p' "$FLAT" | sed 's/}[[:space:]]*;.*//')"
NAMES="$(echo "$TABLE" | grep -Eo '"[A-Za-z_][A-Za-z0-9_]*"' | tr -d '"')"
HANDLERS="$(echo "$TABLE" | grep -Eo '"[A-Za-z_][A-Za-z0-9_]*"[[:space:]]*,[[:space:]]*[A-Za-z_][A-Za-z0-9_]*' | sed 's/.*,[[:space:]]*//')"

MISSING=""
for cmd in enable disable info version ping; do
	echo "$NAMES" | grep -qx "$cmd" || MISSING="$MISSING $cmd"
done
if [ -z "$MISSING" ]; then
	ok "В таблице есть команды enable, disable, info, version и ping"
else
	fail "В таблице команд нет:$MISSING"
fi

if [ -n "$HANDLERS" ]; then
	MISSING=""
	WRONG=""
	for handler in $HANDLERS; do
		if grep -Eq "void[[:space:]]+$handler[[:space:]]*\([[:space:]]*void[[:space:]]*\)" "$SOURCES"; then
			continue
		elif grep -Eq "[A-Za-z_][A-Za-z0-9_]*[[:space:]]+$handler[[:space:]]*\(" "$SOURCES"; then
			WRONG="$WRONG $handler"
		else
			MISSING="$MISSING $handler"
		fi
	done
	if [ -z "$MISSING" ] && [ -z "$WRONG" ]; then
		ok "У каждой команды таблицы своя функция-обработчик"
	fi
	if [ -n "$MISSING" ]; then
		fail "В таблице названы обработчики, которых нет в файлах проекта:$MISSING"
	fi
	if [ -n "$WRONG" ]; then
		fail "Обработчики объявлены не как void f(void):$WRONG"
		note "Пустые скобки — это не «без аргументов»: у такой функции другой тип, и в таблицу command_handler_t она попадает по недосмотру компилятора."
	fi
else
	fail "В таблице команд не видно пар «имя — обработчик»"
fi

# Разбор строки ищется в файлах, которые обучающийся завёл сам, а не в SDK и libs.
CODE="$(mktemp)"
cp "$SOURCES" "$CODE"

if grep -Eq 'for[[:space:]]*\(' "$CODE" && grep -Eq 'commands\[[A-Za-z_]' "$CODE"; then
	ok "Разбор команды идёт циклом по таблице"
else
	fail "Разбор команды не ищет имя в таблице циклом"
	note "Обращение commands[i] по переменной — признак того, что таблица перебирается, а не расписана руками."
fi

match "$CODE" 'commands\[[A-Za-z_][A-Za-z0-9_]*\]\.handler[[:space:]]*\(' \
	"Обработчик вызывается по указателю из таблицы" \
	"Обработчик не вызывается по указателю commands[i].handler()"

match "$CODE" '\.handler[[:space:]]*!=[[:space:]]*NULL' \
	"Перед вызовом указатель проверен на NULL" \
	"Обработчик вызывается без проверки на NULL"

if grep -Eq 'strcmp[[:space:]]*\([^)]*commands\[[^]]*\]\.name' "$CODE"; then
	ok "Принятое слово сравнивается с именем из таблицы"
else
	fail "strcmp не сравнивает принятое слово с commands[i].name"
fi

if grep -Eq 'strcmp[[:space:]]*\([^)]*"' "$CODE"; then
	fail "В разборе остались сравнения strcmp с именем команды"
	note "Имена команд живут только в таблице: цепочка сравнений уходит из handle_command целиком."
else
	ok "Имён команд в разборе не осталось — они только в таблице"
fi

match "$CODE" 'unknown command' \
	"На незнакомое слово прибор отвечает ошибкой" \
	"Нет сообщения о незнакомой команде"

CMAKE="$SRC/CMakeLists.txt"
if [ -f "$CMAKE" ]; then
	FLAT_CMAKE="$(cmake_flatten "$CMAKE")"
	# Заголовок ищется из папки проекта; если он лежит в её подпапке,
	# эта подпапка должна быть в путях поиска заголовков.
	HEADER_PATH="$(find "$SRC" -maxdepth 2 -type f -name '*.h' -not -path '*/build/*' 2>/dev/null |
		xargs grep -lE 'struct[[:space:]]+command_t' 2>/dev/null | sort | head -1)"
	HEADER_DIR="$(dirname "${HEADER_PATH:-$SRC/main.c}")"
	if [ "$(cd "$HEADER_DIR" && pwd)" = "$(cd "$SRC" && pwd)" ]; then
		ok "Объявления таблицы лежат рядом с main.c — отдельного пути в сборке не нужно"
	elif grep -Eo 'target_include_directories[[:space:]]*\([^)]*' "$FLAT_CMAKE" | grep -q "$(basename "$HEADER_DIR")"; then
		ok "Папка с заголовком таблицы добавлена в target_include_directories"
	else
		fail "Заголовок таблицы лежит в $(basename "$HEADER_DIR")/, а этой папки нет в путях поиска заголовков"
		note "main.c подключает его как \"$(basename "$HEADER_DIR")/$(basename "${HEADER_PATH:-x.h}")\" — без пути сборка не найдёт файл."
	fi
fi

rm -f "$FLAT" "$SOURCES" "$CODE"

# const в тексте программы — обещание; адрес в собранном образе — его исполнение.
# Имя commands в таблице символов есть не всегда: компилятор вправе не оставлять
# символ у объекта, который целиком разобран по месту. Зато в карте линковки видно
# имя входной секции, и оно зависит от const: с const таблица уходит в .rodata
# (флеш-память), без него — в .data или .bss (ОЗУ).
BUILD_KEEP=1
if build_project "$SRC" && [ -n "${BUILD_ELF:-}" ]; then
	MAP="$(ls "$BUILD_DIR"/*.elf.map 2>/dev/null | head -1)"
	INPUT="$(grep -oE '[.](rodata|srodata|data|bss)[A-Za-z0-9_.]*[.]commands' "$MAP" 2>/dev/null | head -1)"
	case "$INPUT" in
		.rodata*) ok "Таблица команд — секция $INPUT, и лежит она в образе, во флеш-памяти" ;;
		"") fail "В карте линковки не видно, куда легла таблица commands" ;;
		*) fail "Таблица команд легла в секцию ${INPUT#?.} — это ОЗУ, а с const место ей во флеш-памяти"
		   note "Секцию выбирает компилятор: если таблица в ОЗУ, значит const до неё не дошёл." ;;
	esac
fi
[ -n "${BUILD_DIR:-}" ] && rm -rf "$BUILD_DIR"

if device_log "$SRC/device-2-1-2.log" "2.1.2"; then
	RECEIVED="$(device_received "$DEVICE_LOG")"
	SENT="$(device_sent "$DEVICE_LOG")"

	for cmd in enable disable info ping; do
		if echo "$SENT" | grep -qx "$cmd"; then
			ok "Скрипт отправил команду $cmd"
		else
			fail "В логе нет отправленной команды $cmd"
		fi
	done

	if echo "$RECEIVED" | grep -Eq '^pong[[:space:]]*$'; then
		ok "На ping плата ответила pong"
	else
		fail "В логе нет ответа pong на команду ping"
		note "Ради ping пишутся две вещи: функция-обработчик и строка в таблице."
	fi

	if echo "$RECEIVED" | grep -Eq 'led (on|off)'; then
		ok "Прежние команды работают: плата сообщила о состоянии светодиода"
	else
		fail "В логе нет сообщения о состоянии светодиода"
	fi

	if echo "$RECEIVED" | grep -Eq '^project: 211-command-usb'; then
		ok "Прежние команды работают: info печатает паспорт устройства"
	else
		fail "В логе нет строки project: 211-command-usb в ответе на info"
	fi

	if echo "$RECEIVED" | grep -Eq 'unknown command: [a-z]{2,}'; then
		ok "На незнакомое слово плата ответила ошибкой и назвала это слово"
	else
		fail "В логе нет ответа на незнакомую команду"
	fi
fi

finish "$TITLE"
