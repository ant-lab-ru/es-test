#!/usr/bin/env bash
# Задание п2.2.5 «Частота ядра».
# Смена частоты clk_sys во время работы: что замедляется вместе с ядром, а что идёт от кварца.
# Использование: check-2-2-5.sh <путь к репозиторию> [папка проекта]
set -u

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
. "$LIB/report.sh"
. "$LIB/build.sh"
. "$LIB/code.sh"
. "$LIB/device.sh"
. "$LIB/exchange.sh"

TITLE="Задание 2.2.5 — Частота ядра"
REPO="${1:-.}"
PROJECT="${2:-221-command-time}"
SRC="$REPO/$PROJECT"

if [ ! -d "$SRC" ]; then
	fail "В репозитории нет папки проекта $PROJECT"
	finish "$TITLE"
	exit 1
fi
ok "Папка проекта $PROJECT найдена"

for f in main.c clock/clock.c clock/clock.h check-2-2-5.py device-2-2-5.log; do
	if [ -f "$SRC/$f" ]; then
		ok "Файл $f на месте"
	else
		fail "В проекте нет файла $f"
	fi
done

BODY="$SRC/clock/clock.c"
if [ -f "$BODY" ]; then
	RAW="$(normalize "$BODY")"
	CODE="$(code_only "$RAW")"

	match "$CODE" 'CLK_SYS_LOW_KHZ[^;]*62500' \
		"clock.c: пониженная частота задана константой CLK_SYS_LOW_KHZ = 62500" \
		"clock.c: нет константы CLK_SYS_LOW_KHZ со значением 62500"
	match "$CODE" 'set_sys_clock_khz[[:space:]]*\(' \
		"clock.c: частота меняется функцией set_sys_clock_khz" \
		"clock.c: нет вызова set_sys_clock_khz"
	match "$CODE" 'SYS_CLK_KHZ' \
		"clock.c: рабочая частота берётся из SYS_CLK_KHZ" \
		"clock.c: нет SYS_CLK_KHZ — рабочую частоту задаёт SDK, вписывать её числом не нужно"

	if grep -Eq 'if[[:space:]]*\([[:space:]]*!?[[:space:]]*set_sys_clock_khz|=[[:space:]]*set_sys_clock_khz' "$CODE"; then
		ok "clock.c: результат set_sys_clock_khz проверяется"
	else
		fail "clock.c: результат set_sys_clock_khz не проверяется"
		note "Функция возвращает false, если частоту нельзя получить. Прибор должен сообщить об этом."
	fi
	match "$CODE" 'LOG_ERR[[:space:]]*\(' \
		"clock.c: о неудаче прибор сообщает на уровне err" \
		"clock.c: нет сообщения LOG_ERR о неустановленной частоте"

	if grep -Eiq '(//|/\*).*(clk_peri|pll.?usb|48)' "$RAW"; then
		ok "clock.c: в комментарии объяснено, откуда clk_peri берёт такт"
	else
		warn "clock.c: не найден комментарий о clk_peri"
		note "Причину ищут в set_sys_clock_pll() в hardware_clocks/clocks.c и записывают над clk_sys_set()."
	fi
fi

HEADER="$SRC/clock/clock.h"
if [ -f "$HEADER" ]; then
	HEADER="$(normalize "$HEADER")"
	for fn in clk_sys_low clk_sys_default; do
		match "$HEADER" "$fn[[:space:]]*\\([[:space:]]*void[[:space:]]*\\)" \
			"clock.h: объявлена функция $fn" \
			"clock.h: нет объявления $fn"
	done
fi

MAIN="$SRC/main.c"
if [ -f "$MAIN" ]; then
	MAIN="$(code_only "$(normalize "$MAIN")")"
	for cmd in clk_sys_low clk_sys_default; do
		match "$MAIN" "\"$cmd\"" \
			"main.c: команда $cmd есть в таблице команд" \
			"main.c: в таблице команд нет $cmd"
	done
fi

build_project "$SRC"

