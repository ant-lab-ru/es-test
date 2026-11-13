#!/usr/bin/env bash
# Задание п3.3.3 «Два модуля и допуск скорости».
# UART1 на GP8 и GP9, провода перекрёстно: GP0 — GP9 и GP8 — GP1. Команда link <строка>
# гонит строку из UART0 в UART1 и обратно, baud_shift <процент> смещает скорость UART1
# и печатает настоящую скорость, text передаёт 32 символа из UART1 в UART0, parity <rx> <tx>
# задаёт чётность. Скорость и формат меняет только platform.
# Читает код, собирает проект и разбирает лог: link без ошибок, text при смещении
# 0, +2 и −2 % без ошибок, при −10 % другой текст и FE, при разной чётности PE.
# Использование: check-3-3-3.sh <путь к репозиторию> [папка проекта]
set -u

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
. "$LIB/report.sh"
. "$LIB/build.sh"
. "$LIB/code.sh"
. "$LIB/cmake.sh"
. "$LIB/device.sh"
. "$LIB/exchange.sh"
. "$LIB/firmware.sh"

fw_start "Задание 3.3.3 — Два модуля и допуск скорости" 331-uart "${1:-.}" "${2:-}"

fw_need PLATFORM_C platform.c
for f in check-3-3-3.py device-3-3-3.log; do
	if [ -f "$FW_SRC/$f" ]; then
		ok "Файл $f на месте"
	else
		file_missing "$f"
	fi
done

if [ -n "$PLATFORM_C" ]; then
	PLAT="$(fw_code "$PLATFORM_C")"
	if grep -Eq 'uart_init[[:space:]]*\([[:space:]]*uart1[[:space:]]*,' "$PLAT" && grep -Eq '115200' "$PLAT"; then
		ok "platform.c: UART1 настроен uart_init() на 115 200 бит/с"
	else
		fail "platform.c: нет uart_init(uart1, …) или скорости 115200"
	fi
	if grep -Eq '(^|[^0-9])8([^0-9]|$)' "$PLAT" && grep -Eq '(^|[^0-9])9([^0-9]|$)' "$PLAT"; then
		ok "platform.c: в коде есть выводы 8 и 9 для UART1"
	else
		fail "platform.c: нет выводов 8 и 9 для UART1"
		note "UART1 работает на GP8 (TX) и GP9 (RX): GP4 и GP5 оставлены под I²C."
	fi
	match "$PLAT" 'uart_set_baudrate[[:space:]]*\(' \
		"platform.c: скорость меняет uart_set_baudrate()" \
		"platform.c: нет вызова uart_set_baudrate()"
	match "$PLAT" 'uart_set_format[[:space:]]*\(' \
		"platform.c: чётность меняет uart_set_format()" \
		"platform.c: нет вызова uart_set_format()"
fi

LOGIC="$(mktemp)"
find "$FW_SRC/logic" -type f \( -name '*.c' -o -name '*.h' \) 2>/dev/null | sort |
	while read -r f; do cat "$(fw_code "$f")"; done > "$LOGIC"
if grep -Eq '#include[[:space:]]*[<"](pico|hardware)/|(^|[^a-z_])uart_(init|set_[a-z_]+|is_[a-z_]+|get_hw)[[:space:]]*\(' "$LOGIC"; then
	fail "logic: код логики обращается к SDK"
	note "Скорость и формат UART — железо, им место в platform."
else
	ok "logic: логика по-прежнему без SDK"
fi

build_project "$FW_SRC"

