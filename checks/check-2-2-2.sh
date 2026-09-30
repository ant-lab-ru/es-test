#!/usr/bin/env bash
# Задание п2.2.2 «Неблокирующее мигание».
# Команда uptime, мигание по разности показаний time_us_64() без пауз в суперцикле.
# Использование: check-2-2-2.sh <путь к репозиторию> [папка проекта]
set -u

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
. "$LIB/report.sh"
. "$LIB/build.sh"
. "$LIB/code.sh"
. "$LIB/device.sh"
. "$LIB/exchange.sh"

TITLE="Задание 2.2.2 — Неблокирующее мигание"
REPO="${1:-.}"
PROJECT="${2:-221-command-time}"
SRC="$REPO/$PROJECT"

if [ ! -d "$SRC" ]; then
	fail "В репозитории нет папки проекта $PROJECT"
	finish "$TITLE"
	exit 1
fi
ok "Папка проекта $PROJECT найдена"

for f in main.c clock/clock.c clock/clock.h check-2-2-2.py device-2-2-2.log; do
	if [ -f "$SRC/$f" ]; then
		ok "Файл $f на месте"
	else
		fail "В проекте нет файла $f"
	fi
done

BODY="$SRC/clock/clock.c"
if [ -f "$BODY" ]; then
	BODY="$(code_only "$(normalize "$BODY")")"
	match "$BODY" 'uptime[[:space:]]*\(' \
		"clock.c: написана функция uptime" \
		"clock.c: нет функции uptime — время с запуска печатает модуль часов"
	match "$BODY" 'time_us_64[[:space:]]*\(' \
		"clock.c: время с запуска берётся из time_us_64" \
		"clock.c: нет вызова time_us_64"
fi

MAIN="$SRC/main.c"
if [ -f "$MAIN" ]; then
	CODE="$(code_only "$(normalize "$MAIN")")"

	if grep -Eq 'sleep_(ms|us)[[:space:]]*\(' "$CODE"; then
		fail "main.c: в коде остался вызов sleep_ms или sleep_us"
		if grep -Eq 'get_button_debounce|DEBOUNCE_MS' "$CODE"; then
			note "Пауза сидит в подавлении дребезга кнопки: задание убирает кнопку из суперцикла вместе с ним."
		else
			note "Пауза останавливает суперцикл целиком. Мигание отмеряют часами, а не ожиданием."
		fi
	else
		ok "main.c: пауз в коде нет"
	fi

	if grep -Eq 'BUTTON_PIN|get_button_debounce' "$CODE"; then
		fail "main.c: опрос кнопки остался в прошивке"
		note "Светодиодом теперь управляет мигание, а подавление дребезга ждёт 20 мс на каждой итерации."
	else
		ok "main.c: опрос кнопки убран"
	fi

	STALE=""
	for cmd in enable disable; do
		grep -Eq "\"$cmd\"" "$CODE" && STALE="$STALE $cmd"
	done
	if [ -z "$STALE" ]; then
		ok "main.c: команд enable и disable в таблице нет"
	else
		fail "main.c: в таблице остались команды:$STALE"
		note "Мигание переключит светодиод через полсекунды, и действие этих команд пропадёт."
	fi

	match "$CODE" 'time_us_64[[:space:]]*\(' \
		"main.c: мигание опирается на часы time_us_64" \
		"main.c: нет вызова time_us_64 — мигание нечем отмерять"

	if grep -Eq '(=|define[[:space:]]+[A-Za-z_]+)[[:space:]]*500(000)?[[:space:]]*;?[[:space:]]*$' "$CODE"; then
		ok "main.c: полупериод мигания задан константой 500 мс"
	else
		fail "main.c: не видно константы полупериода 500 мс"
		note "Задание просит завести константу, например const uint BLINK_HALF_PERIOD_MS = 500."
	fi

	if grep -Eq '[A-Za-z_]+[[:space:]]*-[[:space:]]*[A-Za-z_]+[[:space:]]*>=?' "$CODE"; then
		ok "main.c: срок проверяется разностью «сейчас минус прошлый раз»"
	elif grep -Eq '>=?[[:space:]]*[A-Za-z_]+[[:space:]]*\+' "$CODE"; then
		warn "main.c: срок проверяется сравнением с моментом «прошлый раз плюс полупериод»"
		note "С 32-битными часами такое сравнение ошибается при переполнении. Разность переполнение переживает."
	else
		warn "main.c: не удалось найти сравнение прошедшего времени с полупериодом"
	fi

	match "$CODE" '"uptime"' \
		"main.c: команда uptime есть в таблице команд" \
		"main.c: в таблице команд нет uptime"
