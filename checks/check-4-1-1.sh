#!/usr/bin/env bash
# Проверка практики 4.1. Только очищенный код, ответы по шагам обмена.
set -u
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
. "$LIB/report.sh"
. "$LIB/build.sh"
. "$LIB/code.sh"
. "$LIB/cmake.sh"
. "$LIB/device.sh"
. "$LIB/exchange.sh"
. "$LIB/firmware.sh"

fw_start "Задание 4.1.1 — Передача между контроллерами SPI" 411-peripheral-link "${1:-.}" "${2:-}"
require() {
    if grep -Eq "$2" "$1"; then
        ok "$3"
    else
        fail "$3"
        note "$4"
    fi
}
CODE="$(fw_project_code)"
CMAKE="$(mktemp)"
if [ -f "$FW_SRC/CMakeLists.txt" ]; then
    cat "$(cmake_only "$(cmake_flatten "$FW_SRC/CMakeLists.txt")")" > "$CMAKE"
else
    fail "Нет CMakeLists.txt"
    note "Создайте проект на основе 231-firmware-template, шаг 1 п4.1.1."
fi
if [ -f "$FW_SRC/check-4-1-1.py" ]; then
    script_match "$(python_only "$(normalize "$FW_SRC/check-4-1-1.py")")" 'STEPS[[:space:]]*=' \
        "Скрипт опроса содержит сценарий" "Скрипт опроса отличается от пособия"
else
    script_warn "Нет check-4-1-1.py"
fi
require "$CMAKE" 'target_link_libraries[[:space:]]*\([[:space:]]*platform[^)]*hardware_spi' "platform подключает hardware_spi" "Подключите hardware_spi к platform в CMakeLists.txt."
require "$CODE" '(^|[^A-Za-z0-9_])spi_set_slave[[:space:]]*\([[:space:]]*spi1[[:space:]]*,[[:space:]]*true' "SPI1 работает ведомым" "Включите ведомый режим SPI1, шаг 3 п4.1.1."
require "$CODE" '(^|[^A-Za-z0-9_])spi_init[[:space:]]*\([[:space:]]*spi0' "SPI0 инициализирован" "SPI0 должен формировать такт, шаг 3 п4.1.1."
require "$CODE" 'GPIO_FUNC_SPI' "Выводы назначены SPI" "Назначьте функции SPI выводам по схеме."
require "$CODE" 'SPI_CPHA_1' "SPI использует вторую фазу для непрерывного CS" "Для RP2040 используйте режим 3, шаг 3 п4.1.1."
require "$CODE" '(^|[^A-Za-z0-9_])gpio_put[[:space:]]*\(' "Выбор ведомого управляется GPIO" "Опустите CS перед передачей и поднимите после неё."
require "$CODE" 'time_reached|absolute_time_diff_us|time_us_' "Ожидание приёма ограничено" "Не допускайте зависания при разомкнутом такте или CS."
require "$CODE" '(^|[^A-Za-z0-9_])spi_is_readable[[:space:]]*\([[:space:]]*spi1' "Программа читает фактический приём SPI1" "Результат должен пройти по проводу в очередь SPI1."

build_project "$FW_SRC"
if device_log "$FW_SRC/device-4-1-1.log" "4.1.1"; then
    TABLE="$(exchange_table "$DEVICE_LOG")"
    expect() {
        local step answers
        step="$(awk -v wanted="$1" -v nth="${4:-1}" '
            /-->/ {
                step++
                cmd=$0; sub(/^.*-->[[:space:]]*/, "", cmd)
                gsub(/[[:space:]]+/, " ", cmd); sub(/ $/, "", cmd)
                if (cmd == wanted) { seen++; if (seen == nth) { print step; exit } }
            }' "$DEVICE_LOG")"
        answers="$(echo "$TABLE" | awk -F '\t' -v s="$step" \
            '$1 == s && $4 >= $3 && $4 - $3 <= 0.4 { text=$5; for (i=6; i<=NF; i++) text=text "\t" $i; print text }')"
        if [ -n "$step" ] && echo "$answers" | grep -Eq "$2"; then
            ok "$3"
        else
            fail "$3"
            note "Команда «$1» должна дать ответ по образцу п4.1.1 в течение 0,4 с. Проверьте подключение, адрес и обработчик."
        fi
    }
    S='[[:space:]]+'
    expect "spi_send hello" "^spi:${S}hello${S}bytes${S}5${S}match${S}yes$" "Строка hello принята целиком" 1
    expect "spi_send Pico" "^spi:${S}Pico${S}bytes${S}4${S}match${S}yes$" "Другая строка принята целиком" 1
    expect "spi_send 0123456789ABCDEFGHIJKLMNOPQRSTUV" "^spi:${S}0123456789ABCDEFGHIJKLMNOPQRSTUV${S}bytes${S}32${S}match${S}yes$" "Строка из 32 символов принята целиком" 1
    expect "spi_send 0123456789ABCDEFGHIJKLMNOPQRSTUVW" "^error:${S}text${S}longer${S}than${S}32$" "Строка из 33 символов отклонена" 1
    expect "spi_send" "^error:${S}usage${S}spi_send${S}<text>$" "Команда без строки отклонена" 1
    expect "uptime" "^uptime:${S}[0-9]+${S}ms$" "После обмена прибор отвечает по USB"
fi
finish "$TITLE"
