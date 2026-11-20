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

fw_start "Задание 4.1.2 — Обмен между контроллерами I²C" 411-peripheral-link "${1:-.}" "${2:-}"
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
if [ -f "$FW_SRC/check-4-1-2.py" ]; then
    script_match "$(python_only "$(normalize "$FW_SRC/check-4-1-2.py")")" 'STEPS[[:space:]]*=' \
        "Скрипт опроса содержит сценарий" "Скрипт опроса отличается от пособия"
else
    script_warn "Нет check-4-1-2.py"
fi
require "$CMAKE" 'target_link_libraries[[:space:]]*\([[:space:]]*platform[^)]*pico_i2c_slave' "platform подключает pico_i2c_slave" "Подключите библиотеку событий ведомого из SDK."
require "$CODE" '(^|[^A-Za-z0-9_])i2c_slave_init[[:space:]]*\([[:space:]]*i2c1' "I²C1 настроен ведомым" "Назначьте адрес 0x42 и свой обработчик."
require "$CODE" 'I2C_SLAVE_RECEIVE' "Обрабатывается приём номера и значения" "Напишите обработку принятых байтов, шаг 4 п4.1.2."
require "$CODE" 'I2C_SLAVE_REQUEST' "Обрабатывается запрос регистра" "На запрос ведущего нужно положить значение в очередь передачи."
require "$CODE" 'I2C_SLAVE_FINISH' "Обрабатывается завершение фазы" "Сбросьте ожидание номера, сохранив выбранный регистр."
require "$CODE" '(^|[^A-Za-z0-9_])i2c_read_byte_raw[[:space:]]*\(' "Принятые байты забираются из очереди" "Прочитайте номер и значение, не подставляйте их по команде USB."
require "$CODE" '(^|[^A-Za-z0-9_])i2c_write_byte_raw[[:space:]]*\(' "Ответ ведомого попадает в очередь передачи" "Ведущий должен получить содержимое регистра по проводам."
require "$CODE" '(^|[^A-Za-z0-9_])i2c_write_timeout_us[[:space:]]*\(' "Запись ведущего ограничена таймаутом" "Проверьте число переданных байтов."
require "$CODE" '(^|[^A-Za-z0-9_])i2c_read_timeout_us[[:space:]]*\(' "Чтение ведущего ограничено таймаутом" "Проверьте число принятых байтов до использования результата."
require "$CODE" 'REG_CONFIG' "Есть изменяемый регистр CONFIG" "Реализуйте правила своей карты регистров, шаг 3 п4.1.2."

build_project "$FW_SRC"
if device_log "$FW_SRC/device-4-1-2.log" "4.1.2"; then
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
            note "Команда «$1» должна дать ответ по образцу п4.1.2 в течение 0,4 с. Проверьте подключение, адрес и обработчик."
        fi
    }
    S='[[:space:]]+'
    expect "i2c_read 0x42 0x00" "^i2c:${S}addr${S}0x42${S}reg${S}0x00${S}value${S}0xa5$" "ID возвращает 0xa5" 1
    expect "i2c_read 0x42 0x01" "^i2c:${S}addr${S}0x42${S}reg${S}0x01${S}value${S}0x01$" "VERSION возвращает 0x01" 1
    expect "i2c_read 0x42 0x02" "^i2c:${S}addr${S}0x42${S}reg${S}0x02${S}value${S}0x37$" "CONFIG сохраняет 0x37" 1
    expect "i2c_read 0x42 0x02" "^i2c:${S}addr${S}0x42${S}reg${S}0x02${S}value${S}0xc8$" "CONFIG сохраняет 0xc8" 2
    expect "i2c_read 0x42 0x00" "^i2c:${S}addr${S}0x42${S}reg${S}0x00${S}value${S}0xa5$" "Запись не меняет ID" 2
    expect "i2c_read 0x42 0x01" "^i2c:${S}addr${S}0x42${S}reg${S}0x01${S}value${S}0x01$" "Запись не меняет VERSION" 2
    expect "i2c_read 0x42 0xfe" "^i2c:${S}addr${S}0x42${S}reg${S}0xfe${S}value${S}0xff$" "Неизвестный регистр возвращает 0xff" 1
    expect "i2c_read 0x43 0x00" "^error:${S}i2c${S}transfer$" "Свободный адрес даёт ошибку чтения" 1
    expect "i2c_write 0x43 0x02 0x11" "^error:${S}i2c${S}transfer$" "Свободный адрес даёт ошибку записи" 1
    expect "i2c_read 0x42 0x00" "^i2c:${S}addr${S}0x42${S}reg${S}0x00${S}value${S}0xa5$" "После ошибки правильное чтение работает" 3
    expect "i2c_read 0x80 0" "^error:${S}usage${S}i2c_read" "Недопустимый адрес отклонён" 1
    expect "i2c_write 0x42 2 256" "^error:${S}usage${S}i2c_write" "Значение за пределами байта отклонено" 1
    expect "i2c_write 0x42 0x02 0x37" "^i2c:${S}addr${S}0x42${S}reg${S}0x02${S}written${S}0x37$" "Запись CONFIG 0x37 подтверждена"
    expect "i2c_write 0x42 0x02 0xc8" "^i2c:${S}addr${S}0x42${S}reg${S}0x02${S}written${S}0xc8$" "Запись CONFIG 0xc8 подтверждена"
    expect "uptime" "^uptime:${S}[0-9]+${S}ms$" "После обмена прибор отвечает по USB"
fi
finish "$TITLE"
