#!/usr/bin/env bash
# Задание п3.2.1 «Индикатор записи».
# Проект 321-audio-recorder, копия 311-adc: светодиод мигает по будильнику SDK
# (add_repeating_timer_ms), команды timer_blink_start <period_ms> и timer_blink_stop,
# ответ на остановку сообщает число переключений. Протокол работает во время мигания.
# Читает код, собирает проект и разбирает лог: число переключений против периода
# и времени между командами, ответы во время мигания, ошибки аргументов.
# Использование: check-3-2-1.sh <путь к репозиторию> [папка проекта]
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

fw_start "Задание 3.2.1 — Индикатор записи" 321-audio-recorder "${1:-.}" "${2:-}"

fw_need PLATFORM_C platform.c
for f in main.c check-3-2-1.py device-3-2-1.log; do
	if [ -f "$FW_SRC/$f" ]; then
		ok "Файл $f на месте"
	else
		fail "В проекте нет файла $f"
	fi
done

CMAKE="$FW_SRC/CMakeLists.txt"
if [ -f "$CMAKE" ]; then
	match "$(cmake_flatten "$CMAKE")" 'project[[:space:]]*\([[:space:]]*321_audio_recorder[[:space:]]*\)' \
		"CMakeLists.txt: проект назван 321_audio_recorder" \
		"CMakeLists.txt: в project() не 321_audio_recorder"
fi

if [ -n "$PLATFORM_C" ]; then
	PLAT="$(fw_code "$PLATFORM_C")"
	match "$PLAT" 'add_repeating_timer_ms[[:space:]]*\(' \
		"platform.c: мигание запускает будильник add_repeating_timer_ms()" \
		"platform.c: нет вызова add_repeating_timer_ms()"
	match "$PLAT" 'cancel_repeating_timer[[:space:]]*\(' \
		"platform.c: остановка снимает будильник cancel_repeating_timer()" \
		"platform.c: нет вызова cancel_repeating_timer()"
	BODIES="$(mktemp)"
	handler_bodies "$PLAT" > "$BODIES"
	if [ ! -s "$BODIES" ]; then
		fail "platform.c: не найден обработчик будильника"
		note "Обработчик — функция, которую получает add_repeating_timer_ms(): bool имя(repeating_timer_t *timer)."
	elif grep -Eq 'printf|puts[[:space:]]*\(|putchar|sleep_|busy_wait' "$BODIES"; then
		fail "Обработчик будильника печатает или ждёт"
		note "Пока идёт обработчик, прошивка стоит, а printf() из обработчика теряется (т3.2.4)."
	else
		ok "Обработчик будильника не печатает и не ждёт"
	fi
	if grep -Eq 'volatile' "$PLAT"; then
		ok "platform.c: переменные, общие с обработчиком, объявлены volatile"
	else
		fail "platform.c: нет volatile"
		note "Счётчик переключений меняет обработчик, а читает команда — такая переменная объявляется volatile."
	fi
fi

LOGIC="$(mktemp)"
find "$FW_SRC/logic" -type f \( -name '*.c' -o -name '*.h' \) 2>/dev/null | sort |
	while read -r f; do cat "$(fw_code "$f")"; done > "$LOGIC"
if grep -Eq '#include[[:space:]]*[<"](pico|hardware)/|add_repeating_timer|time_us_' "$LOGIC"; then
	fail "logic: код логики обращается к SDK"
	note "Будильник — железо, ему место в platform. Команды зовут функции platform."
else
	ok "logic: логика по-прежнему без SDK"
fi

build_project "$FW_SRC"

