#!/usr/bin/env bash
# Общие проверки вех 4.1. Названия команд и ответы сверяются по целым строкам.
set -u
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$LIB/report.sh"
. "$LIB/build.sh"
. "$LIB/code.sh"
. "$LIB/cmake.sh"
. "$LIB/firmware.sh"
. "$LIB/device.sh"

fw_start "Задание $CHECKS_TASK — $LESSON_TITLE" 411-i2c-spi "${1:-.}" "${2:-}"
stage="${CHECKS_TASK##*.}"
code="$(fw_project_code)"
flat="$(fw_flat "$code")"
cmake_src="$FW_SRC/CMakeLists.txt"
cmake_code="$(mktemp)"
if [ -f "$cmake_src" ]; then
    cat "$(cmake_only "$(cmake_flatten "$cmake_src")")" > "$cmake_code"
fi

expect_code() {
    if grep -Eq "$1" "$2"; then
        ok "$3"
    else
        fail "$3"
        note "$4"
    fi
}

expect_code 'add_library[[:space:]]*\([[:space:]]*platform[[:space:]]+STATIC' "$cmake_code" 'platform собирается как отдельная цель' 'Сверьте add_library для platform.'
expect_code 'add_library[[:space:]]*\([[:space:]]*logic[[:space:]]+STATIC' "$cmake_code" 'logic собирается как отдельная цель' 'Сверьте add_library для logic.'
expect_code 'logic/api/api[.]c' "$cmake_code" 'Диспетчер API входит в сборку' 'Добавьте logic/api/api.c в цель logic.'
expect_code 'logic/api/api-callbacks[.]c' "$cmake_code" 'Обработчики команд входят в сборку' 'Добавьте logic/api/api-callbacks.c в цель logic.'

main_code="$(mktemp)"
api_code="$(mktemp)"
callbacks_code="$(mktemp)"
for path in main.c logic/api/api.c logic/api/api-callbacks.c; do
    case "$path" in
        main.c) output="$main_code" ;;
        logic/api/api.c) output="$api_code" ;;
        *) output="$callbacks_code" ;;
    esac
    if [ -f "$FW_SRC/$path" ]; then
        cat "$(fw_code "$FW_SRC/$path")" > "$output"
    fi
done
expect_code 'stdio_text_protocol_handle[[:space:]]*\(' "$main_code" 'Команды читаются через библиотеку курса' 'Вызовите stdio_text_protocol_handle в суперцикле ядра 0.'
expect_code 'api_handle[[:space:]]*\(' "$main_code" 'Главный цикл передаёт команды в API' 'После приёма команды вызовите api_handle в main.c.'
expect_code '\.callback[[:space:]]*\(' "$api_code" 'API вызывает обработчик из таблицы' 'Возьмите реализацию api.c из проекта 231-firmware-template.'
expect_code 'api_commands[[:space:]]*\[' "$callbacks_code" 'Таблица команд находится в api-callbacks.c' 'Определите api_commands в logic/api/api-callbacks.c.'
expect_code '"i2c_read_reg"' "$callbacks_code" 'Есть USB-команда i2c_read_reg' 'Добавьте команду чтения одного байта.'
expect_code '"i2c_write_reg"' "$callbacks_code" 'Есть USB-команда i2c_write_reg' 'Добавьте команду записи одного байта.'
expect_code 'i2c_write_timeout_us[[:space:]]*\([[:space:]]*i2c0[[:space:]]*,[^)]*,[[:space:]]*true[[:space:]]*,' "$flat" 'Выбор регистра завершается без STOP' 'Передайте true в аргументе nostop первой фазы чтения.'
expect_code 'i2c_read_timeout_us[[:space:]]*\([[:space:]]*i2c0[[:space:]]*,[^)]*,[[:space:]]*false[[:space:]]*,' "$flat" 'Чтение одного байта завершается STOP' 'Используйте i2c_read_timeout_us с nostop равным false.'
if [ "$stage" -ge 2 ]; then
    expect_code 'spi_write_blocking[[:space:]]*\([[:space:]]*spi0' "$code" 'Ведущий передаёт через SPI0' 'Проверьте реализацию передачи в platform.'
    expect_code 'spi_read_blocking[[:space:]]*\([[:space:]]*spi0' "$code" 'Ведущий читает через SPI0' 'После управляющего байта считайте ответ через spi_read_blocking.'
    expect_code '"spi_write"' "$callbacks_code" 'Есть USB-команда spi_write' 'Добавьте имя и обработчик в таблицу команд.'
    expect_code '"spi_read"' "$callbacks_code" 'Есть USB-команда spi_read' 'Добавьте имя и обработчик в таблицу команд.'

    expect_code 'gpio_pull_down[[:space:]]*\([[:space:]]*4[[:space:]]*\)' "$code" 'Свободный вход MISO подтянут к нулю' 'Добавьте gpio_pull_down(4) при настройке ведущего SPI.'