if device_log "$SRC/device-2-2-5.log" "2.2.5"; then
	TABLE="$(exchange_table "$DEVICE_LOG")"

	# Частоты из N-го ответа clk_info: «имя настроенная измеренная».
	clocks() { exchange_replies "$TABLE" clk_info "$1" | awk -F '\t' '{ split($2, f, /[[:space:]]+/); if (f[1] ~ /^clk_/ && f[2] ~ /^[0-9]+$/) print f[1], f[2], f[3] }'; }
	freq() { echo "$1" | awk -v n="$2" -v c="$3" '$1 == n { print $c; exit }'; }
	calc() { exchange_replies "$TABLE" calc_pi "$1" | awk -F '\t' '$2 ~ /^time:/ { v = $2; sub(/^time:[[:space:]]*/, "", v); sub(/[^0-9].*$/, "", v); print v; exit }'; }
	avg() { exchange_replies "$TABLE" main_time_exec "$1" | awk -F '\t' '$2 ~ /avg/ { v = $2; sub(/.*avg[[:space:]]*/, "", v); sub(/[^0-9.].*$/, "", v); print v; exit }'; }

	HIGH="$(clocks 1)"; LOW="$(clocks 2)"; BACK="$(clocks 3)"
	if [ -z "$HIGH" ] || [ -z "$LOW" ] || [ -z "$BACK" ]; then
		fail "В логе меньше трёх таблиц clk_info: до смены частоты, после clk_sys_low и после clk_sys_default"
	else
		if echo "$TABLE" | awk -F '\t' '$2 == "clk_sys_low" && $5 ~ /62500/ && $5 !~ /not/' | grep -q .; then
			ok "Прибор сообщил об установке 62500 кГц"
		else
			fail "На clk_sys_low нет сообщения об установленной частоте 62500 кГц"
		fi

		SET="$(freq "$LOW" clk_sys 2)"; MEASURED="$(freq "$LOW" clk_sys 3)"
		if [ "${SET:-0}" -eq 62500 ] && [ "${MEASURED:-0}" -ge 61875 ] && [ "${MEASURED:-0}" -le 63125 ]; then
			ok "После clk_sys_low у clk_sys 62500 кГц, настроенных и измеренных"
		else
			fail "После clk_sys_low у clk_sys настроено ${SET:-нет} кГц, измерено ${MEASURED:-нет}"
		fi

		SAME=""
		for name in clk_ref clk_usb clk_adc; do
			[ "$(freq "$HIGH" $name 2)" = "$(freq "$LOW" $name 2)" ] || SAME="$SAME $name"
		done
		if [ -z "$SAME" ]; then
			ok "clk_ref, clk_usb и clk_adc после смены частоты ядра прежние"
		else
			fail "После смены частоты ядра изменились:$SAME"
			note "Эти сигналы идут от кварца и от PLL для USB. set_sys_clock_khz() их не трогает."
		fi

		SET="$(freq "$BACK" clk_sys 2)"
		if [ "${SET:-0}" -eq 125000 ]; then
			ok "После clk_sys_default у clk_sys снова 125000 кГц"
		else
			fail "После clk_sys_default у clk_sys ${SET:-нет} кГц вместо 125000"
		fi
	fi

	T1="$(calc 1)"; T2="$(calc 2)"; T3="$(calc 3)"
	if [ -z "$T1" ] || [ -z "$T2" ] || [ -z "$T3" ]; then
		fail "В логе меньше трёх замеров calc_pi"
	else
		if awk -v a="$T1" -v b="$T2" 'BEGIN { r = b / a; exit !(r >= 1.8 && r <= 2.2) }'; then
			ok "На 62,5 МГц расчёт идёт вдвое дольше: $T1 → $T2 мс"
		else
			fail "На 62,5 МГц расчёт занял $T2 мс против $T1 мс, это не вдвое"
		fi
		if awk -v a="$T1" -v c="$T3" 'BEGIN { r = c / a; exit !(r >= 0.9 && r <= 1.1) }'; then
			ok "После clk_sys_default время расчёта вернулось: $T3 мс"
		else
			fail "После clk_sys_default расчёт занял $T3 мс против прежних $T1 мс"
		fi
	fi

	A1="$(avg 1)"; A2="$(avg 2)"
	if [ -z "$A1" ] || [ -z "$A2" ]; then
		fail "В логе меньше двух ответов main_time_exec"
	elif awk -v a="$A1" -v b="$A2" 'BEGIN { exit !(b >= a * 1.3) }'; then
		ok "Средняя итерация выросла вместе с тактом ядра: $A1 → $A2 мкс"
	else
		fail "Средняя итерация на пониженной частоте не выросла: $A1 → $A2 мкс"
	fi

	# Два uptime на пониженной частоте: часы идут вровень со временем лога.
	U1="$(exchange_replies "$TABLE" uptime 1 | awk -F '\t' '$2 ~ /^uptime:/ { v = $2; sub(/^uptime:[[:space:]]*/, "", v); sub(/[^0-9].*$/, "", v); print $1, v; exit }')"
	U2="$(exchange_replies "$TABLE" uptime 2 | awk -F '\t' '$2 ~ /^uptime:/ { v = $2; sub(/^uptime:[[:space:]]*/, "", v); sub(/[^0-9].*$/, "", v); print $1, v; exit }')"
	if [ -z "$U1" ] || [ -z "$U2" ]; then
		fail "В логе меньше двух ответов uptime"
	else
		PACE="$(echo "$U1 $U2" | awk '{ log_ms = ($3 - $1) * 1000; dev_ms = $4 - $2; d = dev_ms - log_ms; if (d < 0) d = -d; print (d <= 50 + log_ms / 20) ? "ok" : dev_ms " " log_ms }')"
		if [ "$PACE" = "ok" ]; then
			ok "На пониженной частоте uptime идёт вровень со временем в логе"
		else
			fail "На пониженной частоте по uptime прошло ${PACE%% *} мс, по логу ${PACE##* } мс"
			note "Таймер считает тики от clk_ref. Если часы замедлились, время берётся не из time_us_64()."
		fi
	fi
fi

finish "$TITLE"
