#!/usr/bin/env python3
"""Дописывает в копию эталона комментарии, которые не должны менять итог проверки.

Запуск: poison.py <папка> — файлы меняются на месте. Сборка эту копию не проходит."""
import os
import sys

C = ('gpio_put(25, 1); gpio_set_dir(25, GPIO_OUT); gpio_get(15); gpio_init(1); printf("x"); puts("x"); '
     "putchar('x'); sleep_ms(1); sleep_us(1); busy_wait_us(1); LED_PIN BUTTON_PIN get_button_debounce DEBOUNCE_MS "
     'COMMAND_COUNT strcmp(cmd, "x") sscanf(a, b) getchar time_us_32() time_us_64() x >> 1 '
     '#include "pico/stdlib.h" #include "hardware/gpio.h" #include <pico/stdlib.h> #include "log.h" '
     '#include "device.h" #include "systime.h" #include "profiling.h" #include "stdio-text-protocol.h" '
     '"mem_info" "fw_info" "boot_info" "dev_info" "clk_info" "clk_sys_low" "clk_sys_default" "help" "info" '
     '"uptime" "led_on" "button" "pi" "pi_start" "profiling" "profiling_reset" "calc_pi" "main_time_exec" '
     '"main_time_reset" device DEVICE_ led period adc_read() adc_init() dma_channel_start(0) pwm_set_wrap(0, 1) '
     'watchdog_update() add_repeating_timer_ms(1) 0.706 dma_channel_wait_for_finish_blocking(0) '
     'while (dma_channel_is_busy(0)) fwrite(a) while (1) for (;;) float double a / b device_card struct info_t '
     '#define FIRMWARE_VERSION "1.0.0"')
CMAKE = ('pico_stdlib hardware_adc PUBLIC pico_stdlib libs/foo.c add_library(x) '
         'target_link_libraries(logic PUBLIC pico_stdlib) target_link_libraries(x PUBLIC pico_stdlib)')


def wrap(lines, head, comment, skip):
    """Комментарии в начале и в конце файла и в хвосте каждой строки кода."""
    tail = [line if not line.strip() or line.rstrip().endswith('\\') or line.lstrip().startswith(skip)
            else line + comment for line in lines]
    return head + tail + head


for folder, dirs, files in os.walk(sys.argv[1]):
    dirs[:] = [d for d in dirs if d not in ('build', '.git')]
    for name in files:
        path = os.path.join(folder, name)
        project = os.path.relpath(path, sys.argv[1]).split(os.sep)[0].replace('-', '_')
        if name.endswith(('.c', '.h')):
            head = ['// ' + C, '/* ' + C + ' */', '/*', ' * ' + C, ' */']
            args = (head, ' // пояснение (см. выше) } { ) ; gpio_put(1, 1); printf("x");', ('#', '//', '/*', '*'))
        elif name == 'CMakeLists.txt':
            head = ['# проект ' + project + ' ' + CMAKE, '#[[ ' + CMAKE, ' ' + CMAKE, ']]']
            args = (head, ' # пояснение (см. задание) ' + project + ' pico_stdlib', ('#',))
        elif name.endswith('.py'):
            args = (['# import os'], '  # пояснение (см. задание)', ('#',))
        else:
            continue
        with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
            lines = f.read().split('\n')
        with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
            f.write('\n'.join(wrap(lines, *args)))
