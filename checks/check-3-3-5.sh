#!/usr/bin/env bash
# Задание п3.3.5 «Осциллограмма линии UART».
# Провод GP0 — GP26: АЦП видит линию передатчика UART0. Захват блока через DMA из
# 321-audio-recorder перенесён в 331-uart с частотой 500 000 отсчётов в секунду, на пределе
# АЦП делитель 0. Команда scope <скорость> <текст> запускает захват, затем передачу
# UART0 → UART1 и печатает отсчёты, когда блок готов.
# Читает код, собирает проект и разбирает лог: сама находит в отсчётах старт-бит
# и расшифровывает символ U на 115 200 и 9600 бит/с.
# Использование: check-3-3-5.sh <путь к репозиторию> [папка проекта]
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

fw_start "Задание 3.3.5 — Осциллограмма линии UART" 331-uart "${1:-.}" "${2:-}"

fw_need PLATFORM_C platform.c
fw_need TASK_C block-task.c
for f in check-3-3-5.py device-3-3-5.log; do
	if [ -f "$FW_SRC/$f" ]; then
		ok "Файл $f на месте"
	else
		file_missing "$f"
	fi
done

if [ -n "$PLATFORM_C" ]; then
	PLAT="$(fw_code "$PLATFORM_C")"
	match "$PLAT" 'adc_set_clkdiv[[:space:]]*\([[:space:]]*0(\.0*)?f?[[:space:]]*\)' \
		"platform.c: АЦП на пределе, делитель 0 — преобразования подряд" \
		"platform.c: нет adc_set_clkdiv(0)"
	if ! grep -Eq 'adc_set_clkdiv[[:space:]]*\([[:space:]]*0(\.0*)?f?[[:space:]]*\)' "$PLAT"; then
		note "Делитель 95 модуль пропускает через раз: запуск приходит, пока идёт прошлое преобразование, и отсчётов вдвое меньше (п3.3.5, шаг 3)."
	fi
	match "$PLAT" 'DREQ_ADC' \
		"platform.c: канал DMA ждёт запроса DREQ_ADC" \
		"platform.c: канал DMA не настроен на запрос DREQ_ADC"
	match "$PLAT" 'irq_set_exclusive_handler[[:space:]]*\([[:space:]]*DMA_IRQ_[01]' \
		"platform.c: конец захвата отмечает обработчик прерывания DMA" \
		"platform.c: нет обработчика прерывания DMA_IRQ_0 или DMA_IRQ_1"
	BODIES="$(mktemp)"
	handler_bodies "$PLAT" > "$BODIES"
	if grep -Eq 'printf|puts[[:space:]]*\(|putchar|sleep_|busy_wait' "$BODIES"; then
		fail "Обработчик прерывания печатает или ждёт"
		note "Обработчики только отмечают события и переносят байты (т3.2.5)."
	else
		ok "Обработчики прерываний не печатают и не ждут"
	fi
fi

WAIT="$(fw_project_code)"
if grep -Eq 'dma_channel_wait_for_finish_blocking|while[[:space:]]*\([[:space:]]*dma_channel_is_busy|sleep_(ms|us)[[:space:]]*\(' "$WAIT"; then
	fail "Прошивка ждёт: конца захвата DMA или паузы"
	note "Захват и передача идут сами, готовый блок замечает задача block-task на итерации суперцикла."
else
	ok "Прошивка ничего не ждёт"
fi

MAIN="$FW_SRC/main.c"
[ -f "$MAIN" ] && match "$(fw_code "$MAIN")" 'block_task_handle[[:space:]]*\(' \
	"main.c: обработчик задачи блока вызывается в суперцикле" \
	"main.c: нет вызова block_task_handle()"

LOGIC="$(mktemp)"
find "$FW_SRC/logic" -type f \( -name '*.c' -o -name '*.h' \) 2>/dev/null | sort |
	while read -r f; do cat "$(fw_code "$f")"; done > "$LOGIC"
