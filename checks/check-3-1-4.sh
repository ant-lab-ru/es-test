#!/usr/bin/env bash
# Задание п3.1.4 «Считывание данных в Python».
# Скрипт get_telemetry.py запускает поток телеметрии прибора 311-adc, сохраняет записи
# в telemetry.csv и строит график в telemetry.png. Проверка читает CSV и PNG, а затем
# запускает скрипт в режиме --plot на копии CSV: график должен построиться без платы.
# Python с matplotlib и pyserial берётся из PYTHON (по умолчанию python3); если их нет,
# запуск скрипта пропускается с замечанием, остальные пункты отрабатывают.
# Использование: check-3-1-4.sh <путь к репозиторию> [папка проекта]
set -u

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
. "$LIB/report.sh"
. "$LIB/firmware.sh"

fw_start "Задание 3.1.4 — Считывание данных в Python" 311-adc "${1:-.}" "${2:-}"
PYTHON="${PYTHON:-python3}"
# предел времени на запуск скрипта, если в системе есть timeout (в macOS его нет)
LIMIT=""
command -v timeout > /dev/null && LIMIT="timeout 120"

for f in get_telemetry.py telemetry.csv telemetry.png; do
	if [ -f "$FW_SRC/$f" ]; then
		ok "Файл $f на месте"
	else
		fail "В проекте нет файла $f"
		note "Скрипт и оба файла, которые он создаёт, лежат в папке проекта."
	fi
done

SCRIPT="$FW_SRC/get_telemetry.py"
if [ -f "$SCRIPT" ]; then
	CODE="$(normalize "$SCRIPT")"
	match "$CODE" '^[[:space:]]*(import serial|from serial)' \
		"get_telemetry.py: порт открывается библиотекой pyserial" \
		"get_telemetry.py: нет import serial"
	match "$CODE" 'matplotlib' \
		"get_telemetry.py: график строит matplotlib" \
		"get_telemetry.py: не видно matplotlib"
	if grep -q 'tm_start' "$CODE" && grep -q 'tm_stop' "$CODE"; then
		ok "get_telemetry.py: скрипт запускает и останавливает телеметрию"
	else
		fail "get_telemetry.py: не видно команд tm_start и tm_stop"
		note "Поток запускает и останавливает сам скрипт, человеку не нужно набирать команды."
	fi
	match "$CODE" '"tm:|'"'"'tm:' \
		"get_telemetry.py: строки потока отбираются по началу tm:" \
		"get_telemetry.py: не видно отбора строк по началу tm:"
	if grep -q 'KeyboardInterrupt\|finally' "$CODE"; then
		ok "get_telemetry.py: при Ctrl+C поток останавливается"
	else
		warn "get_telemetry.py: не видно обработки Ctrl+C"
		note "Если прервать скрипт, прибор продолжит слать строки. try … finally отправит tm_stop при любом выходе."
	fi
fi

