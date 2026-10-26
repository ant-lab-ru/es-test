#!/usr/bin/env bash
# Задание п3.1.3 «Телеметрия измерений».
# Проект 311-adc: задача logic/telemetry-task с состояниями IDLE и RUN снимает напряжение
# и температуру с периодом по systime и отдаёт запись функции, переданной при запуске.
# Команды tm_start [<period_ms>] и tm_stop, строка потока tm: <мкс> <В> <°C>.
# Читает код, собирает проект и разбирает лог: период по меткам времени прибора,
# остановку потока, ответы на неверные аргументы.
# Использование: check-3-1-3.sh <путь к репозиторию> [папка проекта]
set -u

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
. "$LIB/report.sh"
. "$LIB/build.sh"
. "$LIB/code.sh"
. "$LIB/cmake.sh"
. "$LIB/device.sh"
. "$LIB/exchange.sh"
. "$LIB/firmware.sh"

fw_start "Задание 3.1.3 — Телеметрия измерений" 311-adc "${1:-.}" "${2:-}"

fw_need TASK_H telemetry-task.h
fw_need TASK_C telemetry-task.c
for f in main.c check-3-1-3.py device-3-1-3.log; do
	if [ -f "$FW_SRC/$f" ]; then
		ok "Файл $f на месте"
	else
		fail "В проекте нет файла $f"
	fi
done

if [ -n "$TASK_H" ] && [ -n "$TASK_C" ]; then
	BOTH="$(mktemp)"
	cat "$(fw_code "$TASK_H")" "$(fw_code "$TASK_C")" > "$BOTH"
	if grep -Eq 'IDLE' "$BOTH" && grep -Eq 'RUN' "$BOTH"; then
		ok "telemetry-task: у задачи состояния IDLE и RUN"
	else
		fail "telemetry-task: не видно состояний IDLE и RUN"
		note "Состояние задачи — значение перечисления, как у задачи светодиода в п2.3.2."
	fi
	match "$BOTH" 'systime_period_elapsed[[:space:]]*\(' \
		"telemetry-task: период отмеряет systime_period_elapsed()" \
		"telemetry-task: период не отмеряется функцией systime_period_elapsed()"
	if grep -Eq 'printf|puts[[:space:]]*\(|putchar' "$(fw_code "$TASK_C")"; then
		fail "telemetry-task.c: задача печатает сама"
		note "Модули возвращают данные и не печатают (правило П3). Запись задача отдаёт функции, переданной при запуске."
	else
		ok "telemetry-task.c: задача не печатает, запись отдаёт функции"
	fi
	if grep -Eq '\(\*[[:space:]]*[a-z_]+\)[[:space:]]*\(' "$(fw_code "$TASK_H")"; then
		ok "telemetry-task.h: объявлен тип функции, которой задача отдаёт запись"
	else
		fail "telemetry-task.h: нет типа указателя на функцию для записи"
		note "Как у задачи кнопки: typedef void (*…_callback_t)(…), функция передаётся при запуске."
	fi
fi

MAIN="$FW_SRC/main.c"
if [ -f "$MAIN" ]; then
	CODE="$(fw_code "$MAIN")"
	match "$CODE" 'telemetry_task_init[[:space:]]*\([[:space:]]*[a-z_]+' \
		"main.c: задаче телеметрии при запуске передана функция для записей" \
		"main.c: telemetry_task_init() не получает функцию для записей"
	match "$CODE" 'telemetry_task_handle[[:space:]]*\(' \
		"main.c: обработчик задачи телеметрии вызывается в суперцикле" \
		"main.c: нет вызова telemetry_task_handle()"
fi

CMAKE="$FW_SRC/CMakeLists.txt"
if [ -f "$CMAKE" ]; then
	FLAT="$(cmake_flatten "$CMAKE")"
	match "$FLAT" 'add_library[[:space:]]*\([[:space:]]*logic[[:space:]][^)]*telemetry-task\.c' \
		"CMakeLists.txt: telemetry-task.c собирается в библиотеке logic" \
		"CMakeLists.txt: telemetry-task.c не добавлен в библиотеку logic"
fi

LOGIC="$(mktemp)"
find "$FW_SRC/logic" -type f \( -name '*.c' -o -name '*.h' \) 2>/dev/null | sort |
	while read -r f; do cat "$(fw_code "$f")"; done > "$LOGIC"
if grep -Eq '#include[[:space:]]*[<"](pico|hardware)/|time_us_|adc_[a-z_]+[[:space:]]*\(' "$LOGIC"; then
	fail "logic: код логики обращается к SDK"
	note "Время — через systime, измерения — через platform."
else
	ok "logic: задача телеметрии работает без SDK"
fi

build_project "$FW_SRC"

