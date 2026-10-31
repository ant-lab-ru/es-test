#!/usr/bin/env bash
# Задание п3.2.2 «Захват по таймеру».
# Отсчёты GP26 снимает обработчик будильника SDK с заданным периодом. Команды
# cap_start <N> <period_us> и cap_dump; cap_dump первой строкой сообщает разброс интервалов
# и долю времени ядра в обработчике, дальше отсчёты строками cap: по 16.
# Читает код, собирает проект и разбирает лог захватов с периодом 125 и 23 мкс.
# Использование: check-3-2-2.sh <путь к репозиторию> [папка проекта]
set -u

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
. "$LIB/report.sh"
. "$LIB/build.sh"
. "$LIB/code.sh"
. "$LIB/cmake.sh"
. "$LIB/device.sh"
. "$LIB/exchange.sh"
. "$LIB/firmware.sh"
. "$LIB/handlers.sh"

fw_start "Задание 3.2.2 — Захват по таймеру" 321-audio-recorder "${1:-.}" "${2:-}"

fw_need PLATFORM_C platform.c
for f in check-3-2-2.py device-3-2-2.log; do
	if [ -f "$FW_SRC/$f" ]; then
		ok "Файл $f на месте"
	else
		fail "В проекте нет файла $f"
	fi
done

if [ -n "$PLATFORM_C" ]; then
	PLAT="$(fw_code "$PLATFORM_C")"
	match "$PLAT" 'add_repeating_timer_us[[:space:]]*\(' \
		"platform.c: захват запускает будильник add_repeating_timer_us()" \
		"platform.c: нет вызова add_repeating_timer_us()"
	BODIES="$(mktemp)"
	handler_bodies "$PLAT" > "$BODIES"
	if grep -Eq 'adc_read[[:space:]]*\(' "$BODIES"; then
		ok "Отсчёт снимает обработчик будильника: adc_read() в обработчике"
	else
		fail "В обработчиках будильников нет adc_read()"
		note "Захват по таймеру — отсчёт в самом обработчике, в момент срабатывания будильника."
	fi
	if grep -Eq 'printf|puts[[:space:]]*\(|putchar|sleep_|busy_wait' "$BODIES"; then
		fail "Обработчик будильника печатает или ждёт"
		note "Отсчёты печатает команда cap_dump, обработчик только снимает их."
	else
		ok "Обработчики будильников не печатают и не ждут"
	fi
fi

LOGIC="$(mktemp)"
find "$FW_SRC/logic" -type f \( -name '*.c' -o -name '*.h' \) 2>/dev/null | sort |
	while read -r f; do cat "$(fw_code "$f")"; done > "$LOGIC"
if grep -Eq '#include[[:space:]]*[<"](pico|hardware)/|(^|[^a-z_])(adc|dma)_[a-z_]+[[:space:]]*\(|time_us_' "$LOGIC"; then
	fail "logic: код логики обращается к SDK"
	note "АЦП, DMA и будильники — железо, им место в platform."
else
	ok "logic: логика по-прежнему без SDK"
fi

build_project "$FW_SRC"

if device_log "$FW_SRC/device-3-2-2.log" "3.2.2"; then
	TABLE="$(exchange_table "$DEVICE_LOG")"
	reply() {
		exchange_replies "$TABLE" "$1" "$2" | cut -f2 | tail -n +2
	}
	# dump_check <номер вызова cap_dump> <N> <период, мкс> <наибольший допустимый разброс, мкс>
	dump_check() {
		local lines head count bad
		lines="$(reply cap_dump "$1")"
		head="$(echo "$lines" | grep -E '^capture: [0-9]+ samples, period [0-9]+ us, interval [0-9]+\.\.[0-9]+ us, handler [0-9]+\.[0-9] %$')"
		if [ -z "$head" ]; then
			fail "cap_dump после захвата $2 отсчётов по $3 мкс: нет строки capture: … interval … handler …"
			note "Первая строка — capture: <N> samples, period <мкс> us, interval <мин>..<макс> us, handler <доля> %."
			return
		fi
		set -- "$@" $(echo "$head" | sed -E 's/capture: ([0-9]+) samples, period ([0-9]+) us, interval ([0-9]+)\.\.([0-9]+) us, handler ([0-9.]+) %/\1 \2 \3 \4 \5/')
		if [ "$5" -eq "$2" ] && [ "$6" -eq "$3" ]; then
			ok "cap_dump: $5 отсчётов с периодом $6 мкс, интервалы $7..$8 мкс, обработчик $9 %"
		else
			fail "cap_dump: в строке capture $5 отсчётов с периодом $6 мкс, а захват был $2 по $3 мкс"
		fi
		if [ "$7" -le "$3" ] && [ "$8" -ge "$3" ] && [ $(($8 - $7)) -le "$4" ]; then
			ok "Интервалы $7..$8 мкс окружают период $3 мкс"
		else
			fail "Интервалы $7..$8 мкс при периоде $3 мкс"
			note "Интервал — разница времён соседних отсчётов, time_us_32() в обработчике. Период со знаком минус ставит вызовы на ровную сетку."
		fi
		count="$(echo "$lines" | grep -E '^cap:' | sed 's/^cap://' | wc -w | tr -d ' ')"
		bad="$(echo "$lines" | grep -E '^cap:' | sed 's/^cap://' | tr ' ' '\n' | grep -Ev '^[0-9]*$' | head -1)"
		if [ "$count" -eq "$2" ] && [ -z "$bad" ] && echo "$lines" | grep -E '^cap:' | sed 's/^cap://' | tr ' ' '\n' | awk 'NF && ($1 > 4095) { exit 1 }'; then
			ok "cap_dump вывел $count отсчётов от 0 до 4095"
		else
			fail "cap_dump вывел $count отсчётов, а захвачено $2, или в строках cap: не коды АЦП"
			note "Отсчёты — строками cap: по 16 кодов через пробел."
		fi
	}

	HELP="$(reply help 1)"
	if echo "$HELP" | grep -Eq '^cap_start[[:space:]]+[^[:space:]]' && echo "$HELP" | grep -Eq '^cap_dump[[:space:]]+[^[:space:]]'; then
		ok "help перечисляет cap_start и cap_dump со справкой"
	else
		fail "В ответе help нет cap_start или cap_dump со справкой"
	fi
	if reply cap_start 1 | grep -Eq '^capture: started, 1000 samples, period 125 us$'; then
		ok "cap_start 1000 125 отвечает capture: started, 1000 samples, period 125 us"
	else
		fail "Ответ на cap_start 1000 125 не capture: started, 1000 samples, period 125 us"
	fi
	dump_check 1 1000 125 40
	dump_check 2 2000 23 200
	if reply cap_start 3 | grep -Eq '^error: N must be 1\.\.2000, period_us at least 10$'; then
		ok "cap_start 0 125 отклонён"
	else
		fail "На cap_start 0 125 нет ответа error: N must be 1..2000, period_us at least 10"
	fi
	if reply cap_start 4 | grep -Eq '^error: usage cap_start <N> <period_us>$'; then
		ok "cap_start с одним аргументом отклонён: error: usage cap_start <N> <period_us>"
	else
		fail "cap_start 1000 не ответил error: usage cap_start <N> <period_us>"
	fi
fi

finish "$TITLE"
