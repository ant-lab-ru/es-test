#!/usr/bin/env bash
# Задание п3.2.5 «Подключение микрофона».
# Модуль MAX9814 подключён к GP26. Команды mic_bias и mic_level [<ms>] снимают блок
# через DMA задачей block-task и отвечают смещением и уровнем сигнала.
# Читает код, собирает проект и разбирает лог: смещение 1,0–1,5 В (микрофон подключён),
# формат уровня, окно в миллисекундах, ошибки аргументов.
# Использование: check-3-2-5.sh <путь к репозиторию> [папка проекта]
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


fw_start "Задание 3.2.5 — Подключение микрофона" 321-audio-recorder "${1:-.}" "${2:-}"

fw_need API_C api-callbacks.c
for f in check-3-2-5.py device-3-2-5.log; do
	if [ -f "$FW_SRC/$f" ]; then
		ok "Файл $f на месте"
	else
		fail "В проекте нет файла $f"
	fi
done
if [ -n "$API_C" ]; then
	API="$(fw_code "$API_C")"
	if [ "$(grep -Ec 'block_task_start[[:space:]]*\(' "$API")" -ge 1 ] && grep -Eq '"mic_bias"' "$API" && grep -Eq '"mic_level"' "$API"; then
		ok "api: mic_bias и mic_level снимают блок задачей block-task"
	else
		fail "api: нет команд mic_bias и mic_level на задаче block-task"
		note "Блок отсчётов уже умеет снимать задача из п3.2.3, ей передаётся другая функция для готового блока."
	fi
	if grep -Eq '(^|[^a-z_])(adc|dma)_[a-z_]+[[:space:]]*\(' "$API"; then
		fail "api-callbacks.c: команды обращаются к АЦП или DMA напрямую"
	else
		ok "api-callbacks.c: к АЦП и DMA обращается только platform"
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

if device_log "$FW_SRC/device-3-2-5.log" "3.2.5"; then
	TABLE="$(exchange_table "$DEVICE_LOG")"
	reply() {
		exchange_replies "$TABLE" "$1" "$2" | cut -f2 | tail -n +2
	}
	BIAS="$(reply mic_bias 1 | grep -E '^mic: bias [0-9]+\.[0-9]{3} V$' | sed -E 's/mic: bias ([0-9.]+) V/\1/')"
	if [ -z "$BIAS" ]; then
		fail "Ответ на mic_bias не mic: bias <напряжение> V"
	elif awk -v b="$BIAS" 'BEGIN { exit !(b >= 1.0 && b <= 1.5) }'; then
		ok "Смещение микрофона $BIAS В, у MAX9814 оно около 1,25 В"
	else
		fail "Смещение $BIAS В, а у MAX9814 оно около 1,25 В"
		note "Похоже, микрофон не подключён: свободный вход GP26 показывает случайное напряжение. Проверьте провод Out → GP26, Vdd → 3V3(OUT) и GND."
	fi
	# level_check <номер вызова> <окно, мс>
	level_check() {
		local line
		line="$(reply mic_level "$1" | grep -E '^mic: level [0-9]+\.[0-9] mV rms, peak [0-9]+\.[0-9] mV, [0-9]+ ms$')"
		if [ -z "$line" ]; then
			fail "mic_level, окно $2 мс: ответ не mic: level <мВ> mV rms, peak <мВ> mV, <мс> ms"
			return
		fi
		set -- "$@" $(echo "$line" | sed -E 's/mic: level ([0-9.]+) mV rms, peak ([0-9.]+) mV, ([0-9]+) ms/\1 \2 \3/')
		if awk -v r="$3" -v p="$4" -v w="$5" -v want="$2" 'BEGIN { exit !(r <= p && r < 1650 && w >= want - 1 && w <= want) }'; then
			ok "mic_level, окно $5 мс: $3 мВ среднеквадратично, пик $4 мВ"
		else
			fail "mic_level, окно $2 мс: $3 мВ среднеквадратично, пик $4 мВ, окно $5 мс не сходятся"
			note "Уровень — отклонение от среднего блока. Среднеквадратичное не больше пикового."
		fi
	}
	level_check 1 100
	level_check 2 50
	level_check 3 185
	if reply mic_level 4 | grep -Eq '^error: ms must be 1\.\.185$' && reply mic_level 5 | grep -Eq '^error: ms must be 1\.\.185$'; then
		ok "mic_level 0 и mic_level 200 отклонены: error: ms must be 1..185"
	else
		fail "mic_level 0 или mic_level 200 не ответили error: ms must be 1..185"
	fi
fi

finish "$TITLE"
