#!/usr/bin/env bash
# Задание п3.1.5 «Исследование RC-цепи».
# Прибор 311-adc заряжает RC-цепь с вывода GP22 командами charge_on и charge_off.
# Скрипт rc.py --r <кОм> --c <мкФ> ведёт опыт по 5τ на заряд и разряд,
# сохраняет rc.csv, rc.png и rc.log с номиналами и найденной τ.
# Проверка читает номиналы из rc.log и сама находит τ по rc.csv тем же способом,
# что скрипт: время от начала заряда до 63 % вершины и от начала разряда до 37 %.
# Обе τ должны попасть в допуск деталей, от 0,76 до 1,26 R·C.
# Использование: check-3-1-5.sh <путь к репозиторию> [папка проекта]
set -u

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
. "$LIB/report.sh"
. "$LIB/build.sh"
. "$LIB/code.sh"
. "$LIB/firmware.sh"

fw_start "Задание 3.1.5 — Исследование RC-цепи" 311-adc "${1:-.}" "${2:-}"

for f in platform/platform.c rc.py rc.csv rc.png rc.log; do
	if [ -f "$FW_SRC/$f" ]; then
		ok "Файл $f на месте"
	else
		fail "В проекте нет файла $f"
		note "rc.csv, rc.png и rc.log создаёт rc.py --r <кОм> --c <мкФ>."
	fi
done

PLATFORM_C="$FW_SRC/platform/platform.c"
if [ -f "$PLATFORM_C" ]; then
	CODE="$(fw_code "$PLATFORM_C")"
	if grep -Eq '22' "$CODE" && grep -Eq 'gpio_set_dir[[:space:]]*\([^)]*GPIO_OUT|gpio_set_dir[[:space:]]*\([^)]*true' "$CODE"; then
		ok "platform.c: вывод GP22 настроен на выход"
	else
		fail "platform.c: не видно вывода GP22 на выход"
		note "Цепь заряжается с GP22 через резистор. Вывод настраивается в platform_init(), как вывод светодиода."
	fi
fi

LOGIC="$(mktemp)"
find "$FW_SRC/logic" -type f \( -name '*.c' -o -name '*.h' \) 2>/dev/null | sort |
	while read -r f; do cat "$(fw_code "$f")"; done > "$LOGIC"
if grep -q '"charge_on"' "$LOGIC" && grep -q '"charge_off"' "$LOGIC"; then
	ok "api-callbacks.c: команды charge_on и charge_off есть в таблице"
else
	fail "В таблице команд нет charge_on или charge_off"
fi
if grep -Eq '#include[[:space:]]*[<"](pico|hardware)/|gpio_' "$LOGIC"; then
	fail "logic: логика управляет выводом в обход platform"
	note "Вывод заряда, как светодиод, — дело platform. Команда вызывает функцию platform."
fi

SCRIPT="$FW_SRC/rc.py"
if [ -f "$SCRIPT" ]; then
	CODE="$(normalize "$SCRIPT")"
	if grep -q 'charge_on' "$CODE" && grep -q 'charge_off' "$CODE"; then
		ok "rc.py: опыт ведёт скрипт, команды заряда отправляет сам"
	else
		fail "rc.py: не видно команд charge_on и charge_off"
		note "Во время записи плату и цепь руками не трогают: заряд включает и выключает скрипт."
	fi
fi

build_project "$FW_SRC"

# value <ключ> — значение из rc.log, строки вида «ключ = значение»
LOG="$FW_SRC/rc.log"
value() {
	[ -f "$LOG" ] && grep -E "^$1[[:space:]]*=" "$(normalize "$LOG")" | head -1 | sed 's/.*=[[:space:]]*//'
}

R_KOHM="$(value R_kohm)"
C_UF="$(value C_uf)"
TAU=""
if [ -n "$R_KOHM" ] && [ -n "$C_UF" ]; then
	TAU="$(awk -v r="$R_KOHM" -v c="$C_UF" 'BEGIN { printf "%.3f", r * c / 1000 }')"
	ok "rc.log: R = $R_KOHM кОм, C = $C_UF мкФ, R·C = $TAU с"
	if awk -v r="$R_KOHM" 'BEGIN { exit !(r >= 1 && r <= 100) }'; then
		ok "Резистор в пределах от 1 до 100 кОм"
	else
		fail "Резистор $R_KOHM кОм вне пределов от 1 до 100 кОм"
		note "Меньше 1 кОм вывод GP22 даёт слишком большой ток, больше 100 кОм сказывается утечка конденсатора."
	fi
elif [ -f "$LOG" ]; then
	fail "rc.log: нет строк R_kohm и C_uf"
	note "rc.log пишет скрипт, запущенный с номиналами: rc.py --r 10 --c 100."
fi