if device_log "$FW_SRC/device-3-1-3.log" "3.1.3"; then
	TABLE="$(exchange_table "$DEVICE_LOG")"
	reply() {
		exchange_replies "$TABLE" "$1" "$2" | cut -f2 | tail -n +2
	}
	# answers <команда> <вызов> — ответы на вызов без строк потока
	answers() {
		reply "$1" "$2" | grep -v '^tm: '
	}
	# stream <команда> <вызов> — строки потока в ответах на вызов
	stream() {
		reply "$1" "$2" | grep '^tm: '
	}
	# after_reply <команда> <вызов> <ответ> — строки потока после ответа команды
	after_reply() {
		reply "$1" "$2" | awk -v answer="$3" 'seen && /^tm: / { print } index($0, answer) == 1 { seen = 1 }'
	}
	# period_check <строки потока> <период, мкс> <подпись>
	period_check() {
		local lines="$1" period="$2" label="$3"
		local bad count stats
		bad="$(echo "$lines" | grep -Ev '^tm: [0-9]+ [0-9]+\.[0-9]{3} -?[0-9]+\.[0-9]$' | head -1)"
		count="$(echo "$lines" | grep -c '^tm: ')"
		if [ -n "$bad" ]; then
			fail "$label: строка не по формату: $bad"
			note "Строка потока — tm: <время, мкс> <напряжение, В, 3 знака> <температура, °C, 1 знак>."
			return
		fi
		if [ "$count" -lt 5 ]; then
			fail "$label: строк потока ${count}, слишком мало"
			note "Задача должна отдавать запись раз в период, пока телеметрия не остановлена."
			return
		fi
		stats="$(echo "$lines" | awk -v p="$period" '
			{ t = $2 }
			n > 0 { d = t - last; if (d <= 0) back++; sum += d; dev = d - p; if (dev < 0) dev = -dev; if (dev > max) max = dev }
			{ last = t; n++ }
			END { printf "%d %.0f %.0f", back + 0, sum / (n - 1), max }')"
		set -- $stats
		if [ "$1" -gt 0 ]; then
			fail "$label: время в строках не растёт"
			note "Время — показание часов прибора в момент отсчёта, systime_us()."
		elif awk -v m="$2" -v p="$period" 'BEGIN { exit !(m >= p * 0.98 && m <= p * 1.02) }'; then
			ok "$label: строк потока ${count}, средний шаг $2 мкс при периоде $period мкс"
		else
			fail "$label: средний шаг между строками $2 мкс, а период $period мкс"
			note "Следующая метка отсчитывается от прошлой, как у задачи светодиода: systime_period_elapsed()."
		fi
		[ "$1" -eq 0 ] && [ "$3" -gt $((period / 5)) ] && warn "$label: отдельный шаг отклонился от периода на $3 мкс"
		if echo "$lines" | awk '{ if ($3 < 0 || $3 > 3.4 || $4 < 10 || $4 > 50) bad++ } END { exit bad > 0 }'; then
			ok "$label: напряжение от 0 до 3,3 В, температура от 10 до 50 °C"
		else
			fail "$label: значения в строках вне пределов"
			note "Напряжение берётся у platform_voltage_read(), температура у platform_temp_read()."
		fi
	}

	HELP="$(reply help 1)"
	if echo "$HELP" | grep -Eq '^tm_start[[:space:]]+[^[:space:]]' && echo "$HELP" | grep -Eq '^tm_stop[[:space:]]+[^[:space:]]'; then
		ok "help перечисляет tm_start и tm_stop со справкой"
	else
		fail "В ответе help нет tm_start или tm_stop со справкой"
	fi

	if answers tm_start 1 | grep -Eq '^telemetry: started, period 50 ms$'; then
		ok "tm_start 50 отвечает telemetry: started, period 50 ms"
	else
		fail "Ответ на tm_start 50 не telemetry: started, period 50 ms"
	fi
	period_check "$(stream tm_start 1)" 50000 "Телеметрия с периодом 50 мс"

	if answers tm_stop 1 | grep -Eq '^telemetry: stopped$'; then
		ok "tm_stop отвечает telemetry: stopped"
	else
		fail "Ответ на tm_stop не telemetry: stopped"
	fi
	if [ -z "$(after_reply tm_stop 1 'telemetry: stopped')" ]; then
		ok "После ответа tm_stop строки потока больше не приходят"
	else
		fail "После ответа tm_stop пришли строки потока"
		note "tm_stop переводит задачу в IDLE, и в этом состоянии обработчик ничего не снимает."
	fi

	if answers tm_start 2 | grep -Eq '^telemetry: started, period 100 ms$'; then
		ok "tm_start без аргумента запускает телеметрию с периодом 100 мс"
	else
		fail "tm_start без аргумента не ответил telemetry: started, period 100 ms"
		note "Период по умолчанию — 100 мс."
	fi
	period_check "$(stream tm_start 2)" 100000 "Телеметрия с периодом по умолчанию"

	if answers tm_start 3 | grep -Eq '^error: period_ms must be at least 10$'; then
		ok "tm_start 5 отклонён: error: period_ms must be at least 10"
	else
		fail "На tm_start 5 нет ответа error: period_ms must be at least 10"
	fi
	if answers tm_start 4 | grep -Eq '^error: usage tm_start \[<period_ms>\]$' &&
		answers tm_start 5 | grep -Eq '^error: usage tm_start \[<period_ms>\]$'; then
		ok "tm_start с двумя аргументами и с 5x отклонён: error: usage tm_start [<period_ms>]"
	else
		fail "tm_start 10 20 или tm_start 5x не ответил error: usage tm_start [<period_ms>]"
		note "Ошибка в записи аргументов — по общим правилам приложения Б ТЗ 2.3."
	fi
	LEAK=""
	for n in 3 4 5; do
		[ -n "$(stream tm_start "$n")" ] && LEAK="yes"
	done
	if [ -z "$LEAK" ]; then
		ok "Отклонённый tm_start телеметрию не запускает"
	else
		fail "После отклонённого tm_start пошли строки потока"
		note "Команда с ошибкой ничего не меняет."
	fi

	if answers get_voltage 1 | grep -Eq '^voltage: [0-9]+\.[0-9]{3} V$'; then
		ok "После телеметрии get_voltage по-прежнему отвечает напряжением"
	else
		fail "После телеметрии get_voltage не ответил напряжением"
	fi
fi

finish "$TITLE"
