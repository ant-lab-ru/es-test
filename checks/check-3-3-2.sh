#!/usr/bin/env bash
# Задание п3.3.2 «Петля и перемычка».
# UART0 настроен через hardware_uart на 115 200 бит/с, 8N1. Команда loop internal
# ставит бит LBE и не отдаёт выводы модулю, loop pins снимает LBE и отдаёт GP0 и GP1.
# Команда echo <строка> передаёт строку через UART0, задача logic/uart-task без ожиданий
# отдаёт принятое и признаки ошибок из UARTRSR. Перемычка GP0 — GP1 стоит весь прогон.
# Читает код, собирает проект и разбирает лог: строки в обоих режимах, ошибки аргументов.
# Использование: check-3-3-2.sh <путь к репозиторию> [папка проекта]
set -u

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
. "$LIB/report.sh"
. "$LIB/build.sh"
. "$LIB/code.sh"
. "$LIB/cmake.sh"
. "$LIB/device.sh"
. "$LIB/exchange.sh"
. "$LIB/firmware.sh"

fw_start "Задание 3.3.2 — Петля и перемычка" 331-uart "${1:-.}" "${2:-}"

fw_need PLATFORM_C platform.c
fw_need TASK_H uart-task.h
fw_need TASK_C uart-task.c
for f in main.c check-3-3-2.py device-3-3-2.log; do
	if [ -f "$FW_SRC/$f" ]; then
		ok "Файл $f на месте"
	else
		file_missing "$f"
	fi
done

CMAKE="$FW_SRC/CMakeLists.txt"
if [ -f "$CMAKE" ]; then
	match "$(cmake_flatten "$CMAKE")" 'target_link_libraries[[:space:]]*\([[:space:]]*platform[^)]*hardware_uart' \
		"CMakeLists.txt: platform подключает hardware_uart" \
		"CMakeLists.txt: hardware_uart не подключена к platform"
fi

if [ -n "$PLATFORM_C" ]; then
	PLAT="$(fw_code "$PLATFORM_C")"
	if grep -Eq 'uart_init[[:space:]]*\([[:space:]]*uart0[[:space:]]*,' "$PLAT" && grep -Eq '115200' "$PLAT"; then
		ok "platform.c: UART0 настроен uart_init() на 115 200 бит/с"
	else
		fail "platform.c: нет uart_init(uart0, …) или скорости 115200"
	fi
	match "$PLAT" 'GPIO_FUNC_UART' \
		"platform.c: выводы отданы модулю функцией GPIO_FUNC_UART" \
		"platform.c: выводам не назначена функция GPIO_FUNC_UART"
	match "$PLAT" 'UART_UARTCR_LBE_BITS' \
		"platform.c: петлю внутри модуля включает бит LBE регистра UARTCR" \
		"platform.c: нет бита UART_UARTCR_LBE_BITS"
	if grep -Eq 'rsr[[:space:]]*=[^=]' "$PLAT"; then
		ok "platform.c: признаки ошибок сбрасывает запись в UARTECR"
	else
		fail "platform.c: признаки ошибок не сбрасываются записью в UARTECR"
		note "UARTRSR и UARTECR — один адрес. В SDK это поле rsr: запись в него сбрасывает признаки (т3.3.4)."
	fi
	match "$PLAT" 'rsr' \
		"platform.c: признаки ошибок читаются из UARTRSR" \
		"platform.c: признаки ошибок не читаются из UARTRSR"
fi

CODE="$(fw_project_code)"
if grep -Eq '(^|[^a-z_])(sleep_(ms|us)|busy_wait_[a-z_]+|uart_read_blocking|uart_write_blocking|uart_tx_wait_blocking|uart_is_readable_within_us)[[:space:]]*\(' "$CODE"; then
	fail "Прошивка ждёт: в коде пауза или функция UART, которая ждёт линию"
	note "Ожиданий в прошивке нет (требование Н2 ТЗ 2.3). Байт кладут в очередь, только если uart_is_writable(), а принятое забирает задача после конца передачи."
else
	ok "Прошивка не ждёт ни очередь UART, ни паузу"
fi
if [ -n "$TASK_C" ] && grep -Eq 'printf|puts[[:space:]]*\(' "$(fw_code "$TASK_C")"; then
	fail "uart-task.c: задача печатает сама"
	note "Принятые байты задача отдаёт функции, полученной при запуске. Печатает api."