fi
if [ "$stage" -ge 3 ]; then
    expect_code 'multicore_launch_core1[[:space:]]*\(' "$code" 'Второе ядро запускается' 'Вызовите multicore_launch_core1 из platform.'
    expect_code 'slave_device_init[[:space:]]*\([[:space:]]*\)[[:space:]]*;[^}]*while[[:space:]]*\([[:space:]]*1[[:space:]]*\)[[:space:]]*\{[[:space:]]*slave_device_handle[[:space:]]*\(' "$flat" 'Инициализация и суперцикл ведомого связаны' 'В точке входа ядра 1 вызовите инициализацию и обработчик в цикле.'
    expect_code 'platform_led_set[[:space:]]*\(' "$code" 'Ведомое управляет светодиодом' 'Проверьте GPIO штатного светодиода и его вызов из ведомого.'
    expect_code 'SLAVE_REG_CMD[[:space:]]*=[[:space:]]*0x00' "$code" 'Объявлен регистр CMD' 'Сверьте номер CMD в slave.h.'
    expect_code 'SLAVE_REG_STATE[[:space:]]*=[[:space:]]*0x01' "$code" 'Объявлен регистр STATE' 'Сверьте номер STATE в slave.h.'
    if grep -Eq 'BLINK_PERIOD_MS' "$code" || grep -Eq 'i2c_slave_init[[:space:]]*\(' "$code"; then
        ok 'Есть временное неблокирующее мигание или управление из поздней вехи'
    else
        fail 'Не найдено временное мигание или заменившее его управление'
        note 'Сверьте обработчик ведомого в третьем или четвёртом задании.'
    fi
fi
if [ "$stage" -ge 4 ]; then
    expect_code 'i2c_slave_init[[:space:]]*\([[:space:]]*i2c1' "$code" 'I²C1 настроен ведомым' 'Инициализируйте I²C1 на ядре 1.'
    expect_code 'i2c_read_byte_raw[[:space:]]*\(' "$code" 'Принятые байты читаются из аппаратной очереди' 'При I2C_SLAVE_RECEIVE заберите байты из RX FIFO.'
    expect_code 'i2c_write_byte_raw[[:space:]]*\(' "$code" 'Ответ записывается в аппаратную очередь' 'При I2C_SLAVE_REQUEST положите значение в TX FIFO.'
    expect_code 'I2C_SLAVE_FINISH' "$code" 'Граница фаз I²C обрабатывается' 'Сбросьте фазу приёма, сохранив выбранный номер регистра.'
    expect_code 'atomic_store_explicit[[:space:]]*\(' "$code" 'Состояние сохраняется атомарно' 'Используйте atomic_store_explicit для led_state.'
fi
if [ "$stage" -eq 5 ]; then
    expect_code 'spi_set_slave[[:space:]]*\([[:space:]]*spi1[[:space:]]*,[[:space:]]*true' "$flat" 'SPI1 настроен ведомым' 'Настройте ведомый режим аппаратного SPI1.'
    expect_code 'spi_is_readable[[:space:]]*\([[:space:]]*spi1' "$code" 'Ведомый опрашивает очередь SPI1' 'Забирайте управляющий байт и данные из RX FIFO SPI1.'
    expect_code 'platform_spi_slave_reply[[:space:]]*\([[:space:]]*read_register' "$code" 'SPI читает ту же карту регистров' 'Формируйте ответ на основе read_register.'
    expect_code 'platform_spi_slave_reset[[:space:]]*\(' "$code" 'Очереди SPI подготавливаются к новому кадру' 'При снятии CS подготовьте SPI1 к следующему кадру.'
fi

probe="$FW_SRC/check-4-1-$stage.py"
if [ -f "$probe" ]; then
    script_match "$(python_only "$(normalize "$probe")")" 'list_ports[.]comports' 'Присутствует скрипт опроса' 'Скрипт опроса отличается от пособия'
elif [ "$stage" -ne 3 ]; then
    script_warn "Нет ${probe##*/}"
fi

build_project "$FW_SRC"

# Один ответ на указанном шаге. Порядок проверяем от последнего найденного шага.
last_step=0
expect_exchange() {
    local command="$1" response="$2" label="$3" next
    next="$(awk -v command="$command" -v response="$response" -v previous="$last_step" '
        {
            line = $0
            gsub(/[ \t]+/, " ", line)
            sub(/^ /, "", line)
            sub(/ $/, "", line)
            if (line ~ /^[0-9.]+ --> /) {
                step++; sent = line + 0
                sub(/^[0-9.]+ --> /, "", line)
                wanted = (step > previous && line ~ ("^" command "$"))
            } else if (wanted && line ~ /^[0-9.]+ <-- /) {
                if (line + 0 < sent || line + 0 - sent > 2) next
                sub(/^[0-9.]+ <-- /, "", line)
                if (line ~ ("^" response "$")) { print step; exit }
            }
        }' "$DEVICE_LOG")"
    if [ -n "$next" ]; then
        ok "$label"
        last_step="$next"
    else
        fail "$label"
        note 'Сверьте ответ с примером и переснимите лог на рабочей схеме.'
    fi
}

