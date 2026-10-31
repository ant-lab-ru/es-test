#!/usr/bin/env bash
# Задание п3.2.7 «Сторожевой таймер».
# Команда wdt_enable <timeout_ms> включает сторожевой таймер, суперцикл обновляет его
# после всех задач, hang вешает суперцикл навсегда, reset_reason после перезапуска
# сообщает причину сброса и счётчик перезапусков из scratch-регистра.
# Читает код, собирает проект и разбирает лог: прибор жив при обновлении, после hang
# плата перезапускается, причина — сторожевой таймер.
# Использование: check-3-2-7.sh <путь к репозиторию> [папка проекта]
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


fw_start "Задание 3.2.7 — Сторожевой таймер" 321-audio-recorder "${1:-.}" "${2:-}"

fw_need PLATFORM_C platform.c
for f in main.c check-3-2-7.py device-3-2-7.log; do
	if [ -f "$FW_SRC/$f" ]; then
		ok "Файл $f на месте"
	else
		fail "В проекте нет файла $f"
	fi
done
if [ -n "$PLATFORM_C" ]; then
	PLAT="$(fw_code "$PLATFORM_C")"
	match "$PLAT" 'watchdog_enable[[:space:]]*\(' \
		"platform.c: сторожевой таймер включает watchdog_enable()" \
		"platform.c: нет вызова watchdog_enable()"
	match "$PLAT" 'watchdog_enable_caused_reboot[[:space:]]*\(' \
		"platform.c: причину сброса узнаёт watchdog_enable_caused_reboot()" \
		"platform.c: нет watchdog_enable_caused_reboot()"
	match "$PLAT" 'scratch\[' \
		"platform.c: счётчик перезапусков хранится в scratch-регистре" \
		"platform.c: не видно scratch-регистров"
	BODIES="$(mktemp)"
	handler_bodies "$PLAT" > "$BODIES"
	if grep -Eq 'watchdog_update' "$BODIES"; then
		fail "Сторожевой таймер обновляется в обработчике прерывания"
		note "Прерывания приходят и при зависшем суперцикле: таймер будет обновляться у прибора, который уже не работает (т3.2.7)."
	else
		ok "Обработчики прерываний сторожевой таймер не обновляют"
	fi
fi
MAIN="$FW_SRC/main.c"
if [ -f "$MAIN" ]; then
	CODE="$(fw_code "$MAIN")"
	if awk '/while[[:space:]]*\(/ { loop = 1 } loop && /watchdog/ { found = 1 } END { exit !found }' "$CODE"; then
		ok "main.c: суперцикл обновляет сторожевой таймер"
	else
		fail "main.c: в суперцикле нет обновления сторожевого таймера"
		note "Обновление — в суперцикле после всех задач, функцией platform."
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

if device_log "$FW_SRC/device-3-2-7.log" "3.2.7"; then
	TABLE="$(exchange_table "$DEVICE_LOG")"
	reply() {
		exchange_replies "$TABLE" "$1" "$2" | cut -f2 | tail -n +2
	}
	HELP="$(reply help 1)"
	for c in wdt_enable hang reset_reason; do
		if ! echo "$HELP" | grep -Eq "^$c[[:space:]]+[^[:space:]]"; then
			fail "В ответе help нет $c со справкой"
		fi
	done
	if reply reset_reason 1 | grep -Eq '^reset: (other|watchdog), restarts [0-9]+$'; then
		ok "reset_reason отвечает reset: <причина>, restarts <число>"
	else
		fail "Ответ на reset_reason не reset: <причина>, restarts <число>"
	fi
	if reply wdt_enable 1 | grep -Eq '^error: timeout_ms must be 1\.\.8388$'; then
		ok "wdt_enable 9000 отклонён: у RP2040 таймаут не больше 8388 мс"
	else
		fail "wdt_enable 9000 не ответил error: timeout_ms must be 1..8388"
		note "Счётчик убывает на 2 за тик (RP2040-E1), поэтому предел — 8388 мс."
	fi
	if reply wdt_enable 2 | grep -Eq '^wdt: enabled, timeout 2000 ms$'; then
		ok "wdt_enable 2000 отвечает wdt: enabled, timeout 2000 ms"
	else
		fail "Ответ на wdt_enable 2000 не wdt: enabled, timeout 2000 ms"
	fi
	U1="$(reply uptime 1 | sed -nE 's/^uptime: ([0-9]+) ms$/\1/p')"
	U2="$(reply uptime 2 | sed -nE 's/^uptime: ([0-9]+) ms$/\1/p')"
	if [ -n "$U1" ] && [ -n "$U2" ] && [ $(( U2 - U1 )) -ge 2500 ]; then
		ok "Прибор работает дольше таймаута: uptime вырос на $(( U2 - U1 )) мс без сброса"
	else
		fail "После wdt_enable прибор не прожил дольше таймаута без сброса"
		note "Суперцикл должен обновлять таймер на каждой итерации."
	fi
	if reply hang 1 | grep -Eq '^hang: superloop stopped$'; then
		ok "hang отвечает hang: superloop stopped"
	else
		fail "Ответ на hang не hang: superloop stopped"
	fi
	if grep -Eq '^[[:space:]]*[0-9.]+ --- плата снова на связи$' "$DEVICE_LOG"; then
		ok "После hang плата перезапустилась"
	else
		fail "После hang плата не перезапустилась"
		note "Сторожевой таймер должен быть включён, а обновлять его — только суперцикл."
	fi
	if reply reset_reason 2 | grep -Eq '^reset: watchdog, restarts [1-9][0-9]*$'; then
		ok "После перезапуска reset_reason: причина — сторожевой таймер"
	else
		fail "После перезапуска reset_reason не reset: watchdog, restarts <не меньше 1>"
		note "watchdog_caused_reboot() правдив и после прошивки через picotool, нужна watchdog_enable_caused_reboot()."
	fi
	U3="$(reply uptime 3 | sed -nE 's/^uptime: ([0-9]+) ms$/\1/p')"
	if [ -n "$U3" ] && [ "$U3" -lt 10000 ]; then
		ok "После перезапуска uptime начался заново: $U3 мс"
	else
		fail "После перезапуска uptime не начался заново"
	fi
fi

finish "$TITLE"