# Постоянная времени по rc.csv, как в скрипте. Вершина — наибольшее напряжение записи.
# Заряд: от первой записи выше 2 % вершины до первой записи выше 63,2 %.
# Разряд: от вершины, от первой записи ниже 98 % до первой записи ниже 36,8 %.
CSV="$FW_SRC/rc.csv"
if [ -f "$CSV" ]; then
	DATA="$(normalize "$CSV")"
	if [ "$(head -1 "$DATA")" = "time_s,voltage_v,temp_c" ]; then
		ok "rc.csv: заголовок time_s,voltage_v,temp_c"
	else
		fail "rc.csv: заголовок не time_s,voltage_v,temp_c"
	fi
	FOUND="$(tail -n +2 "$DATA" | awk -F, '
		{ t[NR] = $1; v[NR] = $2; if (NR == 1 || $2 > top) { top = $2; peak = NR } }
		function at(i) { return i == "" ? "-" : t[i] }
		function cross(from, level, rising,   i) {
			if (from == "") return ""
			for (i = from; i <= NR; i++)
				if (rising ? v[i] >= level : v[i] <= level) return i
			return ""
		}
		END {
			cs = cross(1, 0.02 * top, 1); ce = cross(cs, 0.632 * top, 1)
			if (ce == "" || ce > peak) { cs = ""; ce = "" }
			ds = cross(peak, 0.98 * top, 0); de = cross(ds, 0.368 * top, 0)
			printf "%d %s %s %s %s %s %s", NR, t[2] - t[1], t[NR], at(cs), at(ce), at(ds), at(de)
			if (cs == "") printf " none"; else printf " %.3f", t[ce] - t[cs]
			if (de == "") printf " none"; else printf " %.3f", t[de] - t[ds]
		}')"
	set -- $FOUND
	ROWS="$1" STEP="$2" LAST="$3" CS="$4" DS="$6" TAU_CHARGE="$8" TAU_DISCHARGE="$9"
	ok "rc.csv: записей $ROWS, шаг $STEP с"

	if [ -n "$TAU" ]; then
		if awk -v tau="$TAU" -v dt="$STEP" 'BEGIN { exit !(dt > 0 && tau / dt >= 20) }'; then
			ok "На τ приходится не меньше 20 отсчётов"
		else
			fail "На τ = $TAU с приходится меньше 20 отсчётов при шаге $STEP с"
			note "Возьмите детали с τ от 0,2 с, таблица пар — в задании."
		fi
		if [ "$TAU_CHARGE" != "none" ] && [ "$TAU_DISCHARGE" != "none" ] &&
			awk -v tau="$TAU" -v cs="$CS" -v ds="$DS" -v last="$LAST" \
				'BEGIN { exit !(ds - cs >= 4 * tau && last - ds >= 4 * tau) }'; then
			ok "Заряд и разряд длятся не меньше 4τ каждый"
		else
			fail "Заряд или разряд в записи короче 4τ"
			note "Опыт ведёт скрипт по номиналам. Проверьте, что в --r и --c те же детали, что в цепи."
		fi
	fi

	if [ "$TAU_CHARGE" = "none" ] || [ "$TAU_DISCHARGE" = "none" ]; then
		fail "rc.csv: напряжение не проходит уровни 63 % на заряде или 37 % на разряде"
		note "Проверьте цепь: GP22 → резистор → GP26, конденсатор между GP26 и землёй, плюсом к GP26."
	elif [ -n "$TAU" ]; then
		RANGE="$(awk -v tau="$TAU" 'BEGIN { printf "%.3f %.3f", 0.76 * tau, 1.26 * tau }')"
		set -- $RANGE
		LOW="$1" HIGH="$2"
		if awk -v a="$TAU_CHARGE" -v b="$TAU_DISCHARGE" -v lo="$LOW" -v hi="$HIGH" \
			'BEGIN { exit !(a >= lo && a <= hi && b >= lo && b <= hi) }'; then
			ok "τ заряда $TAU_CHARGE с и разряда $TAU_DISCHARGE с в диапазоне ${LOW}–${HIGH} с"
		else
			fail "τ заряда $TAU_CHARGE с или разряда $TAU_DISCHARGE с вне диапазона ${LOW}–${HIGH} с"
			note "Сверьте номиналы по маркировке и полярность конденсатора."
		fi
		LOG_CHARGE="$(value tau_charge_s)"
		LOG_DISCHARGE="$(value tau_discharge_s)"
		if awk -v a="$TAU_CHARGE" -v b="$TAU_DISCHARGE" -v la="$LOG_CHARGE" -v lb="$LOG_DISCHARGE" \
			'BEGIN { da = a - la; db = b - lb; exit !(la != "" && lb != "" && da * da < 1e-4 && db * db < 1e-4) }'; then
			ok "rc.log: τ совпадает с записью rc.csv"
		else
			fail "rc.log: τ ($LOG_CHARGE и $LOG_DISCHARGE с) не совпадает с записью rc.csv"
			note "rc.log и rc.csv должны быть из одного опыта. Пересчитать: rc.py --r … --c … --plot rc.csv."
		fi
	fi
fi

PNG="$FW_SRC/rc.png"
if [ -f "$PNG" ]; then
	if [ "$(od -An -N8 -tx1 < "$PNG" | tr -d ' \n')" = "89504e470d0a1a0a" ]; then
		ok "rc.png: это изображение PNG"
	else
		fail "rc.png: файл не PNG"
	fi
fi

finish "$TITLE"
