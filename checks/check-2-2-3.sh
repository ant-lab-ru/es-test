#!/usr/bin/env bash
# Задание п2.2.3 «Цена вычислений».
# Расчёт π рядом Лейбница, замер разностью time_us_64(), прибор замирает на время расчёта.
# Использование: check-2-2-3.sh <путь к репозиторию> [папка проекта]
set -u

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
. "$LIB/report.sh"
. "$LIB/build.sh"
. "$LIB/code.sh"
. "$LIB/device.sh"
. "$LIB/exchange.sh"

TITLE="Задание 2.2.3 — Цена вычислений"
REPO="${1:-.}"
PROJECT="${2:-221-command-time}"
SRC="$REPO/$PROJECT"

if [ ! -d "$SRC" ]; then
	fail "В репозитории нет папки проекта $PROJECT"
	finish "$TITLE"
	exit 1
fi
ok "Папка проекта $PROJECT найдена"

for f in main.c check-2-2-3.py device-2-2-3.log; do
	if [ -f "$SRC/$f" ]; then
		ok "Файл $f на месте"
	else
		fail "В проекте нет файла $f"
	fi
done

MAIN="$SRC/main.c"
if [ -f "$MAIN" ]; then
	MAIN="$(normalize "$MAIN")"
	CODE="$(code_only "$MAIN")"

	LINE="$(grep -nE 'CALC_PI_TERMS[[:space:]]*=?[[:space:]]*1000000' "$CODE" | head -1 | cut -d: -f1)"
	if [ -n "$LINE" ]; then
		ok "main.c: число членов ряда задано константой CALC_PI_TERMS = 1000000"
		# Прикидка — комментарий в той же строке или в трёх строках над константой.
		FROM=$((LINE > 3 ? LINE - 3 : 1))
		if sed -n "${FROM},${LINE}p" "$MAIN" | grep -Eq '//|/\*'; then
			ok "main.c: рядом с CALC_PI_TERMS записана прикидка времени расчёта"
		else
			fail "main.c: рядом с CALC_PI_TERMS нет комментария с прикидкой"
			note "Прикидку делают до запуска по таблице цены операций из т2.2.3 и записывают над константой."
		fi
	else
		fail "main.c: нет константы CALC_PI_TERMS со значением 1000000"
	fi

	BODY="$(mktemp)"
	function_body "$CODE" '(^|[^A-Za-z_])calc_pi' > "$BODY"
	if grep -Eq 'double[[:space:]]+calc_pi[[:space:]]*\(' "$CODE"; then
		ok "main.c: функция calc_pi возвращает double"
	else
		fail "main.c: нет функции double calc_pi(...)"
	fi
	if grep -Eq 'double' "$BODY" && grep -Eq '/' "$BODY"; then
		ok "main.c: ряд суммируется в double с делением на 2k + 1"
	else
		fail "main.c: в calc_pi не видно суммы ряда в double"
	fi
	rm -f "$BODY"

	match "$CODE" 'volatile[[:space:]]+double|double[[:space:]]+volatile' \
		"main.c: результат расчёта пишется в переменную с volatile" \
		"main.c: нет переменной volatile double для результата"

	READS="$(grep -oE 'time_us_64[[:space:]]*\(' "$CODE" | wc -l | tr -d ' ')"
	if [ "$READS" -ge 3 ]; then
		ok "main.c: расчёт замеряется двумя чтениями time_us_64"
	else
		fail "main.c: для замера нужны два чтения time_us_64 рядом с расчётом"
		note "Одно чтение уже есть в мигании. Замер — это ещё два: перед расчётом и сразу после."
	fi

	match "$CODE" '"calc_pi"' \
		"main.c: команда calc_pi есть в таблице команд" \
		"main.c: в таблице команд нет calc_pi"
fi

build_project "$SRC"

if device_log "$SRC/device-2-2-3.log" "2.2.3"; then
	TABLE="$(exchange_table "$DEVICE_LOG")"
	# Результат расчёта приходит, когда uptime уже отправлена, и в таблице числится за ней.
	# Поэтому строки pi: и time: ищутся по всему обмену: время ответа и текст.
	CALC="$(echo "$TABLE" | awk -F '\t' '{ print $4 "\t" $5 }')"

	PI="$(echo "$CALC" | awk -F '\t' '$2 ~ /^pi:/ { v = $2; sub(/^pi:[[:space:]]*/, "", v); print v; exit }')"
	PI_AT="$(echo "$CALC" | awk -F '\t' '$2 ~ /^pi:/ { print $1; exit }')"
	if [ -z "$PI" ]; then
		fail "В ответе на calc_pi нет строки pi: со значением"
		note "Ответ — две строки: pi: 3.14159165 и time: 4698 ms."
	elif awk -v p="$PI" 'BEGIN { d = p - 3.14159265; if (d < 0) d = -d; exit !(d <= 0.000002) }'; then
		ok "Прибор посчитал π = $PI: ошибка не больше двух миллионных"
	else
		fail "Прибор посчитал π = $PI, это дальше двух миллионных от 3,14159265"
		note "Миллион членов ряда Лейбница даёт 3.14159165. Проверьте знак члена и множитель 4."
	fi

	SPENT="$(echo "$CALC" | awk -F '\t' '$2 ~ /^time:/ { v = $2; sub(/^time:[[:space:]]*/, "", v); sub(/[[:space:]]*ms.*$/, "", v); print v; exit }')"
	if [ -z "$SPENT" ]; then
		fail "В ответе на calc_pi нет строки time: с миллисекундами"
	elif [ "$SPENT" -ge 1000 ] && [ "$SPENT" -le 20000 ]; then
		ok "Время расчёта $SPENT мс"
	elif [ "$SPENT" -lt 1000 ]; then
		fail "Время расчёта $SPENT мс: расчёт не попал между двумя чтениями часов"
		note "Без volatile компилятор вправе перенести расчёт за второе чтение часов."
	else
		fail "Время расчёта $SPENT мс, это больше 20 с"
	fi

	UP_SENT="$(exchange_sent_at "$DEVICE_LOG" uptime 1)"
	UP_AT="$(echo "$CALC" | awk -F '\t' '$2 ~ /^uptime:/ { print $1; exit }')"
	if [ -z "$UP_SENT" ] || [ -z "$UP_AT" ]; then
		fail "В логе нет вызова uptime с ответом"
	elif [ -n "$PI_AT" ] && awk -v s="$UP_SENT" -v p="$PI_AT" -v u="$UP_AT" 'BEGIN { exit !(s < p && u >= p) }'; then
		ok "uptime отправлена во время расчёта, а ответ пришёл после его результата"
	else
		fail "Ответ на uptime пришёл не после результата calc_pi"
		note "Пока ядро считает, суперцикл не забирает команды из порта. Ответ на uptime обязан ждать конца расчёта."
	fi
fi

finish "$TITLE"
