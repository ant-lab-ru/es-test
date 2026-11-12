#!/usr/bin/env bash
# Задание п3.3.4 «Приём блока».
# UART1 передаёт блок из 64 байтов, вдвое длиннее очереди приёма UART0. Команда block irq
# разрешает прерывание приёма UART0, его обработчик забирает байты из очереди в буфер.
# Команда block poll читает UART0 только после конца передачи. Провода от п3.3.3.
# Читает код и README, собирает проект и разбирает лог: с прерыванием 64 из 64 без ошибок,
# без прерывания ровно 32 и признак переполнения OE.
# Использование: check-3-3-4.sh <путь к репозиторию> [папка проекта]
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

fw_start "Задание 3.3.4 — Приём блока" 331-uart "${1:-.}" "${2:-}"

fw_need PLATFORM_C platform.c
for f in README.md check-3-3-4.py device-3-3-4.log; do
	if [ -f "$FW_SRC/$f" ]; then
		ok "Файл $f на месте"
	else
		file_missing "$f"
	fi
done

if [ -n "$PLATFORM_C" ]; then
	PLAT="$(fw_code "$PLATFORM_C")"
	match "$PLAT" 'irq_set_exclusive_handler[[:space:]]*\([[:space:]]*UART0_IRQ' \
		"platform.c: назначен обработчик прерывания UART0_IRQ" \
		"platform.c: нет обработчика прерывания UART0_IRQ"
	match "$PLAT" 'uart_set_irqs?_enabled[[:space:]]*\(|uart_set_irq_enables[[:space:]]*\(|imsc' \
		"platform.c: прерывание приёма разрешается в модуле UART" \
		"platform.c: прерывание приёма в модуле не разрешается"
	BODIES="$(mktemp)"
	handler_bodies "$PLAT" > "$BODIES"
	if [ ! -s "$BODIES" ]; then
		fail "platform.c: не найден обработчик прерывания"
		note "Обработчик — функция void имя(void), которую получает irq_set_exclusive_handler()."
	elif grep -Eq 'printf|puts[[:space:]]*\(|putchar|sleep_|busy_wait' "$BODIES"; then
		fail "Обработчик прерывания печатает или ждёт"
		note "Обработчик только переносит байты из очереди в буфер (т3.2.5)."
	else
		ok "Обработчик прерывания не печатает и не ждёт"
	fi
	if grep -Eq 'volatile' "$PLAT"; then
		ok "platform.c: переменные, общие с обработчиком, объявлены volatile"
	else
		fail "platform.c: нет volatile"
		note "Буфер и счётчик байтов меняет обработчик, а читает задача — такие переменные объявляются volatile."
	fi
fi

RAW_README="$FW_SRC/README.md"
if [ -f "$RAW_README" ]; then
	if grep -Eq '(^|[^0-9])32([^0-9]|$)' "$(normalize "$RAW_README")"; then
		ok "README.md: потеря связана с очередью приёма на 32 байта"
	else
		fail "README.md: нет объяснения, сколько байтов теряется без прерывания"
		note "Свяжите потерю с глубиной очереди приёма: сколько байтов в ней помещается и что стало с остальными."
	fi
fi

build_project "$FW_SRC"

if device_log "$FW_SRC/device-3-3-4.log" "3.3.4"; then
	TABLE="$(exchange_table "$DEVICE_LOG")"
	reply() {
		exchange_replies "$TABLE" "$1" "$2" | cut -f2 | tail -n +2
	}
	S='[[:space:]]+'

	if reply help 1 | grep -Eq '^block[[:space:]]+[^[:space:]]'; then
		ok "help перечисляет block со справкой"
	else
		fail "В ответе help нет block со справкой"
	fi

	n=$(exchange_calls "$DEVICE_LOG" block)
	irq=0; poll=0; irq_bad=""; poll_bad=""
	for i in $(seq 1 "$n"); do
		answer="$(reply block "$i" | head -1)"
		case "$answer" in
		"block irq:"*)
			irq=$((irq + 1))
			echo "$answer" | grep -Eq "^block irq:${S}64/64${S}match,${S}err:${S}none$" || irq_bad="$answer"
			;;
		"block poll:"*)
			poll=$((poll + 1))
			echo "$answer" | grep -Eq "^block poll:${S}32/64${S}match,${S}err:.*OE" || poll_bad="$answer"
			;;
		esac
	done

	if [ "$irq" -ge 2 ] && [ -z "$irq_bad" ]; then
		ok "block irq: все 64 байта приняты и совпали с блоком, ошибок нет ($irq раза)"
	else
		fail "block irq: ответ не block irq: 64/64 match, err: none${irq_bad:+ — пришло «${irq_bad}»}"
		note "Обработчик UART0_IRQ должен забирать байты во время передачи. Прерывание приёма разрешают до её начала."
	fi
	if [ "$poll" -ge 2 ] && [ -z "$poll_bad" ]; then
		ok "block poll: принято ровно 32 байта начала блока, признак переполнения OE ($poll раза)"
	else
		fail "block poll: ответ не block poll: 32/64 match, err: OE${poll_bad:+ — пришло «${poll_bad}»}"
		note "Без прерывания UART0 читается только после конца передачи: очередь держит 32 байта, остальные теряются, а OE ставится в UARTRSR."
	fi

	if reply block "$n" | grep -Eq '^error: usage block irq\|poll$'; then
		ok "block xx отклонён: error: usage block irq|poll"
	else
		fail "block xx не ответил error: usage block irq|poll"
	fi
fi

finish "$TITLE"
