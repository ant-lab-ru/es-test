#!/usr/bin/env bash
# Задание п3.3.1 «Драйверы линии».
# Проект 331-uart, копия 231-firmware-template. Вывод GP22 через резистор 1 кОм ведёт
# узел с конденсатором 4,7 мкФ, АЦП на GP26 следит за узлом. Задача logic/edge-task
# без ожиданий измеряет фронт вверх до 2 В и фронт вниз до 1,3 В. Команда edge pp —
# двухтактный режим, edge od — открытый сток с внутренней подтяжкой.
# Читает код и README, собирает проект и разбирает лог: фронты обоих режимов, ошибки.
# Использование: check-3-3-1.sh <путь к репозиторию> [папка проекта]
set -u

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
. "$LIB/report.sh"
. "$LIB/build.sh"
. "$LIB/code.sh"
. "$LIB/cmake.sh"
. "$LIB/device.sh"
. "$LIB/exchange.sh"
. "$LIB/firmware.sh"

fw_start "Задание 3.3.1 — Драйверы линии" 331-uart "${1:-.}" "${2:-}"

fw_need PLATFORM_C platform.c
fw_need TASK_H edge-task.h
fw_need TASK_C edge-task.c
for f in main.c README.md check-3-3-1.py device-3-3-1.log; do
	if [ -f "$FW_SRC/$f" ]; then
		ok "Файл $f на месте"
	else
		file_missing "$f"
	fi
done

CMAKE="$FW_SRC/CMakeLists.txt"
if [ -f "$CMAKE" ]; then
	FLAT="$(cmake_flatten "$CMAKE")"
	match "$FLAT" 'project[[:space:]]*\([[:space:]]*331_uart[[:space:]]*\)' \
		"CMakeLists.txt: проект назван 331_uart" \
		"CMakeLists.txt: в project() не 331_uart"
	match "$FLAT" 'target_link_libraries[[:space:]]*\([[:space:]]*platform[^)]*hardware_adc' \
		"CMakeLists.txt: platform подключает hardware_adc" \
		"CMakeLists.txt: hardware_adc не подключена к platform"
fi

if [ -n "$PLATFORM_C" ]; then
	PLAT="$(fw_code "$PLATFORM_C")"
	match "$PLAT" 'adc_read[[:space:]]*\(' \
		"platform.c: напряжение узла читает АЦП" \
		"platform.c: нет вызова adc_read()"
	if grep -Eq 'gpio_pull_up[[:space:]]*\(' "$PLAT" && grep -Eq 'GPIO_IN' "$PLAT" && grep -Eq 'GPIO_OUT' "$PLAT"; then
		ok "platform.c: открытый сток — подтяжка вверх и переключение направления вывода"
	else
		fail "platform.c: нет открытого стока — gpio_pull_up() и переключения GPIO_IN и GPIO_OUT"
		note "Открытый сток RP2040 получают из двухтактного драйвера: в регистре выхода ноль, а переключают направление (т3.3.2)."
	fi
fi

CODE="$(fw_project_code)"
if grep -Eq '(^|[^a-z_])(sleep_(ms|us)|busy_wait_[a-z_]+)[[:space:]]*\(' "$CODE"; then
	fail "В прошивке есть пауза sleep_ или busy_wait_"
	note "Ожиданий в прошивке нет (требование Н2 ТЗ 2.3). Фронт измеряет задача: на каждой итерации она читает АЦП и сравнивает с порогом."
else
	ok "В прошивке нет пауз"
fi
if [ -n "$TASK_C" ] && grep -Eq 'printf|puts[[:space:]]*\(' "$(fw_code "$TASK_C")"; then
	fail "edge-task.c: задача печатает сама"
	note "Результат задача отдаёт функции, полученной при запуске. Печатает api."
elif [ -n "$TASK_H" ] && grep -Eq '\(\*[[:space:]]*[a-z_]+\)[[:space:]]*\(' "$(fw_code "$TASK_H")"; then
	ok "edge-task: результат отдаётся функции, переданной при запуске"
elif [ -n "$TASK_H" ]; then
	fail "edge-task.h: нет типа указателя на функцию для результата"
fi
MAIN="$FW_SRC/main.c"
[ -f "$MAIN" ] && match "$(fw_code "$MAIN")" 'edge_task_handle[[:space:]]*\(' \
	"main.c: обработчик задачи фронтов вызывается в суперцикле" \
	"main.c: нет вызова edge_task_handle()"

LOGIC="$(mktemp)"
find "$FW_SRC/logic" -type f \( -name '*.c' -o -name '*.h' \) 2>/dev/null | sort |
	while read -r f; do cat "$(fw_code "$f")"; done > "$LOGIC"