elif [ -n "$TASK_H" ] && grep -Eq '\(\*[[:space:]]*[a-z_]+\)[[:space:]]*\(' "$(fw_code "$TASK_H")"; then
	ok "uart-task: принятое отдаётся функции, переданной при запуске"
elif [ -n "$TASK_H" ]; then
	fail "uart-task.h: нет типа указателя на функцию для принятых байтов"
fi
MAIN="$FW_SRC/main.c"
[ -f "$MAIN" ] && match "$(fw_code "$MAIN")" 'uart_task_handle[[:space:]]*\(' \
	"main.c: обработчик задачи обмена вызывается в суперцикле" \
	"main.c: нет вызова uart_task_handle()"

LOGIC="$(mktemp)"
find "$FW_SRC/logic" -type f \( -name '*.c' -o -name '*.h' \) 2>/dev/null | sort |
	while read -r f; do cat "$(fw_code "$f")"; done > "$LOGIC"
if grep -Eq '#include[[:space:]]*[<"](pico|hardware)/|(^|[^a-z_])(uart|gpio)_(init|set_[a-z_]+|is_[a-z_]+|get_hw)[[:space:]]*\(' "$LOGIC"; then
	fail "logic: код логики обращается к SDK"
	note "UART — железо, ему место в platform. Задача зовёт функции platform."
else
	ok "logic: логика по-прежнему без SDK"
fi

build_project "$FW_SRC"

if device_log "$FW_SRC/device-3-3-2.log" "3.3.2"; then
	TABLE="$(exchange_table "$DEVICE_LOG")"
	reply() {
		exchange_replies "$TABLE" "$1" "$2" | cut -f2 | tail -n +2
	}
	S='[[:space:]]+'
	LINE32='0123456789ABCDEFGHIJKLMNOPQRSTUV'

	if reply help 1 | grep -Eq '^loop[[:space:]]+[^[:space:]]' && reply help 1 | grep -Eq '^echo[[:space:]]+[^[:space:]]'; then
		ok "help перечисляет loop и echo со справкой"
	else
		fail "В ответе help нет loop или echo со справкой"
	fi

	if reply loop 1 | grep -Eq '^loop: internal$' && reply loop 2 | grep -Eq '^loop: pins$'; then
		ok "loop internal и loop pins отвечают loop: internal и loop: pins"
	else
		fail "Ответы на loop internal и loop pins не loop: internal и loop: pins"
	fi

	# echo_check <номер вызова> <строка> <подпись>
	echo_check() {
		local answer
		answer="$(reply echo "$1" | grep -E '^rx:' | head -1)"
		if echo "$answer" | grep -Eq "^rx:$S$2${S}err:${S}none$"; then
			ok "$3: строка $2 вернулась, ошибок нет"
		else
			fail "$3: ответ не rx: $2 err: none${answer:+ — пришло «${answer}»}"
			note "$4"
		fi
	}

	echo_check 1 ping "Петля LBE, echo ping" "С битом LBE строка не выходит на выводы. Если она не вернулась, модуль не настроен или бит LBE не стоит."
	echo_check 2 "$LINE32" "Петля LBE, строка из 32 символов" "32 символа помещаются и в очередь передачи, и в очередь приёма. Принятое читается целиком после конца передачи."
	echo_check 3 ping "Перемычка, echo ping" "Без LBE строка идёт через GP0 и GP1. Проверьте перемычку и функцию UART у обоих выводов."
	echo_check 4 "$LINE32" "Перемычка, строка из 32 символов" "Строка вернулась с петлёй LBE, но не через выводы — ищите ошибку в перемычке или в выводах."

	if reply echo 5 | grep -Eq '^error: text longer than 32$'; then
		ok "echo из 33 символов отклонён: error: text longer than 32"
	else
		fail "echo из 33 символов не ответил error: text longer than 32"
	fi
	if reply echo 6 | grep -Eq '^error: usage echo <text>$' && reply loop 3 | grep -Eq '^error: usage loop internal\|pins$'; then
		ok "echo без аргумента и loop xx отклонены"
	else
		fail "echo без аргумента или loop xx не ответили error: usage"
	fi
fi

finish "$TITLE"