log="$FW_SRC/device-4-1-$stage.log"
if [ "$stage" -ne 3 ] && device_log "$log" "$CHECKS_TASK"; then
    expect_code '^проект: 411-i2c-spi[[:space:]]*$' "$DEVICE_LOG" 'Лог снят для проекта 411-i2c-spi' 'Переснимите лог скриптом этого задания.'
    help_step="$(awk -v stage="$stage" '
        {
            line = $0
            gsub(/[ \t]+/, " ", line)
            sub(/^ /, "", line)
            sub(/ $/, "", line)
            if (line ~ /^[0-9.]+ --> /) {
                step++
                sent = line + 0
                in_help = line ~ /^[0-9.]+ --> help$/
                heading = i2c_write = i2c_read = spi_write = spi_read = 0
            } else if (in_help && line ~ /^[0-9.]+ <-- / &&
                       line + 0 >= sent && line + 0 - sent <= 2) {
                sub(/^[0-9.]+ <-- /, "", line)
                if (line == "help list of commands") heading = 1
                if (line == "i2c_write_reg <address> <register> <value>") i2c_write = 1
                if (line == "i2c_read_reg <address> <register>") i2c_read = 1
                if (line == "spi_write <cs> <command> <value>") spi_write = 1
                if (line == "spi_read <cs> <command> [pause_us]") spi_read = 1
                if (heading && i2c_write && i2c_read && (stage == 1 || (spi_write && spi_read))) {
                    print step
                    exit
                }
            }
        }' "$DEVICE_LOG")"
    if [ -n "$help_step" ]; then
        ok 'USB-справка содержит команды этой вехи'
        last_step="$help_step"
    else
        fail 'В логе нет полной USB-справки'
        note 'Проверьте таблицу команд и переснимите лог скриптом этого задания.'
    fi
    if [ "$stage" -eq 2 ]; then
        if grep -Eq '^режим SPI: без датчика[[:space:]]*$' "$DEVICE_LOG"; then
            before_spi="$last_step"
            expect_exchange 'spi_read 0x00 0xD0' 'spi: cs 0x00 command 0xD0 value 0x00' 'Без датчика ведущий прочитал нулевой байт'
            if [ "$last_step" -gt "$before_spi" ]; then
                warn 'SPI проверен без датчика. Обмен с ведомым проверяется в 4.1.5.'
            fi
        elif grep -Eq '^режим SPI: BME280[[:space:]]*$' "$DEVICE_LOG"; then
            expect_exchange 'spi_read 0x00 0xD0' 'spi: cs 0x00 command 0xD0 value 0x60' 'ID BME280 прочитан по SPI'
        else
            fail 'В логе не указан режим проверки SPI'
            note 'Запустите check-4-1-2.py. Для четырёхконтактного модуля добавьте --without-sensor.'
        fi
    else
        for address in 0x76 0x77; do
            if grep -Eq -- "-->[[:space:]]+i2c_read_reg[[:space:]]+$address[[:space:]]+0xD0([[:space:]]|$)" "$DEVICE_LOG"; then
                break
            fi
        done
        expect_exchange "i2c_read_reg $address 0xD0" "i2c: addr $address reg 0xD0 value 0x60" 'ID BME280 прочитан по I²C'
        if [ "$stage" -eq 4 ]; then
            expect_exchange 'i2c_write_reg 0x42 0x00 0x65' 'i2c: addr 0x42 reg 0x00 sent 0x65' 'Команда включения отправлена по I²C'
            expect_exchange 'i2c_read_reg 0x42 0x01' 'i2c: addr 0x42 reg 0x01 value 0x01' 'I²C читает состояние включённого LED'
            expect_exchange 'i2c_write_reg 0x42 0x01 0x00' 'i2c: addr 0x42 reg 0x01 sent 0x00' 'Состояние записано по I²C'
            expect_exchange 'i2c_read_reg 0x42 0x01' 'i2c: addr 0x42 reg 0x01 value 0x00' 'I²C читает состояние выключенного LED'
        elif [ "$stage" -eq 5 ]; then
            expect_exchange 'i2c_read_reg 0x43 0x01' 'error: i2c transfer' 'Свободный адрес даёт ошибку передачи'
            expect_exchange 'spi_write 0x01 0x00 0x65' 'spi: cs 0x01 command 0x00 sent 0x65' 'Команда включения отправлена по SPI'
            expect_exchange 'i2c_read_reg 0x42 0x01' 'i2c: addr 0x42 reg 0x01 value 0x01' 'Изменение по SPI видно через I²C'
            expect_exchange 'i2c_write_reg 0x42 0x01 0x00' 'i2c: addr 0x42 reg 0x01 sent 0x00' 'Состояние записано по I²C'
            expect_exchange 'spi_read 0x01 0x81 0x[0-9A-F]{2}' 'spi: cs 0x01 command 0x81 value 0x00' 'Изменение по I²C видно через SPI'
            expect_exchange 'i2c_write_reg 0x42 0x00 0x65' 'i2c: addr 0x42 reg 0x00 sent 0x65' 'Включение по I²C подтверждено'
            expect_exchange 'spi_read 0x01 0x81 0x[0-9A-F]{2}' 'spi: cs 0x01 command 0x81 value 0x01' 'SPI читает изменённое состояние'
        fi
    fi
fi

finish "$TITLE"
