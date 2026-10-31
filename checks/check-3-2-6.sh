#!/usr/bin/env bash
# Задание п3.2.6 «Запись звука».
# rec_audio.py принимает поток рекордера и сохраняет запись в recording.wav (16 бит, 44100 Гц),
# итог — в recording.log. Сборка не нужна: проверка читает заголовок WAV и лог.
# Использование: check-3-2-6.sh <путь к репозиторию> [папка проекта]
set -u

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
. "$LIB/report.sh"
. "$LIB/code.sh"
. "$LIB/device.sh"
. "$LIB/firmware.sh"

fw_start "Задание 3.2.6 — Запись звука" 321-audio-recorder "${1:-.}" "${2:-}"

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

if device_log "$FW_SRC/recording.log" "3.2.6"; then
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
