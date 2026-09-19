#!/usr/bin/env bash
# Задание п2.1.2 «Таблица команд».
# Тип обработчика, массив пар «имя — функция», поиск по нему и вызов по указателю.
# Использование: check-2-1-2.sh <путь к репозиторию> [папка проекта]
set -u

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
. "$LIB/report.sh"
. "$LIB/build.sh"
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
if [ -f "$MAIN" ]; then
	MAIN="$(normalize "$MAIN")"
	# Объявление типа и таблица занимают несколько строк, поэтому часть пунктов
	# читается по файлу со схлопнутыми переводами строк.
	FLAT="$(mktemp)"
	tr '\n' ' ' < "$MAIN" > "$FLAT"

	match "$MAIN" 'typedef[[:space:]]+void[[:space:]]*\([[:space:]]*\*[[:space:]]*command_handler_t[[:space:]]*\)[[:space:]]*\([[:space:]]*void[[:space:]]*\)' \
		"main.c: объявлен тип command_handler_t — указатель на функцию без аргументов" \
		"main.c: нет typedef указателя на функцию command_handler_t"

	if grep -Eq 'struct[[:space:]]+command_t[[:space:]]*\{[^}]*name[^}]*handler[^}]*\}|struct[[:space:]]+command_t[[:space:]]*\{[^}]*handler[^}]*name[^}]*\}' "$FLAT"; then
		ok "main.c: объявлен тип command_t с именем команды и её обработчиком"
	else
		fail "main.c: нет типа command_t с полями имени и обработчика"
		note "Команда прибора — пара: слово, которое набирает человек, и функция, которая на него отвечает."
	fi

	if grep -Eq 'const[[:space:]]+struct[[:space:]]+command_t[[:space:]]+commands[[:space:]]*\[' "$FLAT"; then
		ok "main.c: таблица команд объявлена с const"
	else
		fail "main.c: нет массива commands, объявленного с const"
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
		ok "main.c: в таблице есть команды enable, disable, info, version и ping"
	else
		fail "main.c: в таблице команд нет:$MISSING"
	fi

	if [ -n "$HANDLERS" ]; then
		MISSING=""
		for handler in $HANDLERS; do
			grep -Eq "void[[:space:]]+$handler[[:space:]]*\([[:space:]]*void[[:space:]]*\)" "$MAIN" ||
				MISSING="$MISSING $handler"
		done
		if [ -z "$MISSING" ]; then
			ok "main.c: у каждой команды таблицы своя функция-обработчик"
		else
			fail "main.c: в таблице названы обработчики, которых нет в файле:$MISSING"
		fi
	else
		fail "main.c: в таблице команд не видно пар «имя — обработчик»"
	fi

	if grep -Eq 'for[[:space:]]*\(' "$MAIN" && grep -Eq 'commands\[[A-Za-z_]' "$MAIN"; then
		ok "main.c: разбор команды идёт циклом по таблице"
	else
		fail "main.c: разбор команды не ищет имя в таблице циклом"
		note "Обращение commands[i] по переменной — признак того, что таблица перебирается, а не расписана руками."
	fi

	match "$MAIN" 'commands\[[A-Za-z_][A-Za-z0-9_]*\]\.handler[[:space:]]*\(' \
		"main.c: обработчик вызывается по указателю из таблицы" \
		"main.c: обработчик не вызывается по указателю commands[i].handler()"

	match "$MAIN" '\.handler[[:space:]]*!=[[:space:]]*NULL' \
		"main.c: перед вызовом указатель проверен на NULL" \
		"main.c: обработчик вызывается без проверки на NULL"

	if grep -Eq 'strcmp[[:space:]]*\([^)]*commands\[[^]]*\]\.name' "$MAIN"; then
		ok "main.c: принятое слово сравнивается с именем из таблицы"
	else
		fail "main.c: strcmp не сравнивает принятое слово с commands[i].name"
	fi

	if grep -Eq 'strcmp[[:space:]]*\([^)]*"' "$MAIN"; then
		fail "main.c: в разборе остались сравнения strcmp с именем команды"
		note "Имена команд живут только в таблице: цепочка сравнений уходит из handle_command целиком."
	else
		ok "main.c: имён команд в разборе не осталось — они только в таблице"
	fi

	match "$MAIN" 'unknown command' \
		"main.c: на незнакомое слово прибор отвечает ошибкой" \
		"main.c: нет сообщения о незнакомой команде"

	rm -f "$FLAT"
fi

# const в тексте программы — обещание; секция в собранном образе — его исполнение.
BUILD_KEEP=1
if build_project "$SRC" && [ -n "${BUILD_ELF:-}" ]; then
	SYMBOLS="$(mktemp)"
	if arm-none-eabi-objdump -t "$BUILD_ELF" > "$SYMBOLS" 2>/dev/null; then
		SECTION="$(awk '$NF == "commands" {print $(NF-2)}' "$SYMBOLS" | head -1)"
		case "$SECTION" in
			.rodata*|.text*)
				ok "Таблица команд легла во флеш-память, в секцию $SECTION" ;;
			"")
				fail "Таблицы команд нет в собранном образе под именем commands" ;;
			*)
				fail "Таблица команд легла в секцию $SECTION, а с const место ей во флеш-памяти"
				note "Секцию выбирает компилятор: если таблица в ОЗУ, значит const до неё не дошёл." ;;
		esac
	else
		warn "Не удалось прочитать таблицу символов: нет arm-none-eabi-objdump"
	fi
	rm -f "$SYMBOLS"
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
