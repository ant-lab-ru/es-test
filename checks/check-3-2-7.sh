#!/usr/bin/env bash
# Задание п3.2.7 «Запись звука».
# Модуль MAX9814 подключён к GP26. Команды mic_bias и mic_level [<ms>] снимают блок
# через DMA задачей block-task и отвечают смещением и уровнем сигнала. rec_audio.py
# принимает поток и сохраняет голос в recording.wav (16 бит, 44100 Гц), итог — в recording.log.
# Читает код, собирает проект и разбирает лог: смещение 1,0–1,5 В (микрофон подключён),
# формат уровня, окно в миллисекундах, ошибки аргументов. Затем читает заголовок WAV и лог записи.
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


fw_start "Задание 3.2.7 — Запись звука" 321-audio-recorder "${1:-.}" "${2:-}"

fw_need API_C api-callbacks.c
for f in check-3-2-7.py device-3-2-7.log; do
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

if device_log "$FW_SRC/device-3-2-7.log" "3.2.7"; then
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


# --- запись голоса ---

# wav_field <файл> <смещение> <байтов: 2 или 4> — число из заголовка WAV, младшим байтом вперёд
wav_field() {
	od -An -j "$2" -N "$3" -t u"$3" "$1" | tr -d ' '
}

# wav_check <файл> <разрядность> — заголовок: RIFF, WAVE, PCM, один канал, 44100 Гц, разрядность;
# заводит WAV_SECONDS — длительность по размеру данных
wav_check() {
	WAV_SECONDS=""
	if [ "$(head -c 4 "$1")" != "RIFF" ] || [ "$(dd if="$1" bs=1 skip=8 count=4 2> /dev/null)" != "WAVE" ]; then
		fail "$(basename "$1"): не файл WAV"
		return
	fi
	local format channels rate bits size
	format="$(wav_field "$1" 20 2)"
	channels="$(wav_field "$1" 22 2)"
	rate="$(wav_field "$1" 24 4)"
	bits="$(wav_field "$1" 34 2)"
	size="$(wav_field "$1" 40 4)"
	if [ "$format" = 1 ] && [ "$channels" = 1 ] && [ "$rate" = 44100 ] && [ "$bits" = "$2" ]; then
		ok "$(basename "$1"): PCM, один канал, 44100 Гц, $bits бит"
	else
		fail "$(basename "$1"): формат $format, каналов $channels, $rate Гц, $bits бит, а нужно PCM, 1 канал, 44100 Гц, $2 бит"
		note "Параметры файла задают setnchannels(), setframerate() и setsampwidth() модуля wave."
	fi
	WAV_SECONDS="$(awk -v s="$size" -v b="$2" 'BEGIN { printf "%.2f", s / (b / 8) / 44100 }')"
}

for f in rec_audio.py recording.wav recording.log; do
	if [ -f "$FW_SRC/$f" ]; then
		ok "Файл $f на месте"
	else
		fail "В проекте нет файла $f"
	fi
done

SCRIPT="$FW_SRC/rec_audio.py"
if [ -f "$SCRIPT" ]; then
	PY="$(normalize "$SCRIPT")"
	match "$PY" '^[[:space:]]*import wave|from wave' \
		"rec_audio.py: файл пишет модуль wave" \
		"rec_audio.py: нет import wave"
fi

if [ -f "$SCRIPT" ]; then
	match "$PY" 'setsampwidth[[:space:]]*\([[:space:]]*2' \
		"rec_audio.py: отсчёт WAV — 2 байта" \
		"rec_audio.py: нет setsampwidth(2)"
fi
if [ -f "$FW_SRC/recording.wav" ]; then
	wav_check "$FW_SRC/recording.wav" 16
fi

if device_log "$FW_SRC/recording.log" "3.2.7"; then
	L="$DEVICE_LOG"
	FILE="$(grep -E '^файл: ' "$L" | head -1)"
	GOT="$(grep -E '^принято: пакетов [0-9]+, отсчётов [0-9]+, пропущено пакетов [0-9]+' "$L" | head -1)"
	STOP="$(grep -E '^<-- stream: stopped, [0-9]+ packets, [0-9]+ samples, [0-9]+ overruns$' "$L" | head -1)"
	if [ -z "$FILE" ] || [ -z "$GOT" ] || [ -z "$STOP" ]; then
		fail "В логе нет строк «файл», «принято» или ответа stream: stopped"
		note "Лог пишет rec_audio.py, запущенный с ключом --wav: имя лога — имя файла WAV с расширением .log."
	else
		LOST="$(echo "$GOT" | sed -E 's/.*пропущено пакетов ([0-9]+).*/\1/')"
		OVER="$(echo "$STOP" | sed -E 's/.* ([0-9]+) overruns/\1/')"
		SECONDS_LOG="$(echo "$FILE" | sed -E 's/.*Гц, ([0-9.]+) с.*/\1/')"
		if [ "$LOST" -eq 0 ] && [ "$OVER" -eq 0 ]; then
			ok "Запись без пропущенных пакетов и переполнений"
		else
			fail "В записи пропущено пакетов $LOST, переполнений $OVER"
			note "Запись с пропусками звучит с щелчками и короче, чем шла."
		fi
		if [ -n "${WAV_SECONDS:-}" ] && awk -v a="$WAV_SECONDS" -v b="$SECONDS_LOG" 'BEGIN { d = a - b; if (d < 0) d = -d; exit !(a >= 2.5 && d <= 0.05) }'; then
			ok "Длительность записи $WAV_SECONDS с совпадает с логом"
		else
			fail "Длительность файла ${WAV_SECONDS:-?} с, в логе $SECONDS_LOG с, нужно не меньше 2,5 с"
		fi
		if grep -Eq '^<-- stream: started, 44100 Hz, 16 bit$' "$L"; then
			ok "Запись шла 16-битным потоком"
		else
			fail "В логе нет ответа stream: started, 44100 Hz, 16 bit"
		fi
	fi
fi

finish "$TITLE"
