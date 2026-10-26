#!/usr/bin/env bash
# Задание п3.1.5 «Исследование RC-цепи».
# Прибор 311-adc заряжает RC-цепь с вывода GP22 командами charge_on и charge_off,
# скрипт get_telemetry.py --rc снимает 5 с заряда и 5 с разряда в rc.csv и rc.png.
# Проверка сама оценивает постоянную времени по rc.csv на заряде и на разряде
# и сравнивает её с R·C и с оценкой обучающегося из README.md проекта, допуск 25 %.
# Использование: check-3-1-5.sh <путь к репозиторию> [папка проекта]
set -u

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
. "$LIB/report.sh"
. "$LIB/build.sh"
. "$LIB/code.sh"
. "$LIB/firmware.sh"

fw_start "Задание 3.1.5 — Исследование RC-цепи" 311-adc "${1:-.}" "${2:-}"

for f in platform/platform.c get_telemetry.py rc.csv rc.png README.md; do
	if [ -f "$FW_SRC/$f" ]; then
		ok "Файл $f на месте"
	else
		fail "В проекте нет файла $f"
		note "rc.csv и rc.png создаёт get_telemetry.py --rc, номиналы и τ записываются в README.md проекта."
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

SCRIPT="$FW_SRC/get_telemetry.py"
if [ -f "$SCRIPT" ]; then
	CODE="$(normalize "$SCRIPT")"
	if grep -q 'charge_on' "$CODE" && grep -q 'charge_off' "$CODE"; then
		ok "get_telemetry.py: опыт ведёт скрипт, команды заряда отправляет сам"
	else
		fail "get_telemetry.py: не видно команд charge_on и charge_off"
		note "Во время записи плату и цепь руками не трогают: заряд включает и выключает скрипт."
	fi
fi

build_project "$FW_SRC"

# Постоянная времени по rc.csv: участки до и после максимума, точки от 10 до 90 % размаха,
# наклон прямой ln(1 − U/Umax) или ln(U/Umax) от времени методом наименьших квадратов.
CSV="$FW_SRC/rc.csv"
TAU_CHARGE=""
TAU_DISCHARGE=""
if [ -f "$CSV" ]; then
	DATA="$(normalize "$CSV")"
	if [ "$(head -1 "$DATA")" = "time_s,voltage_v,temp_c" ]; then
		ok "rc.csv: заголовок time_s,voltage_v,temp_c"
	else
		fail "rc.csv: заголовок не time_s,voltage_v,temp_c"
	fi
	FIT="$(tail -n +2 "$DATA" | awk -F, '
		{ t[NR] = $1; v[NR] = $2; if ($2 > top) { top = $2; peak = NR } }
		function fit(a, b, kind,   i, n, st, sy, stt, sty, y, slope) {
			for (i = a; i <= b; i++) {
				if (v[i] <= 0.1 * top || v[i] >= 0.9 * top) continue
				y = kind == "c" ? log(1 - v[i] / top) : log(v[i] / top)
				n++; st += t[i]; sy += y; stt += t[i] * t[i]; sty += t[i] * y
			}
			if (n < 5) return "none"
			slope = (n * sty - st * sy) / (n * stt - st * st)
			return slope < 0 ? sprintf("%.3f", -1 / slope) : "none"
		}
		END { printf "%s %s %.3f %d", fit(1, peak - 1, "c"), fit(peak + 1, NR, "d"), top, NR }')"
	set -- $FIT
	ROWS="$4"
	if [ "$ROWS" -ge 500 ]; then
		ok "rc.csv: записей $ROWS"
	else
		fail "rc.csv: записей $ROWS, мало для опыта"
		note "Опыт длится 10 с с периодом 10 мс, это около тысячи записей."
	fi
	if [ "$1" != "none" ] && [ "$2" != "none" ]; then
		TAU_CHARGE="$1"
		TAU_DISCHARGE="$2"
		ok "rc.csv: экспонента видна, τ на заряде $1 с, на разряде $2 с, напряжение до $3 В"
	else
		fail "rc.csv: на заряде или на разряде экспоненты не видно"
		note "Проверьте цепь: GP22 → резистор → GP26, конденсатор между GP26 и землёй, плюсом к GP26."
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