CSV="$FW_SRC/telemetry.csv"
if [ -f "$CSV" ]; then
	DATA="$(normalize "$CSV")"
	if [ "$(head -1 "$DATA")" = "time_s,voltage_v,temp_c" ]; then
		ok "telemetry.csv: заголовок time_s,voltage_v,temp_c"
	else
		fail "telemetry.csv: заголовок не time_s,voltage_v,temp_c: $(head -1 "$DATA")"
	fi
	ROWS="$(tail -n +2 "$DATA" | grep -c .)"
	if [ "$ROWS" -ge 50 ]; then
		ok "telemetry.csv: записей $ROWS"
	else
		fail "telemetry.csv: записей $ROWS, нужно не меньше 50"
		note "По умолчанию скрипт принимает поток 10 секунд с периодом 100 мс, это около 100 записей."
	fi
	BAD="$(tail -n +2 "$DATA" | grep -Ev '^[0-9]+(\.[0-9]+)?,[0-9]+\.[0-9]+,-?[0-9]+\.[0-9]+$' | head -1)"
	if [ -z "$BAD" ]; then
		ok "telemetry.csv: в каждой строке время, напряжение и температура числами"
	else
		fail "telemetry.csv: строка не из трёх чисел: $BAD"
	fi
	STATS="$(tail -n +2 "$DATA" | awk -F, '
		NR > 1 { d = $1 - last; if (d <= 0) back++; steps[++n] = d }
		{ last = $1; if ($2 < 0 || $2 > 3.4 || $3 < 10 || $3 > 50) out++ }
		END {
			# медиана шага и самое сильное отклонение от неё
			for (i = 1; i <= n; i++) for (j = i + 1; j <= n; j++) if (steps[j] < steps[i]) { t = steps[i]; steps[i] = steps[j]; steps[j] = t }
			med = n ? steps[int((n + 1) / 2)] : 0
			for (i = 1; i <= n; i++) { dev = steps[i] - med; if (dev < 0) dev = -dev; if (med > 0 && dev / med > worst) worst = dev / med }
			printf "%d %d %.6f %.2f", back + 0, out + 0, med, worst
		}')"
	set -- $STATS
	if [ "$1" -eq 0 ]; then
		ok "telemetry.csv: время растёт от строки к строке"
	else
		fail "telemetry.csv: время в $1 строках не растёт"
		note "Время берётся из записи прибора, а не из часов компьютера."
	fi
	if awk -v w="$4" 'BEGIN { exit !(w <= 0.2) }'; then
		ok "telemetry.csv: шаг по времени ровный, около $3 с"
	else
		fail "telemetry.csv: шаг по времени неровный, отклонение до $(awk -v w="$4" 'BEGIN { printf "%.0f", w * 100 }') % от $3 с"
		note "Ровный шаг даёт метка прибора. Время прихода строки на компьютер гуляет, им пользоваться нельзя."
	fi
	if [ "$2" -eq 0 ]; then
		ok "telemetry.csv: напряжение от 0 до 3,3 В, температура от 10 до 50 °C"
	else
		fail "telemetry.csv: значения вне пределов в $2 строках"
		note "Столбцы по порядку: время в секундах, напряжение в вольтах, температура в градусах."
	fi
fi

# is_png <файл> — начинается ли файл с подписи PNG
is_png() {
	[ "$(od -An -N8 -tx1 < "$1" | tr -d ' \n')" = "89504e470d0a1a0a" ]
}

PNG="$FW_SRC/telemetry.png"
if [ -f "$PNG" ]; then
	if is_png "$PNG"; then
		ok "telemetry.png: это изображение PNG"
	else
		fail "telemetry.png: файл не PNG"
		note "Файл сохраняет matplotlib: savefig(\"telemetry.png\")."
	fi
fi

if [ -f "$SCRIPT" ] && [ -f "$CSV" ]; then
	if ! "$PYTHON" -c 'import matplotlib, serial' 2>/dev/null; then
		note "Запуск скрипта не проверялся: нет $PYTHON с matplotlib и pyserial."
	else
		WORK="$(mktemp -d)"
		cp "$SCRIPT" "$CSV" "$WORK/"
		if (cd "$WORK" && MPLBACKEND=Agg $LIMIT "$PYTHON" get_telemetry.py --plot telemetry.csv > run.log 2>&1) &&
			[ -f "$WORK/telemetry.png" ] && is_png "$WORK/telemetry.png"; then
			ok "get_telemetry.py --plot telemetry.csv строит telemetry.png без платы"
		else
			fail "get_telemetry.py --plot telemetry.csv не построил telemetry.png"
			note "В режиме --plot скрипт не ищет плату, а читает CSV и сохраняет график. Вывод запуска:"
			tail -15 "$WORK/run.log"
		fi
		rm -rf "$WORK"
	fi
fi

finish "$TITLE"
