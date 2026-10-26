#!/usr/bin/env bash
# Задание п3.1.1 «Измерение напряжения».
# Проект 311-adc — копия шаблона 231-firmware-template. АЦП подключён в модуле platform,
# команда get_voltage отвечает напряжением на входе GP26. Читает код, собирает проект
# и разбирает лог прогона на плате.
# Проверка переживает следующие задания занятия: они только добавляют команды и модули.
# Использование: check-3-1-1.sh <путь к репозиторию> [папка проекта]
set -u

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
. "$LIB/report.sh"
. "$LIB/build.sh"
. "$LIB/code.sh"
. "$LIB/cmake.sh"
. "$LIB/device.sh"
. "$LIB/exchange.sh"
. "$LIB/firmware.sh"

fw_start "Задание 3.1.1 — Измерение напряжения" 311-adc "${1:-.}" "${2:-}"

for f in platform/platform.h platform/platform.c logic/api/api-callbacks.c firmware.h main.c \
	check-3-1-1.py device-3-1-1.log; do
	if [ -f "$FW_SRC/$f" ]; then
		ok "Файл $f на месте"
	else
		fail "В проекте нет файла $f"
		note "Проект заводится копией папки 231-firmware-template, раскладка шаблона сохраняется."
	fi
done

LEFT="$(cd "$FW_SRC" && ls check-2-3-*.py device-2-3-*.log 2>/dev/null | tr '\n' ' ')"
if [ -z "$LEFT" ]; then
	ok "Скрипт и лог приёмки шаблона в новый проект не перенесены"
else
	warn "В проекте остались файлы занятия 2.3: $LEFT"
	note "Они относятся к 231-firmware-template. В копии их удаляют вместе с папкой build."
fi


FIRMWARE_H="$FW_SRC/firmware.h"
if [ -f "$FIRMWARE_H" ]; then
	match "$(fw_code "$FIRMWARE_H")" 'FIRMWARE_PROJECT[[:space:]]+"311-adc"' \
		"firmware.h: имя проекта 311-adc" \
		"firmware.h: в FIRMWARE_PROJECT не 311-adc"
fi

CMAKE="$FW_SRC/CMakeLists.txt"
if [ -f "$CMAKE" ]; then
	FLAT="$(cmake_flatten "$CMAKE")"
	match "$FLAT" 'project[[:space:]]*\([[:space:]]*311_adc[[:space:]]*\)' \
		"CMakeLists.txt: имя проекта 311_adc задано в project()" \
		"CMakeLists.txt: в project() не 311_adc"
	PLATFORM_LINK="$(grep -Eo 'target_link_libraries[[:space:]]*\([[:space:]]*platform[[:space:]][^)]*' "$FLAT")"
	if echo "$PLATFORM_LINK" | grep -Eq 'hardware_adc'; then
		ok "CMakeLists.txt: platform подключает hardware_adc"
	else
		fail "CMakeLists.txt: platform не подключает hardware_adc"
		note "Функции АЦП лежат в библиотеке SDK hardware_adc. С АЦП работает platform, ей и подключать."
	fi
	LOGIC_LINK="$(grep -Eo 'target_link_libraries[[:space:]]*\([[:space:]]*logic[[:space:]][^)]*' "$FLAT")"
	if echo "$LOGIC_LINK" | grep -Eq 'pico_|hardware_'; then
		fail "CMakeLists.txt: библиотека logic подключает SDK"
		note "Логика работает с АЦП только через platform, как с выводами в шаблоне."
	else
		ok "CMakeLists.txt: библиотека logic по-прежнему собирается без SDK"
	fi
fi

PLATFORM_C="$FW_SRC/platform/platform.c"
if [ -f "$PLATFORM_C" ]; then
	CODE="$(fw_code "$PLATFORM_C")"
	match "$CODE" '#include[[:space:]]*"hardware/adc\.h"' \
		"platform.c: подключён hardware/adc.h" \
		"platform.c: нет #include \"hardware/adc.h\""
	match "$CODE" 'adc_init[[:space:]]*\(' \
		"platform.c: АЦП инициализируется функцией adc_init()" \
		"platform.c: нет вызова adc_init()"
	if grep -Eq 'adc_gpio_init[[:space:]]*\([[:space:]]*(26|[A-Z_]+)[[:space:]]*\)' "$CODE"; then
		ok "platform.c: вывод отдан аналоговому входу функцией adc_gpio_init()"
	else
		fail "platform.c: нет вызова adc_gpio_init() для вывода GP26"
		note "adc_gpio_init() отключает у вывода цифровую часть и подтяжки, иначе они искажают напряжение."
	fi
	if grep -Eq 'adc_read[[:space:]]*\(|->[[:space:]]*result' "$CODE"; then
		ok "platform.c: результат преобразования читается"
	else
		fail "platform.c: не видно чтения результата АЦП"
		note "Один отсчёт снимает adc_read(): запускает преобразование и ждёт готовности."
	fi
	if grep -Eq '4096|4095|1[[:space:]]*<<[[:space:]]*12' "$CODE"; then
		ok "platform.c: код переводится в напряжение через число уровней 12-разрядного АЦП"
	else
		fail "platform.c: не видно перевода кода в вольты"
		note "Напряжение — код, умноженный на опорное 3,3 В и делённый на 4096 уровней."
	fi
