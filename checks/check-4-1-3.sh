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

fw_start "Задание 4.1.3 — Чтение идентификатора BME280" 411-peripheral-link "${1:-.}" "${2:-}"
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
if [ -f "$FW_SRC/check-4-1-3.py" ]; then
    script_match "$(python_only "$(normalize "$FW_SRC/check-4-1-3.py")")" 'STEPS[[:space:]]*=' \
        "Скрипт опроса содержит сценарий" "Скрипт опроса отличается от пособия"
else
    script_warn "Нет check-4-1-3.py"
fi
require "$CODE" '(^|[^A-Za-z0-9_])i2c_write_timeout_us[[:space:]]*\(' "Номер регистра передаётся с таймаутом" "Первая фаза должна успешно передать один байт."
require "$CODE" '(^|[^A-Za-z0-9_])i2c_read_timeout_us[[:space:]]*\(' "Значение читается с таймаутом" "При неудаче нельзя печатать старый ID."
if [ -f "$FW_SRC/README.md" ]; then
    RAW_README="$(normalize "$FW_SRC/README.md")"
    for word in '0x7[67]' '0xd0' '0x60' '5\.4\.1' 'BME280'; do
        require "$RAW_README" "$word" "README описывает $word" "Запишите адрес устройства, регистр, ID и раздел документации, шаг 4 п4.1.3."
    done
else
    fail "Нет README.md проекта"
    note "Опишите подключение и результат чтения ID, шаг 4 п4.1.3."
fi

build_project "$FW_SRC"
if device_log "$FW_SRC/device-4-1-3.log" "4.1.3"; then
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
            note "Команда «$1» должна дать ответ по образцу п4.1.3 в течение 0,4 с. Проверьте подключение, адрес и обработчик."
        fi
    }
    S='[[:space:]]+'
    ADDRESS="$(awk '/-->/ && $3 == "i2c_read" && $5 == "0xd0" && ($4 == "0x76" || $4 == "0x77") { print $4; exit }' "$DEVICE_LOG")"
    if [ -z "$ADDRESS" ]; then ADDRESS=0x76; fi
    expect "i2c_read $ADDRESS 0xd0" "^i2c:${S}addr${S}$ADDRESS${S}reg${S}0xd0${S}value${S}0x60$" "BME280 возвращает ID 0x60" 1
    expect "i2c_read 0x43 0xd0" "^error:${S}i2c${S}transfer$" "Свободный адрес даёт ошибку"
    expect "i2c_read $ADDRESS 0xd0" "^i2c:${S}addr${S}$ADDRESS${S}reg${S}0xd0${S}value${S}0x60$" "После ошибки ID снова читается" 2
    BAD_STEP="$(awk '/-->/ {step++} /-->/ && $3 == "i2c_read" && $4 == "0x43" {print step; exit}' "$DEVICE_LOG")"
    if echo "$TABLE" | awk -F '\t' -v s="$BAD_STEP" '$1 == s {print $5}' | grep -Eq '^i2c:[[:space:]]+addr'; then
        fail "Ошибка сопровождается старым значением регистра"
        note "Выходите из обработчика сразу после сообщения об ошибке."
    else
        ok "Ошибка не выдаёт старое значение за новое"
    fi
    expect "uptime" "^uptime:${S}[0-9]+${S}ms$" "После обмена прибор отвечает по USB"
fi
finish "$TITLE"
