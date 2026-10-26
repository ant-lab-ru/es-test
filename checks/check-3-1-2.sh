#!/usr/bin/env bash
# Задание п3.1.2 «Измерение температуры».
# Проект 311-adc: модуль platform включает датчик температуры и переводит напряжение
# на нём в градусы по формуле RP2040 Datasheet, команда get_temp отвечает температурой
# кристалла. Читает код, собирает проект и разбирает лог прогона на плате.
# Использование: check-3-1-2.sh <путь к репозиторию> [папка проекта]
set -u

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
. "$LIB/report.sh"
. "$LIB/build.sh"
. "$LIB/code.sh"
. "$LIB/device.sh"
. "$LIB/exchange.sh"
. "$LIB/firmware.sh"

fw_start "Задание 3.1.2 — Измерение температуры" 311-adc "${1:-.}" "${2:-}"

for f in platform/platform.c logic/api/api-callbacks.c check-3-1-2.py device-3-1-2.log; do
	if [ -f "$FW_SRC/$f" ]; then
		ok "Файл $f на месте"
	else
		fail "В проекте нет файла $f"
	fi
done

PLATFORM_C="$FW_SRC/platform/platform.c"
if [ -f "$PLATFORM_C" ]; then
	CODE="$(fw_code "$PLATFORM_C")"
	if grep -Eq 'adc_set_temp_sensor_enabled[[:space:]]*\([[:space:]]*true|TS_EN' "$CODE"; then
		ok "platform.c: датчик температуры включён"
	else
		fail "platform.c: не видно включения датчика температуры"
		note "Питание датчика включают отдельно от АЦП: adc_set_temp_sensor_enabled(true)."
	fi
	if grep -Eq 'adc_select_input[[:space:]]*\([[:space:]]*(4|[A-Z_]*TEMP[A-Z_]*)[[:space:]]*\)' "$CODE"; then
		ok "platform.c: для температуры выбирается канал 4"
	else
		fail "platform.c: не видно выбора канала 4 для датчика температуры"
		note "Датчик подключён к пятому входу мультиплексора, AINSEL = 4 (RP2040 Datasheet, 4.9.2.1)."
	fi
	if grep -Eq '0\.706' "$CODE" && grep -Eq '0\.001721|1\.721' "$CODE"; then
		ok "platform.c: напряжение переводится в градусы по формуле раздела 4.9.5"
	else
		fail "platform.c: не видно формулы датчика с 0,706 В и наклоном 1,721 мВ на градус"
		note "T = 27 − (U − 0,706) / 0,001721, где U — напряжение на датчике в вольтах."
	fi
fi

LOGIC="$(mktemp)"
find "$FW_SRC/logic" -type f \( -name '*.c' -o -name '*.h' \) 2>/dev/null | sort |
	while read -r f; do cat "$(fw_code "$f")"; done > "$LOGIC"
if grep -Eq '#include[[:space:]]*[<"](pico|hardware)/|adc_[a-z_]+[[:space:]]*\(|0\.706' "$LOGIC"; then
	fail "logic: перевод в градусы или обращение к АЦП — в логике"
	note "Формула датчика — знание о железе, она живёт в platform (правило П13 ТЗ 2.3)."
else
	ok "logic: температуру логика получает у platform готовой"
fi
if grep -Eq '"get_temp"' "$LOGIC"; then
	ok "api-callbacks.c: команда get_temp есть в таблице команд"
else
	fail "В таблице команд нет get_temp"
fi

build_project "$FW_SRC"

if device_log "$FW_SRC/device-3-1-2.log" "3.1.2"; then
	TABLE="$(exchange_table "$DEVICE_LOG")"
	reply() {
		exchange_replies "$TABLE" "$1" "$2" | cut -f2 | tail -n +2
	}

	CALLS="$(exchange_calls "$DEVICE_LOG" get_temp)"
	VALUES=""
	for n in $(seq 1 "$CALLS"); do
		ANSWER="$(reply get_temp "$n" | head -1)"
		if echo "$ANSWER" | grep -Eq '^temp: -?[0-9]+\.[0-9] C$'; then
			VALUES="$VALUES $(echo "$ANSWER" | awk '{ print $2 }')"
		else
			fail "Ответ get_temp не по формату: $ANSWER"
			note "Ответ — temp: <температура> C, один знак после точки, например temp: 27.4 C."
		fi
	done
	if [ "$CALLS" -lt 3 ]; then
		fail "В логе меньше трёх вызовов get_temp"
		note "Лог снимается скриптом check-3-1-2.py без правок."
	elif [ -n "$VALUES" ]; then
		RANGE="$(echo "$VALUES" | tr ' ' '\n' | awk 'NF { if (min == "" || $1 < min) min = $1; if (max == "" || $1 > max) max = $1 } END { print min, max }')"
		MIN="${RANGE% *}"
		MAX="${RANGE#* }"
		if awk -v a="$MIN" -v b="$MAX" 'BEGIN { exit !(a >= 10 && b <= 50) }'; then
			ok "get_temp: температура кристалла от $MIN до $MAX °C, в пределах 10–50 °C"
		else
			fail "get_temp: температура от $MIN до $MAX °C вне пределов 10–50 °C"
			note "Проверьте канал 4 и формулу. Кристалл в комнате теплее воздуха на несколько градусов, но не на десятки."
		fi
		if awk -v a="$MIN" -v b="$MAX" 'BEGIN { exit !(b - a <= 3) }'; then
			ok "get_temp: три замера подряд расходятся не больше чем на 3 °C"
		else
			fail "get_temp: замеры подряд расходятся: от ${MIN} до ${MAX} °C"
			note "За три секунды кристалл так не нагревается. Похоже, читается не тот канал."
		fi
	fi

	if reply get_voltage 1 | grep -Eq '^voltage: [0-9]+\.[0-9]{3} V$'; then
		ok "После get_temp команда get_voltage по-прежнему отвечает напряжением"
	else
		fail "После get_temp get_voltage не ответил напряжением"
		note "Каждое измерение выбирает свой канал перед отсчётом: adc_select_input() в обеих функциях."
	fi
fi

finish "$TITLE"
