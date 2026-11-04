#!/usr/bin/env bash
# Задание п3.2.4 «Поток с двойной буферизацией».
# Два канала DMA цепочкой заполняют два буфера по очереди, прерывание DMA отмечает
# готовый буфер, задача logic/stream-task отдаёт его кадром (синхрослово a5 5a, номер, число
# отсчётов, отсчёты), api отправляет байты без замены \n. Команды stream_start и stream_stop.
# Скрипт rec_audio.py принимает поток и пишет итог в stream.log.
# Читает код, собирает проект и разбирает stream.log: кадры, пропуски, переполнения.
# Использование: check-3-2-4.sh <путь к репозиторию> [папка проекта]
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


fw_start "Задание 3.2.4 — Поток с двойной буферизацией" 321-audio-recorder "${1:-.}" "${2:-}"

fw_need PLATFORM_C platform.c
fw_need TASK_H stream-task.h
fw_need TASK_C stream-task.c
for f in rec_audio.py stream.log; do
	if [ -f "$FW_SRC/$f" ]; then
		ok "Файл $f на месте"
	else
		fail "В проекте нет файла $f"
	fi
done

if [ -n "$PLATFORM_C" ]; then
	PLAT="$(fw_code "$PLATFORM_C")"
	match "$PLAT" 'channel_config_set_chain_to[[:space:]]*\(' \
		"platform.c: каналы потока связаны цепочкой" \
		"platform.c: нет channel_config_set_chain_to()"
	# остановка потока: перед прерыванием каналов цепочка разорвана (RP2040-E13)
	STOP_BODY="$(awk '/void[[:space:]]+platform_stream_stop[[:space:]]*\(/ { on = 1 } on { print } on && /^}/ { exit }' "$PLAT")"
	if echo "$STOP_BODY" | grep -Eq 'channel_config_set_chain_to[[:space:]]*\(' && echo "$STOP_BODY" | grep -Eq 'dma_channel_abort[[:space:]]*\('; then
		ok "platform.c: перед остановкой потока цепочка каналов разорвана"
	else
		fail "platform.c: platform_stream_stop() прерывает каналы, не разорвав цепочку"
		note "Из-за RP2040-E13 прерванный канал запускает соседний, и тот остаётся взведённым. Следующий захват пишет за конец буфера (п3.2.4, врезка о разрыве цепочки)."
	fi
	match "$PLAT" 'dma_channel_set_write_addr[[:space:]]*\(' \
		"platform.c: обработчик возвращает каналу начало буфера" \
		"platform.c: нет dma_channel_set_write_addr()"
	if grep -Eq 'stdio_put_string[[:space:]]*\([^;]*false[[:space:]]*,[[:space:]]*false[[:space:]]*\)|stdio_set_translate_crlf[[:space:]]*\([^;]*false' "$PLAT"; then
		ok "platform.c: байты уходят в порт без замены \\n на \\r\\n"
	else
		fail "platform.c: не видно отправки без замены \\n на \\r\\n"
		note "printf() и fwrite() заменяют байт 0A парой 0D 0A. Двоичные данные — stdio_put_string(…, false, false) (т3.2.8)."
	fi
fi
if [ -n "$TASK_C" ] && grep -Eq 'printf|puts[[:space:]]*\(|fwrite' "$(fw_code "$TASK_C")"; then
	fail "stream-task.c: задача отправляет сама"
	note "Кадр задача отдаёт функции, полученной при запуске. Отправляет api через platform."
elif [ -n "$TASK_H" ]; then
	H="$(fw_code "$TASK_H")"
	if grep -Eiq '0x5aa5' "$H" && grep -Eq '\(\*[[:space:]]*[a-z_]+\)[[:space:]]*\(' "$H"; then
		ok "stream-task.h: синхрослово 0x5aa5 и тип функции для кадра"
	else
		fail "stream-task.h: нет синхрослова 0x5aa5 или типа функции для кадра"
		note "Синхрослово a5 5a в памяти младшим байтом вперёд — число 0x5aa5 (приложение А ТЗ)."
	fi
fi
MAIN="$FW_SRC/main.c"
if [ -f "$MAIN" ]; then
	CODE="$(fw_code "$MAIN")"
	match "$CODE" 'stream_task_init[[:space:]]*\([[:space:]]*[a-z_]+' \
		"main.c: задаче потока передана функция отправки кадра" \
		"main.c: stream_task_init() не получает функцию отправки"
	match "$CODE" 'stream_task_handle[[:space:]]*\(' \
		"main.c: обработчик задачи потока вызывается в суперцикле" \
		"main.c: нет вызова stream_task_handle()"