fi

PLATFORM_H="$FW_SRC/platform/platform.h"
if [ -f "$PLATFORM_H" ] && grep -Eq '#include[[:space:]]*[<"](pico|hardware)/' "$(fw_code "$PLATFORM_H")"; then
	fail "platform.h: заголовок подключает SDK"
	note "SDK нужен только platform.c. Правила П4 и П5 части 2 ТЗ 2.3."
fi

LOGIC="$(mktemp)"
find "$FW_SRC/logic" -type f \( -name '*.c' -o -name '*.h' \) 2>/dev/null | sort |
	while read -r f; do cat "$(fw_code "$f")"; done > "$LOGIC"
if grep -Eq '#include[[:space:]]*[<"](pico|hardware)/|adc_[a-z_]+[[:space:]]*\(' "$LOGIC"; then
	fail "logic: код логики обращается к АЦП в обход platform"
	note "Команда получает напряжение у platform. Функции adc_* вызывает только platform.c."
else
	ok "logic: к АЦП логика обращается только через platform"
fi
if grep -Eq '"get_voltage"' "$LOGIC"; then
	ok "api-callbacks.c: команда get_voltage есть в таблице команд"
else
	fail "В таблице команд нет get_voltage"
	note "Новая команда добавляется правкой только api-callbacks.c (правило П2)."
fi

build_project "$FW_SRC"

if device_log "$FW_SRC/device-3-1-1.log" "3.1.1"; then
	TABLE="$(exchange_table "$DEVICE_LOG")"
	reply() {
		exchange_replies "$TABLE" "$1" "$2" | cut -f2 | tail -n +2
	}

	if reply help 1 | grep -Eq '^get_voltage[[:space:]]+[^[:space:]]'; then
		ok "help перечисляет get_voltage со справкой"
	else
		fail "В ответе help нет get_voltage со справкой"
	fi
	if reply info 1 | grep -Eq '^project: 311-adc$'; then
		ok "Паспорт называет проект 311-adc: на плате прошивка нового проекта"
	else
		fail "В паспорте нет строки project: 311-adc"
		note "Проверьте FIRMWARE_PROJECT в firmware.h и что на плату записана свежая прошивка."
	fi

	CALLS="$(exchange_calls "$DEVICE_LOG" get_voltage)"
	GOOD=0
	for n in $(seq 1 "$CALLS"); do
		ANSWER="$(reply get_voltage "$n" | head -1)"
		if echo "$ANSWER" | grep -Eq '^voltage: [0-9]+\.[0-9]{3} V$'; then
			VALUE="$(echo "$ANSWER" | awk '{ print $2 }')"
			if awk -v v="$VALUE" 'BEGIN { exit !(v >= 0 && v <= 3.4) }'; then
				GOOD=$((GOOD + 1))
			else
				fail "get_voltage ответил $VALUE В — вне диапазона АЦП 0–3,3 В"
				note "Проверьте перевод кода в вольты: код до 4095, опорное напряжение 3,3 В."
			fi
		else
			fail "Ответ get_voltage не по формату: $ANSWER"
			note "Ответ — voltage: <напряжение> V, три знака после точки, например voltage: 1.652 V."
		fi
	done
	if [ "$CALLS" -ge 3 ] && [ "$GOOD" -eq "$CALLS" ]; then
		ok "get_voltage ответил $CALLS раза напряжением от 0 до 3,3 В в формате voltage: 1.652 V"
	elif [ "$CALLS" -lt 3 ]; then
		fail "В логе меньше трёх вызовов get_voltage"
		note "Лог снимается скриптом check-3-1-1.py без правок."
	fi
fi

finish "$TITLE"