if device_log "$FW_SRC/device-3-3-3.log" "3.3.3"; then
	TABLE="$(exchange_table "$DEVICE_LOG")"
	reply() {
		exchange_replies "$TABLE" "$1" "$2" | cut -f2 | tail -n +2
	}
	S='[[:space:]]+'
	LINE32='0123456789ABCDEFGHIJKLMNOPQRSTUV'

	for c in link baud_shift text parity; do
		if ! reply help 1 | grep -Eq "^$c[[:space:]]+[^[:space:]]"; then
			MISSING="${MISSING:-} $c"
		fi
	done
	if [ -z "${MISSING:-}" ]; then
		ok "help перечисляет link, baud_shift, text и parity со справкой"
	else
		fail "В ответе help нет со справкой:$MISSING"
	fi

	LINK="$(reply link 1)"
	if echo "$LINK" | grep -Eq "^0->1:${S}ping${S}err:${S}none$" && echo "$LINK" | grep -Eq "^1->0:${S}ping${S}err:${S}none$"; then
		ok "link ping прошёл в обе стороны без ошибок"
	else
		fail "link ping не вернул 0->1: ping err: none и 1->0: ping err: none"
		note "Проверьте провода GP0 — GP9 и GP8 — GP1 и то, что перемычки GP0 — GP1 больше нет."
	fi

	# ответы baud_shift: настоящая скорость в пределах 0,5 % от расчёта
	BAD=""
	n=$(exchange_calls "$DEVICE_LOG" baud_shift)
	for i in $(seq 1 "$n"); do
		arg="$(awk -v nth="$i" '/-->/ && $3 == "baud_shift" { seen++; if (seen == nth) { print $4; exit } }' "$DEVICE_LOG")"
		answer="$(reply baud_shift "$i" | head -1)"
		if [ "$arg" -lt -50 ] 2>/dev/null || [ "$arg" -gt 50 ] 2>/dev/null; then
			echo "$answer" | grep -Eq '^error: percent must be -50\.\.50$' || BAD="$BAD $arg"
			continue
		fi
		baud="$(echo "$answer" | sed -nE 's/^baud_shift:[[:space:]]+uart1[[:space:]]+([0-9]+)[[:space:]]+baud$/\1/p')"
		if [ -z "$baud" ] || ! awk -v b="$baud" -v p="$arg" 'BEGIN { e = 115200 * (100 + p) / 100; d = (b - e) / e; exit !(d < 0.005 && d > -0.005) }'; then
			BAD="$BAD $arg"
		fi
	done
	if [ "$n" -gt 0 ] && [ -z "$BAD" ]; then
		ok "baud_shift отвечает настоящей скоростью UART1 в формате baud_shift: uart1 <скорость> baud"
	else
		fail "Ответ baud_shift не baud_shift: uart1 <скорость> baud или скорость не та при смещении:${BAD:- нет вызовов}"
		note "Скорость — 115 200 · (1 + p/100). Печатается то, что вернула uart_set_baudrate(), а не расчёт."
	fi

	# строки text: смещение скорости, чётность UART0 и UART1, ответ
	TEXTS="$(awk '
		/-->/ {
			text = 0
			if ($3 == "baud_shift") shift = $4
			if ($3 == "parity" && NF == 5) parity = $4 "/" $5
			if ($3 == "text") text = 1
			next
		}
		/<--/ && text && index($0, "<-- text:") {
			print shift "\t" parity "\t" substr($0, index($0, "<-- ") + 4)
		}
	' "$DEVICE_LOG")"

	# text_clean <смещение> <чётность rx/tx> <подпись> <подсказка> [head|tail] — первый
	# или последний ответ text при таком смещении и чётности
	text_clean() {
		local answer
		answer="$(echo "$TEXTS" | awk -F '\t' -v s="$1" -v p="$2" '$1 == s && $2 == p { print $3 }' | "${5:-head}" -1)"
		if echo "$answer" | grep -Eq "^text:${S}32${S}chars${S}$LINE32${S}err:${S}none$"; then
			ok "$3: строка из 32 символов пришла целиком, ошибок нет"
		else
			fail "$3: ответ не text: 32 chars $LINE32 err: none${answer:+ — пришло «${answer}»}"
			note "$4"
		fi
	}
	text_clean 0 none/none "Скорости равны" "32 символа помещаются в очередь приёма UART0. Если их меньше, принятое читается раньше конца передачи."
	text_clean 2 none/none "UART1 быстрее на 2 %" "Смещение 2 % в пределах допуска около 5 % (т3.3.3). Проверьте, что baud_shift меняет скорость только UART1."
	text_clean -2 none/none "UART1 медленнее на 2 %" "Смещение 2 % в пределах допуска около 5 % (т3.3.3). Проверьте, что baud_shift меняет скорость только UART1."

	answer="$(echo "$TEXTS" | awk -F '\t' '$1 == "-10" && $2 == "none/none" { print $3; exit }')"
	if [ -n "$answer" ] && ! echo "$answer" | grep -Eq "^text:${S}32${S}chars${S}$LINE32${S}" && echo "$answer" | grep -Eq "err:.*FE"; then
		ok "UART1 медленнее на 10 %: текст другой, признак ошибки кадра FE"
	else
		fail "UART1 медленнее на 10 %: ответ без FE или текст не изменился${answer:+ — пришло «${answer}»}"
		note "На 10 % медленнее приёмник читает стоп-бит в старшем бите данных, у символов ASCII это ноль. Признаки читаются из UARTRSR за всю строку."
	fi

	answer="$(echo "$TEXTS" | awk -F '\t' '$1 == "0" && $2 == "even/odd" { print $3; exit }')"
	if echo "$answer" | grep -Eq "err:.*PE"; then
		ok "Чётность even против odd: признак ошибки чётности PE"
	else
		fail "Чётность even против odd: в ответе text нет PE${answer:+ — пришло «${answer}»}"
		note "parity <rx> <tx> задаёт чётность UART0 и UART1 через uart_set_format(). Скорость перед этим возвращают baud_shift 0."
	fi

	text_clean 0 none/none "Скорость и чётность возвращены" "После parity none none обмен снова должен идти без ошибок." tail
	if reply parity "$(exchange_calls "$DEVICE_LOG" parity)" | grep -Eq '^error: usage parity '; then
		ok "parity с одним аргументом отклонён: error: usage parity …"
	else
		fail "parity с одним аргументом не ответил error: usage parity …"
	fi
fi

finish "$TITLE"
