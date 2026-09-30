#!/usr/bin/env bash
# Задание п2.2.4 «Профилирование».
# Модуль profiling: длительность итерации, максимум и экспоненциальное среднее в целых числах.
# Использование: check-2-2-4.sh <путь к репозиторию> [папка проекта]
set -u

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
. "$LIB/report.sh"
. "$LIB/build.sh"
. "$LIB/cmake.sh"
. "$LIB/code.sh"
. "$LIB/device.sh"
. "$LIB/exchange.sh"

TITLE="Задание 2.2.4 — Профилирование"
REPO="${1:-.}"
PROJECT="${2:-221-command-time}"
SRC="$REPO/$PROJECT"

if [ ! -d "$SRC" ]; then
	fail "В репозитории нет папки проекта $PROJECT"
	finish "$TITLE"
	exit 1
fi
ok "Папка проекта $PROJECT найдена"

for f in main.c profiling/profiling.c profiling/profiling.h check-2-2-4.py device-2-2-4.log; do
	if [ -f "$SRC/$f" ]; then
		ok "Файл $f на месте"
	else
		fail "В проекте нет файла $f"
	fi
done

CMAKE="$SRC/CMakeLists.txt"
if [ -f "$CMAKE" ]; then
	FLAT="$(cmake_flatten "$CMAKE")"
	match "$FLAT" 'add_executable[[:space:]]*\([^)]*profiling/profiling\.c' \
		"CMakeLists.txt: profiling/profiling.c добавлен в сборку" \
		"CMakeLists.txt: profiling/profiling.c не добавлен в add_executable"
	match "$FLAT" 'target_include_directories[[:space:]]*\([^)]*/profiling([[:space:]]|\))' \
		"CMakeLists.txt: папка profiling есть в путях заголовков" \
		"CMakeLists.txt: папки profiling нет в target_include_directories"
fi

HEADER="$SRC/profiling/profiling.h"
if [ -f "$HEADER" ]; then
	HEADER="$(code_only "$(normalize "$HEADER")")"
	MISSING=""
	for fn in profiling_init profiling_iteration profiling_avg_us profiling_max_us profiling_reset_max; do
		grep -Eq "$fn[[:space:]]*\([[:space:]]*void[[:space:]]*\)" "$HEADER" || MISSING="$MISSING $fn"
	done
	if [ -z "$MISSING" ]; then
		ok "profiling.h: объявлены пять функций модуля"
	else
		fail "profiling.h: нет объявлений:$MISSING"
	fi
fi

BODY="$SRC/profiling/profiling.c"
if [ -f "$BODY" ]; then
	RAW="$(normalize "$BODY")"
	BODY="$(code_only "$RAW")"

	match "$BODY" 'time_us_32[[:space:]]*\(' \
		"profiling.c: итерация меряется показаниями time_us_32" \
		"profiling.c: нет вызова time_us_32"

	ITERATION="$(mktemp)"
	function_body "$BODY" 'profiling_iteration' > "$ITERATION"
	if [ ! -s "$ITERATION" ]; then
		fail "profiling.c: нет функции profiling_iteration"
	else
		if grep -Eq '>>' "$ITERATION"; then
			ok "profiling.c: среднее обновляется сдвигом"
		else
			fail "profiling.c: в profiling_iteration нет сдвига вправо"
			note "Если N — степень двойки, деление суммы на N превращается в сдвиг: S >> K."
		fi
		if grep -Eq 'float|double|/' "$ITERATION"; then
			fail "profiling.c: в profiling_iteration есть float, double или деление"
			note "Эта функция работает на каждой итерации. Деление и плавающая точка стоят сотни тактов и удвоят то, что меряют."
		else
			ok "profiling.c: в profiling_iteration нет ни float, ни деления"
		fi
		if grep -Eq '>[[:space:]]*[A-Za-z_]*max' "$ITERATION" || grep -Eq 'max[A-Za-z_]*[[:space:]]*<' "$ITERATION"; then
			ok "profiling.c: максимум обновляется на каждой итерации"
		else
			fail "profiling.c: в profiling_iteration не видно обновления максимума"
		fi
	fi
	rm -f "$ITERATION"

	if grep -Eq '(//|/\*).*[0-9]' "$RAW"; then
		ok "profiling.c: в комментарии записан расчёт памяти среднего"
	else
		fail "profiling.c: нет комментария с расчётом N"
		note "Запишите, сколько итераций проходит за секунду и какая степень двойки выбрана."
	fi

	SHIFT="$(grep -Eo 'AVG_SHIFT[[:space:]]+[0-9]+' "$BODY" | head -1 | awk '{print $2}')"
	if [ -z "$SHIFT" ]; then
		warn "profiling.c: не удалось найти показатель степени N, пункт о памяти среднего пропущен"
	elif [ "$SHIFT" -ge 17 ] && [ "$SHIFT" -le 20 ]; then
		ok "profiling.c: N = 2^$SHIFT — среднее помнит около секунды работы"
	else
		fail "profiling.c: N = 2^$SHIFT — память среднего далека от секунды"
		note "Итерация длится около 2 мкс, за секунду их около полумиллиона. Это 2^19."
	fi
fi