if grep -Eq '#include[[:space:]]*[<"](pico|hardware)/|(^|[^a-z_])(adc|gpio)_[a-z_]+[[:space:]]*\(' "$LOGIC"; then
	fail "logic: код логики обращается к SDK"
	note "АЦП и вывод GP22 — железо, им место в platform. Задача зовёт функции platform."
else
	ok "logic: логика по-прежнему без SDK"
fi

RAW_README="$FW_SRC/README.md"
if [ -f "$RAW_README" ]; then
	TEXT="$(normalize "$RAW_README")"
	if grep -Eq '4[.,]7' "$TEXT" && grep -Eq '50' "$TEXT" && grep -Eq '80' "$TEXT"; then
		ok "README.md: есть расчёт τ для 1 кОм и 4,7 мкФ и для подтяжки 50–80 кОм"
	else
		fail "README.md: нет расчёта τ = R·C для 1 кОм и 4,7 мкФ и для подтяжки 50–80 кОм"
		note "Запишите расчёт для обоих режимов и измеренные времена рядом с ним (п3.3.1, шаг 7)."
	fi
fi

build_project "$FW_SRC"

if device_log "$FW_SRC/device-3-3-1.log" "3.3.1"; then
	TABLE="$(exchange_table "$DEVICE_LOG")"
	reply() {
		exchange_replies "$TABLE" "$1" "$2" | cut -f2 | tail -n +2
	}

	if grep -Eq '^[[:space:]]*[0-9.]+ <-- project: 331-uart$' "$DEVICE_LOG"; then
		ok "Паспорт прибора называет проект 331-uart"
	else
		fail "В ответе info нет project: 331-uart"
		note "Имя проекта задаёт FIRMWARE_PROJECT в firmware.h."
	fi

	if reply help 1 | grep -Eq '^edge[[:space:]]+[^[:space:]]'; then
		ok "help перечисляет edge со справкой"
	else
		fail "В ответе help нет edge со справкой"
	fi

	# edge_check <номер вызова> <режим> <подпись>
	edge_check() {
		local answer rise fall
		answer="$(reply edge "$1" | grep -E "^edge $2:" | head -1)"
		if ! echo "$answer" | grep -Eq "^edge $2:[[:space:]]+rise[[:space:]]+[0-9]+(\.[0-9]+)?[[:space:]]+ms,[[:space:]]+fall[[:space:]]+[0-9]+(\.[0-9]+)?[[:space:]]+ms$"; then
			fail "$3: ответ не edge $2: rise <мс> ms, fall <мс> ms${answer:+ — пришло «${answer}»}"
			note "timeout значит, что порог не достигнут за 2 с: проверьте цепь — резистор, конденсатор и провод к GP26."
			return
		fi
		rise="$(echo "$answer" | sed -E 's/.*rise[[:space:]]+([0-9.]+).*/\1/')"
		fall="$(echo "$answer" | sed -E 's/.*fall[[:space:]]+([0-9.]+).*/\1/')"
		if [ "$2" = pp ]; then
			if awk -v r="$rise" -v f="$fall" 'BEGIN { exit !(r >= 1 && r <= 20 && f >= 1 && f <= 20 && r / f >= 0.5 && r / f <= 2) }'; then
				ok "$3: фронт вверх $rise мс, фронт вниз $fall мс — единицы миллисекунд и близки"
			else
				fail "$3: фронт вверх $rise мс, фронт вниз $fall мс, а в двухтактном режиме оба около 5 мс"
				note "Через 1 кОм и 4,7 мкФ τ = 4,7 мс. Проверьте номиналы и то, что вывод в двухтактном режиме не подтянут."
			fi
		else
			if awk -v r="$rise" -v f="$fall" 'BEGIN { exit !(r >= 100 && r <= 2000 && f >= 1 && f <= 20) }'; then
				ok "$3: фронт вверх $rise мс через подтяжку, фронт вниз $fall мс через ключ"
			else
				fail "$3: фронт вверх $rise мс, фронт вниз $fall мс, а у открытого стока вверх дольше 100 мс, вниз единицы мс"
				note "Отпущенную линию поднимает только внутренняя подтяжка 50–80 кОм. Если фронт вверх короткий, в регистр выхода записана единица."
			fi
		fi
	}

	edge_check 1 pp "Первый замер edge pp"
	edge_check 2 od "Первый замер edge od"
	edge_check 3 pp "Второй замер edge pp"
	edge_check 4 od "Второй замер edge od"

	if reply edge 5 | grep -Eq '^error: usage edge pp\|od$' && reply edge 6 | grep -Eq '^error: usage edge pp\|od$'; then
		ok "edge с неверным аргументом и без него отклонён: error: usage edge pp|od"
	else
		fail "edge xx или edge без аргумента не ответил error: usage edge pp|od"
	fi
fi

finish "$TITLE"
