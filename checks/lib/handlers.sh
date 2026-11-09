#!/usr/bin/env bash
# Обработчики прерываний и будильников в коде прибора. Подключается проверками
# занятия 3.2: в обработчике нельзя печатать, ждать и обновлять сторожевой таймер.
#
# handler_names <файл без комментариев> — имена функций, которые код назначает
# обработчиками: irq_set_exclusive_handler(…, имя) и add_repeating_timer_*(…, имя, …).
handler_names() {
	sed -nE \
		-e 's/.*irq_set_exclusive_handler[[:space:]]*\([^,]*,[[:space:]]*([A-Za-z_][A-Za-z0-9_]*).*/\1/p' \
		-e 's/.*add_repeating_timer_(ms|us)[[:space:]]*\([^,]*,[[:space:]]*([A-Za-z_][A-Za-z0-9_]*).*/\2/p' \
		-e 's/.*add_alarm_in_(ms|us)[[:space:]]*\([^,]*,[[:space:]]*([A-Za-z_][A-Za-z0-9_]*).*/\2/p' \
		"$1" | sort -u
}

# handler_bodies <файл без комментариев> — тела всех обработчиков подряд
handler_bodies() {
	local name
	for name in $(handler_names "$1"); do
		function_body "$1" "$name"
	done
}
