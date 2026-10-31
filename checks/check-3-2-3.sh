#!/usr/bin/env bash
# Задание п3.2.3 «Захват блока через DMA».
# АЦП в непрерывном режиме с делителем на 44,1 кГц, канал DMA по запросу АЦП раскладывает
# отсчёты в массив, о конце захвата сообщает прерывание DMA, готовый блок забирает задача
# logic/block-task. Команда dma_cap <N> отвечает временем захвата против расчёта.
# Читает код, собирает проект и разбирает лог: время трёх блоков, ошибки аргументов.
# Использование: check-3-2-3.sh <путь к репозиторию> [папка проекта]
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


fw_start "Задание 3.2.3 — Захват блока через DMA" 321-audio-recorder "${1:-.}" "${2:-}"

fw_need PLATFORM_C platform.c
fw_need TASK_H block-task.h
fw_need TASK_C block-task.c
for f in check-3-2-3.py device-3-2-3.log; do
	if [ -f "$FW_SRC/$f" ]; then
		ok "Файл $f на месте"
	else
		fail "В проекте нет файла $f"
	fi
done

if [ -n "$PLATFORM_C" ]; then
	PLAT="$(fw_code "$PLATFORM_C")"
	match "$PLAT" 'adc_set_clkdiv[[:space:]]*\(' \
		"platform.c: шаг отсчётов задаёт делитель АЦП adc_set_clkdiv()" \
		"platform.c: нет вызова adc_set_clkdiv()"
	match "$PLAT" 'adc_fifo_setup[[:space:]]*\([[:space:]]*true[[:space:]]*,[[:space:]]*true' \
		"platform.c: буфер АЦП включён вместе с запросом DMA" \
		"platform.c: adc_fifo_setup() не включает буфер и запрос DMA"
	match "$PLAT" 'DREQ_ADC' \
		"platform.c: канал DMA ждёт запроса DREQ_ADC" \
		"platform.c: канал DMA не настроен на запрос DREQ_ADC"
	match "$PLAT" 'dma_channel_configure[[:space:]]*\(' \
		"platform.c: канал настроен dma_channel_configure()" \
		"platform.c: нет вызова dma_channel_configure()"
	match "$PLAT" 'irq_set_exclusive_handler[[:space:]]*\([[:space:]]*DMA_IRQ_[01]' \
		"platform.c: конец захвата отмечает обработчик прерывания DMA" \
		"platform.c: нет обработчика прерывания DMA_IRQ_0 или DMA_IRQ_1"
fi
WAIT="$(mktemp)"
find "$FW_SRC" -type f \( -name '*.c' -o -name '*.h' \) -not -path '*/build/*' 2>/dev/null | sort |
	while read -r f; do cat "$(fw_code "$f")"; done > "$WAIT"
if grep -Eq 'dma_channel_wait_for_finish_blocking|while[[:space:]]*\([[:space:]]*dma_channel_is_busy' "$WAIT"; then
	fail "Прошивка ждёт конца захвата DMA в цикле"
	note "Ожиданий в прошивке нет (требование Н2 ТЗ 2.3). О конце захвата сообщает прерывание, блок забирает задача."
else
	ok "Конца захвата прошивка не ждёт"
fi
if [ -n "$TASK_C" ] && grep -Eq 'printf|puts[[:space:]]*\(' "$(fw_code "$TASK_C")"; then
	fail "block-task.c: задача печатает сама"
	note "Готовый блок задача отдаёт функции, полученной при запуске. Печатает api."
elif [ -n "$TASK_H" ] && grep -Eq '\(\*[[:space:]]*[a-z_]+\)[[:space:]]*\(' "$(fw_code "$TASK_H")"; then
	ok "block-task: блок отдаётся функции, переданной при запуске"
elif [ -n "$TASK_H" ]; then
	fail "block-task.h: нет типа указателя на функцию для готового блока"
fi
MAIN="$FW_SRC/main.c"
[ -f "$MAIN" ] && match "$(fw_code "$MAIN")" 'block_task_handle[[:space:]]*\(' \
	"main.c: обработчик задачи блока вызывается в суперцикле" \
	"main.c: нет вызова block_task_handle()"

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

if device_log "$FW_SRC/device-3-2-3.log" "3.2.3"; then
	TABLE="$(exchange_table "$DEVICE_LOG")"
	reply() {
		exchange_replies "$TABLE" "$1" "$2" | cut -f2 | tail -n +2
	}
	# block_check <номер вызова> <N>
	block_check() {
		local line expected
		line="$(reply dma_cap "$1" | grep -E '^dma_cap: [0-9]+ samples in [0-9]+ us, expected [0-9]+ us, min [0-9]+ max [0-9]+ mean [0-9]+\.[0-9]$')"
		if [ -z "$line" ]; then
			fail "dma_cap $2: нет ответа dma_cap: <N> samples in <мкс> us, expected <мкс> us, min … max … mean …"
			return
		fi
		set -- "$@" $(echo "$line" | sed -E 's/dma_cap: ([0-9]+) samples in ([0-9]+) us, expected ([0-9]+) us, min ([0-9]+) max ([0-9]+) mean ([0-9.]+)/\1 \2 \3 \4 \5 \6/')
		expected=$(( $2 * 1000000 / 44100 ))
		if [ "$3" -ne "$2" ] || [ "$5" -ne "$expected" ]; then
			fail "dma_cap $2: в ответе $3 отсчётов и расчёт $5 мкс, а должно быть $2 и $expected мкс"
			note "Расчёт — N / 44100 секунды."
		elif awk -v t="$4" -v e="$expected" 'BEGIN { d = t - e; if (d < 0) d = -d; exit !(d <= e * 0.01 + 30) }'; then
			ok "dma_cap $2: захват $4 мкс при расчёте $expected мкс"
		else
			fail "dma_cap $2: захват $4 мкс, а расчёт $expected мкс"
			note "Шаг держит делитель АЦП: 48 МГц / 44100 − 1. Время — от запуска АЦП до прерывания конца блока."
		fi
		if [ "$6" -le "$7" ] && [ "$7" -le 4095 ] && awk -v a="$6" -v m="$8" -v b="$7" 'BEGIN { exit !(m >= a && m <= b) }'; then
			ok "dma_cap $2: коды от $6 до $7, среднее $8"
		else
			fail "dma_cap $2: коды min $6 max $7 mean $8 не сходятся"
		fi
	}
	HELP="$(reply help 1)"
	if echo "$HELP" | grep -Eq '^dma_cap[[:space:]]+[^[:space:]]'; then
		ok "help перечисляет dma_cap со справкой"
	else
		fail "В ответе help нет dma_cap со справкой"
	fi
	block_check 1 1000
	block_check 2 4410
	block_check 3 8192
	if reply uptime 1 | grep -Eq '^uptime: [0-9]+ ms$'; then
		ok "После захватов прибор отвечает на uptime"
	else
		fail "После захватов прибор не ответил на uptime"
	fi
	if reply dma_cap 4 | grep -Eq '^error: N must be 1\.\.8192$' && reply dma_cap 5 | grep -Eq '^error: N must be 1\.\.8192$'; then
		ok "dma_cap 0 и dma_cap 9000 отклонены: error: N must be 1..8192"
	else
		fail "dma_cap 0 или dma_cap 9000 не ответили error: N must be 1..8192"
	fi
	if reply dma_cap 6 | grep -Eq '^error: usage dma_cap <N>$'; then
		ok "dma_cap без аргумента отклонён: error: usage dma_cap <N>"
	else
		fail "dma_cap без аргумента не ответил error: usage dma_cap <N>"
	fi
fi

finish "$TITLE"