if device_log "$FW_SRC/device-3-2-1.log" "3.2.1"; then
	TABLE="$(exchange_table "$DEVICE_LOG")"
	reply() {
		exchange_replies "$TABLE" "$1" "$2" | cut -f2 | tail -n +2
	}

	if grep -Eq '^[[:space:]]*[0-9.]+ <-- project: 321-audio-recorder$' "$DEVICE_LOG"; then
		ok "Паспорт прибора называет проект 321-audio-recorder"
	else
		fail "В ответе info нет project: 321-audio-recorder"
		note "Имя проекта задаёт FIRMWARE_PROJECT в firmware.h."
	fi

	HELP="$(reply help 1)"
	if echo "$HELP" | grep -Eq '^timer_blink_start[[:space:]]+[^[:space:]]' && echo "$HELP" | grep -Eq '^timer_blink_stop[[:space:]]+[^[:space:]]'; then
		ok "help перечисляет timer_blink_start и timer_blink_stop со справкой"
	else
		fail "В ответе help нет timer_blink_start или timer_blink_stop со справкой"
	fi

	# toggles <номер вызова start> <номер вызова stop> <период, мс> <подпись>
	toggles() {
		local start stop answer n t0 t1
		answer="$(reply timer_blink_stop "$2" | grep -E '^timer_blink: stopped, [0-9]+ toggles$')"
		if [ -z "$answer" ]; then
			fail "$4: ответ на timer_blink_stop не timer_blink: stopped, <число> toggles"
			return
		fi
		n="$(echo "$answer" | sed -E 's/.* ([0-9]+) toggles/\1/')"
		t0="$(exchange_sent_at "$DEVICE_LOG" timer_blink_start "$1")"
		t1="$(exchange_sent_at "$DEVICE_LOG" timer_blink_stop "$2")"
		if awk -v n="$n" -v a="$t0" -v b="$t1" -v p="$3" 'BEGIN { e = (b - a) * 1000 / p; exit !(n >= e * 0.85 - 1 && n <= e * 1.15 + 1) }'; then
			ok "$4: переключений $n за $(awk -v a="$t0" -v b="$t1" 'BEGIN { printf "%.1f", b - a }') с при периоде $3 мс"
		else
			fail "$4: переключений $n за $(awk -v a="$t0" -v b="$t1" 'BEGIN { printf "%.1f", b - a }') с, а при периоде $3 мс их должно быть около $(awk -v a="$t0" -v b="$t1" -v p="$3" 'BEGIN { printf "%d", (b - a) * 1000 / p }')"
			note "Обработчик переключает светодиод и прибавляет единицу к счётчику при каждом вызове."
		fi
	}

	if reply timer_blink_start 1 | grep -Eq '^timer_blink: started, period 250 ms$'; then
		ok "timer_blink_start 250 отвечает timer_blink: started, period 250 ms"
	else
		fail "Ответ на timer_blink_start 250 не timer_blink: started, period 250 ms"
	fi
	toggles 1 1 250 "Мигание с периодом 250 мс"
	if reply uptime 1 | grep -Eq '^uptime: [0-9]+ ms$' && reply pi_start 1 | grep -Eq '^pi: started' &&
		reply pi 1 | grep -Eq '^pi: '; then
		ok "Во время мигания прибор отвечает на uptime, pi_start и pi"
	else
		fail "Во время мигания прибор не ответил на uptime, pi_start или pi"
		note "Будильник не должен останавливать суперцикл: обработчик короткий, команды идут как прежде."
	fi
	toggles 2 2 100 "Мигание с периодом 100 мс"

	if reply timer_blink_start 3 | grep -Eq '^error: period_ms must be 10\.\.60000$'; then
		ok "timer_blink_start 5 отклонён: error: period_ms must be 10..60000"
	else
		fail "На timer_blink_start 5 нет ответа error: period_ms must be 10..60000"
	fi
	if reply timer_blink_start 4 | grep -Eq '^error: usage timer_blink_start <period_ms>$'; then
		ok "timer_blink_start без аргумента отклонён: error: usage timer_blink_start <period_ms>"
	else
		fail "timer_blink_start без аргумента не ответил error: usage timer_blink_start <period_ms>"
	fi
fi

finish "$TITLE"