fi
SCRIPT="$FW_SRC/rec_audio.py"
if [ -f "$SCRIPT" ]; then
	PY="$(normalize "$SCRIPT")"
	match "$PY" '^[[:space:]]*import struct|from struct' \
		"rec_audio.py: числа из байтов собирает struct" \
		"rec_audio.py: нет import struct"
	if grep -q 'stream_start' "$PY" && grep -q 'stream_stop' "$PY"; then
		ok "rec_audio.py: скрипт запускает и останавливает поток"
	else
		fail "rec_audio.py: не видно stream_start и stream_stop"
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

if device_log "$FW_SRC/stream.log" "3.2.4"; then
	L="$DEVICE_LOG"
	if grep -Eq '^<-- stream: started, 44100 Hz, 16 bit$' "$L"; then
		ok "stream_start отвечает stream: started, 44100 Hz, 16 bit"
	else
		fail "В stream.log нет ответа stream: started, 44100 Hz, 16 bit"
	fi
	GOT="$(grep -E '^принято: кадров [0-9]+, отсчётов [0-9]+, пропущено кадров [0-9]+' "$L" | head -1)"
	STOP="$(grep -E '^<-- stream: stopped, [0-9]+ frames, [0-9]+ samples, [0-9]+ overruns$' "$L" | head -1)"
	SPEED="$(grep -E '^скорость: [0-9]+ отсчётов в секунду за [0-9.]+ с$' "$L" | head -1)"
	if [ -z "$GOT" ] || [ -z "$STOP" ] || [ -z "$SPEED" ]; then
		fail "В stream.log нет строк «принято», «скорость» или ответа stream: stopped"
		note "stream.log пишет rec_audio.py, запущенный без --wav."
	else
		set -- $(echo "$GOT" | sed -E 's/принято: кадров ([0-9]+), отсчётов ([0-9]+), пропущено кадров ([0-9]+).*/\1 \2 \3/') \
			$(echo "$STOP" | sed -E 's/<-- stream: stopped, ([0-9]+) frames, ([0-9]+) samples, ([0-9]+) overruns/\1 \2 \3/') \
			$(echo "$SPEED" | sed -E 's/скорость: ([0-9]+) отсчётов в секунду за ([0-9.]+) с/\1 \2/')
		if awk -v p="$1" -v s="$8" 'BEGIN { exit !(s >= 3 && p >= s * 80) }'; then
			ok "Принято $1 кадров за $8 с"
		else
			fail "Принято $1 кадров за $8 с, нужно не меньше 3 с и около 86 кадров в секунду"
		fi
		if [ "$2" -eq $(( $1 * 512 )) ]; then
			ok "В каждом кадре 512 отсчётов"
		else
			fail "Отсчётов $2 на $1 кадров, а в кадре 16-битного потока их 512"
		fi
		if [ "$3" -eq 0 ]; then
			ok "Пропущенных кадров нет"
		else
			fail "Пропущено кадров: $3"
			note "Пропуск виден по номерам. Если номера идут подряд на приборе, байты теряются или меняются по пути, например при замене \\n на \\r\\n."
		fi
		if [ "$6" -eq 0 ]; then
			ok "Переполнений буферов нет"
		else
			fail "Переполнений буферов: $6"
			note "Суперцикл не успевает отправить буфер, пока DMA заполняет другой. Смотрите профилирование задачи потока."
		fi
		if [ "$4" -ge "$1" ] && [ $(( $4 - $1 )) -le 1 ]; then
			ok "Прибор отправил $4 кадров, скрипт принял $1"
		else
			fail "Прибор отправил $4 кадров, а скрипт принял $1"
		fi
		if awk -v r="$7" 'BEGIN { exit !(r >= 43000 && r <= 45500) }'; then
			ok "Скорость потока $7 отсчётов в секунду"
		else
			fail "Скорость потока $7 отсчётов в секунду, а должно быть около 44100"
			note "Шаг держит делитель АЦП: 48 МГц / 44100 − 1."
		fi
	fi
	if grep -Eq '^<-- stream: stopped' "$L"; then
		ok "Поток остановлен командой stream_stop"
	fi
fi

finish "$TITLE"