MAIN="$SRC/main.c"
if [ -f "$MAIN" ]; then
	CODE="$(code_only "$(normalize "$MAIN")")"
	match "$CODE" 'profiling_init[[:space:]]*\(' \
		"main.c: замер запускается вызовом profiling_init" \
		"main.c: нет вызова profiling_init перед суперциклом"
	match "$CODE" 'profiling_iteration[[:space:]]*\(' \
		"main.c: каждая итерация учитывается вызовом profiling_iteration" \
		"main.c: нет вызова profiling_iteration в суперцикле"
	if grep -Eq 'time_us_32|>>[[:space:]]*[0-9A-Z_]' "$CODE"; then
		fail "main.c: вычисления профилирования попали в main.c"
		note "Чтение часов и сдвиги среднего — внутреннее дело модуля profiling. main.c только вызывает его функции."
	else
		ok "main.c: вычислений профилирования нет, только вызовы модуля"
	fi
	for cmd in main_time_exec main_time_reset; do
		match "$CODE" "\"$cmd\"" \
			"main.c: команда $cmd есть в таблице команд" \
			"main.c: в таблице команд нет $cmd"
	done
fi

build_project "$SRC"

if device_log "$SRC/device-2-2-4.log" "2.2.4"; then
	TABLE="$(exchange_table "$DEVICE_LOG")"

	# N-й ответ main_time_exec: среднее и максимум в микросекундах.
	exec_reply() {
		exchange_replies "$TABLE" main_time_exec "$1" | awk -F '\t' '
			$2 ~ /avg/ && $2 ~ /max/ {
				a = $2; sub(/.*avg[[:space:]]*/, "", a); sub(/[^0-9.].*$/, "", a)
				m = $2; sub(/.*max[[:space:]]*/, "", m); sub(/[^0-9].*$/, "", m)
				print a, m; exit
			}'
	}

	FIRST="$(exec_reply 1)"
	AFTER="$(exec_reply 2)"
	LATER="$(exec_reply 3)"
	RESET="$(exec_reply 4)"

	if [ -z "$FIRST" ] || [ -z "$AFTER" ] || [ -z "$LATER" ] || [ -z "$RESET" ]; then
		fail "В логе меньше четырёх ответов main_time_exec со средним и максимумом"
		note "Ответ — строка вида iteration avg 2.46 us, max 297 us."
	else
		AVG1="${FIRST% *}"; AVG2="${AFTER% *}"; AVG3="${LATER% *}"
		MAX2="${AFTER#* }"; MAX4="${RESET#* }"

		if awk -v a="$AVG1" 'BEGIN { exit !(a > 0 && a < 20) }'; then
			ok "Средняя итерация без нагрузки $AVG1 мкс"
		else
			fail "Средняя итерация без нагрузки $AVG1 мкс, а должна быть единицы микросекунд"
			note "Если среднее ноль, profiling_iteration не вызывается. Если десятки — в суперцикле осталось ожидание."
		fi

		SPENT="$(exchange_replies "$TABLE" calc_pi 1 | awk -F '\t' '$2 ~ /^time:/ { v = $2; sub(/^time:[[:space:]]*/, "", v); sub(/[^0-9].*$/, "", v); print v; exit }')"
		if [ -z "$SPENT" ]; then
			fail "В логе нет времени расчёта calc_pi"
		elif [ "$MAX2" -ge "$((SPENT * 1000 * 95 / 100))" ]; then
			ok "После calc_pi максимум $MAX2 мкс: это итерация с расчётом на $SPENT мс"
		else
			fail "После calc_pi максимум $MAX2 мкс меньше времени расчёта $SPENT мс"
			note "Итерация с расчётом длится не меньше самого расчёта. Проверьте, что максимум обновляется в profiling_iteration."
		fi

		if awk -v a="$AVG1" -v b="$AVG2" 'BEGIN { exit !(b > a) }'; then
			ok "После calc_pi среднее подскочило: $AVG1 → $AVG2 мкс"
		else
			fail "После calc_pi среднее не выросло: $AVG1 → $AVG2 мкс"
			note "Итерация в секунды сдвигает среднее на её N-ю часть. Если N слишком велико, сдвиг не виден."
		fi

		if awk -v a="$AVG1" -v b="$AVG2" -v c="$AVG3" 'BEGIN { exit !(c < b && c <= a * 1.5 + 0.5) }'; then
			ok "Через несколько секунд среднее вернулось: $AVG3 мкс"
		else
			fail "Через несколько секунд среднее $AVG3 мкс не вернулось к $AVG1"
			note "Среднее помнит около N итераций. Если оно держится долго, N выбрано слишком большим."
		fi

		if [ "$MAX4" -lt 2000 ]; then
			ok "После main_time_reset максимум снова мал: $MAX4 мкс"
		else
			fail "После main_time_reset максимум $MAX4 мкс"
			note "Сброс обнуляет максимум, и дальше в него попадают только обычные итерации."
		fi
	fi

	if echo "$TABLE" | awk -F '\t' '$2 == "main_time_reset"' | grep -q .; then
		ok "Плата ответила на main_time_reset"
	else
		fail "В логе нет ответа на main_time_reset"
	fi
fi

finish "$TITLE"