if grep -Eq '#include[[:space:]]*[<"](pico|hardware)/|(^|[^a-z_])(adc|dma)_[a-z_]+[[:space:]]*\(|(^|[^a-z_])uart_(init|set_[a-z_]+|is_[a-z_]+|get_hw)[[:space:]]*\(' "$LOGIC"; then
	fail "logic: код логики обращается к SDK"
	note "АЦП, DMA и UART — железо, им место в platform."
else
	ok "logic: логика по-прежнему без SDK"
fi

build_project "$FW_SRC"

# scope_decode <скорость> — символ из отсчётов ответа на стандартном входе: первый спад
# после высокого уровня — старт-бит, биты читаются в середине, младший первым;
# печатает «код старт стоп» или пусто, если спада нет
scope_decode() {
	awk -v baud="$1" '
		/^[0-9]/ { for (i = 1; i <= NF; i++) s[n++] = $i }
		END {
			bit = 500000 / baud
			for (i = 1; i < n; i++) if (s[i - 1] >= 2048 && s[i] < 2048) break
			if (i >= n || i + 10 * bit >= n) exit
			code = 0
			for (k = 0; k < 10; k++) {
				v = s[int(i + (k + 0.5) * bit)] >= 2048
				if (k == 0) start = v
				else if (k == 9) stop = v
				else code += v * 2 ^ (k - 1)
			}
			printf "%d %d %d\n", code, start, stop
		}
	'
}

if device_log "$FW_SRC/device-3-3-5.log" "3.3.5"; then
	TABLE="$(exchange_table "$DEVICE_LOG")"
	reply() {
		exchange_replies "$TABLE" "$1" "$2" | cut -f2 | tail -n +2
	}
	S='[[:space:]]+'

	if reply help 1 | grep -Eq '^scope[[:space:]]+[^[:space:]]'; then
		ok "help перечисляет scope со справкой"
	else
		fail "В ответе help нет scope со справкой"
	fi

	# scope_check <номер вызова> <скорость>
	scope_check() {
		local answer header count decoded
		answer="$(reply scope "$1")"
		header="$(echo "$answer" | head -1)"
		if ! echo "$header" | grep -Eq "^scope:${S}[0-9]+${S}samples,${S}500000${S}Hz,${S}$2${S}baud,${S}uart1${S}U${S}err:${S}none$"; then
			fail "scope $2 U: заголовок не scope: <N> samples, 500000 Hz, $2 baud, uart1 U err: none${header:+ — пришло «${header}»}"
			note "Скорость задаётся обоим модулям, UART1 принимает тот же U без ошибок."
			return
		fi
		count="$(echo "$answer" | grep -E '^[0-9]' | wc -w)"
		if [ "$count" -ne "$(echo "$header" | sed -E 's/^scope:[[:space:]]+([0-9]+).*/\1/')" ] ||
			! echo "$answer" | tail -1 | grep -Eq '^scope: end$'; then
			fail "scope $2 U: отсчётов $count, не столько, сколько в заголовке, или нет scope: end"
			return
		fi
		decoded="$(echo "$answer" | scope_decode "$2")"
		if [ "$decoded" = "85 0 1" ]; then
			ok "scope $2 U: в $count отсчётах старт-бит, 0x55 младшим вперёд и стоп-бит"
		else
			fail "scope $2 U: из отсчётов не читается U — код, старт, стоп: ${decoded:-спада нет}"
			note "Захват запускается раньше передачи, а отсчётов на бит — 500 000 / скорость. Если на бит вдвое меньше отсчётов, делитель АЦП не 0."
		fi
	}

	scope_check 1 115200
	scope_check 2 9600

	errors=0
	for i in 3 4 5; do
		reply scope "$i" | grep -Eq '^error: usage scope <baud> <text>$' && errors=$((errors + 1))
	done
	if [ "$errors" -eq 3 ]; then
		ok "scope 1200 U, scope 9600 ABCDE и scope без аргументов отклонены"
	else
		fail "Неверные аргументы scope не отклонены как error: usage scope <baud> <text>"
		note "Скорость 9600..115200, текст до четырёх символов: иначе передача не поместится в блок."
	fi
fi

finish "$TITLE"