# number <строка README> — число из строки, запятая как точка
number() {
	echo "$1" | sed 's/,/./' | grep -Eo '[0-9]+(\.[0-9]+)?' | head -1
}

README="$FW_SRC/README.md"
if [ -f "$README" ]; then
	TEXT="$(normalize "$README")"
	R_LINE="$(grep -E '^R[[:space:]]*=' "$TEXT" | head -1)"
	C_LINE="$(grep -E '^C[[:space:]]*=' "$TEXT" | head -1)"
	T_LINE="$(grep -E '^τ[[:space:]]*=' "$TEXT" | head -1)"
	R_OHM=""
	C_F=""
	case "$R_LINE" in
		*кОм*) R_OHM="$(awk -v x="$(number "$R_LINE")" 'BEGIN { print x * 1000 }')" ;;
		*МОм*) R_OHM="$(awk -v x="$(number "$R_LINE")" 'BEGIN { print x * 1000000 }')" ;;
		*Ом*) R_OHM="$(number "$R_LINE")" ;;
	esac
	case "$C_LINE" in
		*мкФ*) C_F="$(awk -v x="$(number "$C_LINE")" 'BEGIN { print x / 1000000 }')" ;;
		*нФ*) C_F="$(awk -v x="$(number "$C_LINE")" 'BEGIN { print x / 1000000000 }')" ;;
	esac
	if [ -n "$R_OHM" ] && [ -n "$C_F" ]; then
		RC="$(awk -v r="$R_OHM" -v c="$C_F" 'BEGIN { printf "%.3f", r * c }')"
		ok "README.md: R = $R_OHM Ом, C = $C_F Ф, R·C = $RC с"
	else
		fail "README.md: не найдены строки R = … и C = … с единицами"
		note "Строки вида R = 10 кОм и C = 100 мкФ, каждая с начала строки."
	fi
	STUDENT="$(number "$T_LINE")"
	if [ -n "$STUDENT" ]; then
		ok "README.md: оценка по графику τ = $STUDENT с"
	else
		fail "README.md: нет строки τ = … с вашей оценкой по графику"
		note "Строка вида τ = 1.02 с, с начала строки."
	fi

	# near <a> <b> — отличаются ли числа не больше чем на 25 % от второго
	near() {
		awk -v a="$1" -v b="$2" 'BEGIN { d = a - b; if (d < 0) d = -d; exit !(b > 0 && d / b <= 0.25) }'
	}
	if [ -n "${RC:-}" ] && [ -n "$TAU_CHARGE" ]; then
		if near "$TAU_CHARGE" "$RC" && near "$TAU_DISCHARGE" "$RC"; then
			ok "τ по записи ($TAU_CHARGE и $TAU_DISCHARGE с) сходится с R·C = $RC с в пределах 25 %"
		else
			fail "τ по записи ($TAU_CHARGE и $TAU_DISCHARGE с) расходится с R·C = $RC с больше чем на 25 %"
			note "Сверьте номиналы по маркировке. У электролитического конденсатора допуск до 20 %."
		fi
	fi
	if [ -n "$STUDENT" ] && [ -n "$TAU_CHARGE" ]; then
		MEAN="$(awk -v a="$TAU_CHARGE" -v b="$TAU_DISCHARGE" 'BEGIN { printf "%.3f", (a + b) / 2 }')"
		if near "$STUDENT" "$MEAN"; then
			ok "Ваша оценка τ = $STUDENT с сходится с оценкой по записи $MEAN с"
		else
			fail "Ваша оценка τ = $STUDENT с расходится с оценкой по записи $MEAN с"
			note "По графику τ — время, за которое напряжение проходит 63 % пути до конечного значения."
		fi
	fi
fi

finish "$TITLE"