fi

build_project "$SRC"

if device_log "$SRC/device-2-2-2.log" "2.2.2"; then
	TABLE="$(exchange_table "$DEVICE_LOG")"

	# Показания uptime и время их прихода: время в логе, миллисекунды прибора.
	UPTIMES="$(echo "$TABLE" | awk -F '\t' '$2 == "uptime" && $5 ~ /^uptime:/ { v = $5; sub(/^uptime:[[:space:]]*/, "", v); sub(/[[:space:]]*ms.*$/, "", v); print $4, v }')"
	COUNT="$(echo "$UPTIMES" | grep -c .)"
	if [ "$COUNT" -ge 3 ]; then
		ok "Плата ответила на uptime $COUNT раза"
	else
		fail "В логе меньше трёх ответов вида uptime: N ms"
		note "Ответ — строка uptime: и число миллисекунд, например uptime: 4939 ms."
	fi

	if [ "$COUNT" -ge 2 ]; then
		GROWING="$(echo "$UPTIMES" | awk 'NR > 1 && $2 <= prev { bad = 1 } { prev = $2 } END { print bad + 0 }')"
		if [ "$GROWING" -eq 0 ]; then
			ok "Показания uptime растут от вызова к вызову"
		else
			fail "Показания uptime не растут"
		fi

		# Часы прибора и время лога идут вровень: разность показаний равна разности моментов.
		PACE="$(echo "$UPTIMES" | awk 'NR == 1 { t = $1; v = $2 } END { log_ms = ($1 - t) * 1000; dev_ms = $2 - v; d = dev_ms - log_ms; if (d < 0) d = -d; print (d <= 50 + log_ms / 20) ? "ok" : dev_ms " " log_ms }')"
		if [ "$PACE" = "ok" ]; then
			ok "uptime идёт вровень со временем в логе"
		else
			fail "По uptime прошло ${PACE%% *} мс, по логу ${PACE##* } мс"
			note "Прибор печатает миллисекунды: показание time_us_64() делится на 1000."
		fi
	fi

	# Быстрый ответ: первая строка после команды приходит за десятую долю секунды.
	SLOW="$(echo "$TABLE" | awk -F '\t' '$1 != last { last = $1; if ($4 - $3 > 0.1) print $2 " " ($4 - $3) }' | head -1)"
	if [ -z "$SLOW" ]; then
		ok "Плата ответила на каждую команду быстрее чем за 0,1 с"
	else
		fail "Плата ответила на ${SLOW%% *} только через ${SLOW##* } с"
		note "Итерация суперцикла слишком длинная: в ней осталось ожидание."
	fi

	BITS="$(echo "$TABLE" | awk -F '\t' '$2 == "boot_info" && $5 ~ /led bit/ { v = $5; sub(/.*led bit[[:space:]]*/, "", v); print v }' | sort -u | grep -c .)"
	if [ "$BITS" -ge 2 ]; then
		ok "Разряд светодиода менялся без команд: светодиод мигает сам"
	else
		fail "Разряд светодиода во всех ответах boot_info одинаковый"
		note "Скрипт спрашивает boot_info раз в 0,8 с. При мигании с периодом в секунду разряд обязан меняться."
	fi
fi

finish "$TITLE"
