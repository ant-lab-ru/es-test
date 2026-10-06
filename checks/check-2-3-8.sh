#!/usr/bin/env bash
# Задание п2.3.8 «Приёмка прибора».
# Функциональная проверка прибора 231-firmware-template по техническому заданию занятия 2.3.
# Каждый пункт называет требование ТЗ, которое он подтверждает: Ф — функции прибора,
# Н — время и ресурсы, У и П — устройство кода (часть 2 ТЗ), А и Б — приложения.
# Читает лог прогона на плате, собирает проект три раза: как есть, с заголовком SDK
# в логике (сборка должна остановиться) и с выключенным профилированием.
# Использование: check-2-3-8.sh <путь к репозиторию> [папка проекта]
set -u

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
. "$LIB/report.sh"
. "$LIB/build.sh"
. "$LIB/code.sh"
. "$LIB/cmake.sh"
. "$LIB/device.sh"
. "$LIB/exchange.sh"
. "$LIB/firmware.sh"

fw_start "Задание 2.3.8 — Приёмка прибора" 231-firmware-template "${1:-.}" "${2:-}"

for f in check-2-3-8.py device-2-3-8.log; do
	if [ -f "$FW_SRC/$f" ]; then
		ok "Файл $f на месте"
	else
		fail "В проекте нет файла $f"
	fi
done

# ---------- обмен с платой ----------

if device_log "$FW_SRC/device-2-3-8.log" "2.3.8"; then
	TABLE="$(exchange_table "$DEVICE_LOG")"

	# reply <команда> <номер вызова> — текст ответов на N-й кадр с этой командой;
	# первая строка — эхо кадра, её пропускаем
	reply() {
		exchange_replies "$TABLE" "$1" "$2" | cut -f2 | tail -n +2
	}
	# delay <команда> <номер вызова> — сколько секунд прошло до ответа: второй строки после эха
	delay() {
		echo "$TABLE" | awk -F '\t' -v command="$1" -v nth="$2" '
			$2 == command && $1 != last { last = $1; seen++; line = 0 }
			$2 == command && seen == nth && ++line == 2 { printf "%.3f", $4 - $3; exit }'
	}
	# has <текст ответа> <образец> <успех> <неудача> [подсказка]
	has() {
		if echo "$1" | grep -Eq "$2"; then
			ok "$3"
		else
			fail "$4"
			[ -n "${5:-}" ] && note "$5"
		fi
	}

	# 1. Протокол
	if echo "$TABLE" | awk -F '\t' '$1 == 1' | grep -q .; then
		fail "А.3: на пустой кадр прибор ответил"
	else
		ok "А.3: кадр без символов, кроме пробелов, не обрабатывается"
	fi
	has "$(reply uptime 2)" '^uptime: [0-9]+ ms' \
		"А.3: лишние пробелы в начале, в конце и между словами не мешают команде" \
		"А.3: кадр с лишними пробелами не выполнен" \
		"Слова кадра разделены одним или несколькими пробелами, пробелы в начале и в конце допустимы."
	has "$(reply 'upx<BS>time' 1)" '^uptime: [0-9]+ ms' \
		"А.4: опечатка, стёртая Backspace, не попадает в команду" \
		"А.4: кадр, исправленный Backspace, не выполнен" \
		"Backspace (0x08 и 0x7f) убирает из кадра последний символ."
	has "$(reply xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx 1)" '^error: ' \
		"А.6: кадр длиннее 63 символов не выполняется, ответ error:" \
		"А.6: на кадр длиннее 63 символов нет ответа error:"
	has "$(reply led_period 1)" '^error: ' \
		"А.6: команда с пятью аргументами не выполняется, ответ error:" \
		"А.6: на команду с пятью аргументами нет ответа error:"
	has "$(reply blink 1)" "^error: unknown command 'blink', try help" \
		"А.6: неизвестная команда — error: unknown command 'blink', try help" \
		"А.6: нет ответа error: unknown command '<имя>', try help на неизвестную команду"
	if [ -z "$(reply p 1)" ] && echo "$(reply i 1)" | grep -Eq '^pi: [0-9]+\.[0-9]+ in [0-9]+ ms'; then
		ok "Ф1.4: пока кадр pi набирался, прибор досчитал π"
	else
		fail "Ф1.4: кадр, набранный наполовину, задержал работу прибора"
		note "Скрипт отправляет «p», ждёт 6 с, пока идёт расчёт, и дописывает «i». К этому моменту π должно быть готово."
	fi

	# 2. Команды
	HELP="$(reply help 1)"
	MISSING=""
	for cmd in help info uptime led_enable led_disable led_blink led_period button pi_start pi profiling profiling_reset; do
		echo "$HELP" | grep -Eq "^$cmd[[:space:]]+[^[:space:]]" || MISSING="$MISSING $cmd"
	done
	if [ -z "$MISSING" ]; then
		ok "Ф1.3: help перечисляет все 12 команд прибора, у каждой справка"
	else
		fail "Ф1.3: в ответе help нет команд со справкой:$MISSING"
	fi
	has "$(echo "$HELP" | head -1)" '^help[[:space:]]' \
		"Б.3: перечень help начинается с help" \
		"Б.3: перечень help начинается не с help"

	INFO="$(reply info 1)"
	ORDER="$(echo "$INFO" | sed -n 's/^\([a-z-]*\):.*/\1/p' | tr '\n' ' ')"
	if [ "$ORDER" = "name version project repo board serial chip pico-sdk " ]; then
		ok "Ф2.1: паспорт — восемь строк в порядке приложения Б"
	else
		fail "Ф2.1: строки паспорта не по приложению Б: $ORDER"
		note "Порядок: name, version, project, repo, board, serial, chip, pico-sdk."
	fi
	has "$INFO" '^project: 231-firmware-template$' \
		"Ф2.1: имя проекта 231-firmware-template" \
		"Ф2.1: в паспорте не то имя проекта"
	has "$INFO" '^version: [0-9]+\.[0-9]+\.[0-9]+$' \
		"Ф2.1: версия прошивки вида 1.0.0" \
		"Ф2.1: версия прошивки не вида 1.0.0"
	has "$INFO" "^serial: $DEVICE_SERIAL$" \
		"Ф2.1: серийный номер в паспорте совпадает с номером платы" \
		"Ф2.1: серийный номер в паспорте не совпадает с номером платы в шапке лога"
	has "$INFO" '^chip: manufacturer 0x[0-9a-f]{3}, part 0x[0-9a-f]{4}, revision [0-9]+$' \
		"Ф2.1: сведения о кристалле в формате приложения Б" \
		"Ф2.1: строка chip не в формате приложения Б"

	U1="$(reply uptime 1 | sed -n 's/^uptime: \([0-9]*\) ms$/\1/p')"
	U3="$(reply uptime 3 | sed -n 's/^uptime: \([0-9]*\) ms$/\1/p')"
	# sent <команда> <номер вызова> — время отправки N-го кадра с этой командой
	sent() {
		echo "$TABLE" | awk -F '\t' -v command="$1" -v nth="$2" '
			$2 == command && $1 != last { last = $1; seen++ }
			$2 == command && seen == nth { print $3; exit }'
	}
	T1="$(sent uptime 1)"
	T3="$(sent uptime 3)"
	if [ -n "$U1" ] && [ -n "$U3" ] && [ -n "$T1" ] && [ -n "$T3" ] &&
		awk -v u="$((U3 - U1))" -v t1="$T1" -v t3="$T3" 'BEGIN { d = u - (t3 - t1) * 1000; exit !(d > -150 && d < 150) }'; then
		ok "Ф2.2: время с момента сброса идёт вровень с часами компьютера"
	else
		fail "Ф2.2: показания uptime не идут вровень со временем в логе"
	fi

	# 3. Светодиод
	has "$(reply led_enable 1)" '^led: on, period 1000 ms$' \
		"Ф3.1: led_enable — «горит», период после сброса 1000 мс" \
		"Ф3.1: ответ led_enable не led: on, period 1000 ms"
	has "$(reply led_disable 1)" '^led: off, period 1000 ms$' \
		"Ф3.1: led_disable — «выключен»" \
		"Ф3.1: ответ led_disable не led: off, period 1000 ms"
	has "$(reply led_period 2)" '^led: off, period 2000 ms$' \
		"Ф3.3: период задаётся в любом состоянии и состояния не меняет" \
		"Ф3.3: led_period 2000 в состоянии «выключен» ответил не led: off, period 2000 ms"
	has "$(reply led_blink 1)" '^led: blink, period 2000 ms$' \
		"Ф3.3: в состоянии «мигает» действует заданный раньше период" \
		"Ф3.3: led_blink ответил не led: blink, period 2000 ms"
	USAGE=0
	for n in 3 4 5 6; do
		reply led_period "$n" | grep -q '^error: usage led_period <period_ms>$' && USAGE=$((USAGE + 1))
	done
	if [ "$USAGE" -eq 4 ]; then
		ok "Б.1: led_period без аргумента, 5x, -1 и 4294967296 — error: usage led_period <period_ms>"
	else
		fail "Б.1: из четырёх неверных записей периода ответ error: usage дан на $USAGE"
		note "Число — только цифры, от 0 до 4 294 967 295. Знак, посторонние символы и переполнение — ошибка записи."
	fi
	has "$(reply led_period 7)" '^error: period_ms must be greater than 0$' \
		"Б.3: led_period 0 — error: period_ms must be greater than 0" \
		"Б.3: на led_period 0 нет ответа error: period_ms must be greater than 0"
	has "$(reply led_period 8)" '^led: blink, period 1000 ms$' \
		"Ф3.3: после отказа период меняется следующей верной командой" \
		"Ф3.3: led_period 1000 ответил не led: blink, period 1000 ms"

	# 4. Кнопка
	has "$(reply button 1)" '^button( [0-9]+)?: (pressed|released), presses [0-9]+$' \
		"Ф4.4: button выдаёт состояние кнопки и число нажатий" \
		"Ф4.4: ответ button не в формате button: released, presses 0"

	# 5. Расчёт π
	has "$(reply pi 1)" '^pi: not started$' \
		"Ф5.5: до запуска pi отвечает pi: not started" \
		"Ф5.5: до запуска pi ответил не pi: not started"
	has "$(reply pi_start 1)" '^error: terms must be greater than 0$' \
		"Б.3: pi_start 0 — error: terms must be greater than 0" \
		"Б.3: на pi_start 0 нет ответа error: terms must be greater than 0"
	if reply pi_start 2 | grep -q '^error: usage pi_start' && reply pi_start 3 | grep -q '^error: usage pi_start'; then
		ok "Б.1: pi_start 5x и pi_start 10 20 — error: usage pi_start [<terms>]"
	else
		fail "Б.1: на pi_start 5x или pi_start 10 20 нет ответа error: usage pi_start [<terms>]"
	fi
	has "$(reply pi_start 4)" '^pi: started, 1000000 terms$' \
		"Ф5.1: pi_start без аргумента — 1 000 000 членов, ответ сразу" \
		"Ф5.1: pi_start ответил не pi: started, 1000000 terms"
	has "$(reply pi 2)" '^pi: running$' \
		"Ф5.5: во время расчёта pi отвечает pi: running" \
		"Ф5.5: во время расчёта pi ответил не pi: running"
	has "$(reply pi_start 5)" '^error: pi is busy$' \
		"Ф5.4: новый расчёт не запускается, пока идёт текущий" \
		"Ф5.4: pi_start во время расчёта ответил не error: pi is busy"
	D="$(delay uptime 3)"
	if [ -n "$D" ] && awk -v d="$D" 'BEGIN { exit !(d < 0.2) }'; then
		ok "Ф5.3: во время расчёта uptime ответил через $D с"
	else
		fail "Ф5.3: во время расчёта uptime ответил через ${D:-?} с"
		note "Расчёт держит ядро не дольше порции. Если ответ ждёт секунды, задача считает всё за один вызов."
	fi
	PI="$(reply i 1 | sed -n 's/^pi: \([0-9.]*\) in \([0-9]*\) ms$/\1 \2/p')"
	if [ -n "$PI" ] && awk -v p="${PI% *}" 'BEGIN { d = p - 3.14159265358979; if (d < 0) d = -d; exit !(d <= 1.0e-6 + 1e-9) }'; then
		ok "Ф5.2: при 1 000 000 членов π = ${PI% *}, отличие не больше 10⁻⁶"
	else
		fail "Ф5.2: результат ${PI% *} отличается от π больше чем на 10⁻⁶ или нет ответа pi: <значение> in <время> ms"
	fi
	if [ -n "$PI" ] && [ "${PI#* }" -ge 3000 ] && [ "${PI#* }" -le 7000 ]; then
		ok "Ф5.5: время расчёта ${PI#* } мс — близко к calc_pi из 2.2"
	else
		fail "Ф5.5: время расчёта ${PI#* } мс далеко от 4,7 с"
	fi
	SHORT="$(reply pi 3 | sed -n 's/^pi: [0-9.]* in \([0-9]*\) ms$/\1/p')"
	if [ -n "$SHORT" ] && [ -n "$PI" ] && [ "$SHORT" -lt "$((${PI#* } / 5))" ]; then
		ok "Ф5.1: 100 000 членов считаются в 10 раз быстрее: $SHORT мс"
	else
		fail "Ф5.1: pi_start 100000 не считает в 10 раз быстрее: ${SHORT:-?} мс"
	fi

	# 6. Профилирование
	PROF="$(reply profiling 1)"
	MISSING=""
	for sw in loop command led button pi; do
		echo "$PROF" | grep -Eq "^$sw[[:space:]]+count [0-9]+[[:space:]]+mean [0-9]+\.[0-9]{2} us[[:space:]]+max [0-9]+ us$" || MISSING="$MISSING $sw"
	done
	if [ -z "$MISSING" ]; then
		ok "Ф6.1, Ф6.2: секундомеры loop, command, led, button и pi — число замеров, среднее и максимум"
	else
		fail "Ф6.2: нет строк секундомеров в формате приложения Б:$MISSING"
	fi
	SLOW=""
	for sw in led button pi; do
		MAX="$(echo "$PROF" | sed -n "s/^$sw[[:space:]].*max \([0-9]*\) us$/\1/p")"
		[ -n "$MAX" ] && [ "$MAX" -le 1000 ] || SLOW="$SLOW $sw=${MAX:-?}"
	done
	if [ -z "$SLOW" ]; then
		ok "Н1: после расчёта π обработчики светодиода, кнопки и π длятся не дольше 1 мс"
	else
		fail "Н1: обработчик дольше 1 мс, мкс:$SLOW"
		note "Порция π должна укладываться в 0,5 мс. Уменьшите число членов за вызов."
	fi
	has "$(reply profiling_reset 2)" '^profiling reset$' \
		"Ф6.2: profiling_reset сбрасывает результаты" \
		"Ф6.2: ответ profiling_reset не profiling reset"
	C1="$(echo "$PROF" | sed -n 's/^loop[[:space:]]*count \([0-9]*\).*/\1/p')"
	C2="$(reply profiling 2 | sed -n 's/^loop[[:space:]]*count \([0-9]*\).*/\1/p')"
	if [ -n "$C1" ] && [ -n "$C2" ] && [ "$C2" -lt "$C1" ]; then
		ok "Ф6.2: после сброса число замеров начинается заново: $C1 → $C2"
	else
		fail "Ф6.2: после profiling_reset число замеров не сбросилось: ${C1:-?} → ${C2:-?}"
	fi
fi

# ---------- код ----------

CODE="$(fw_join '*.c' '*.h')"
if grep -Eq '(sleep_(ms|us)|busy_wait_[a-z_]*)[[:space:]]*\(' "$CODE"; then
	fail "Н2: в прошивке есть паузы: $(grep -Eo '(sleep_(ms|us)|busy_wait_[a-z_]*)' "$CODE" | sort -u | tr '\n' ' ')"
else
	ok "Н2: в прошивке нет sleep_ms(), sleep_us() и busy_wait_*()"
fi

MISSING=""
for f in CMakeLists.txt firmware.h main.c platform/platform.h platform/platform.c \
	logic/api/api.h logic/api/api.c logic/api/api-commands.h logic/api/api-callbacks.c; do
	[ -f "$FW_SRC/$f" ] || MISSING="$MISSING $f"
done
for name in stdio-text-protocol systime profiling device logging button; do
	[ -f "$FW_LIBS/$name/CMakeLists.txt" ] && [ -d "$FW_LIBS/$name/include/$name" ] && [ -d "$FW_LIBS/$name/src" ] || MISSING="$MISSING libs/$name"
done
for d in led-task pi-task; do
	[ -d "$FW_SRC/logic/$d" ] || MISSING="$MISSING logic/$d"
done
if [ -z "$MISSING" ]; then
	ok "У1, У2: раскладка проекта и библиотек — по части 2 ТЗ, раздел 1"
else
	fail "У1, У2: нет по раскладке части 2 ТЗ:$MISSING"
fi

if [ -f "$FW_SRC/main.c" ] && grep -Eq '#include[[:space:]]*[<"](pico|hardware)/' "$(fw_code "$FW_SRC/main.c")"; then
	fail "П7: main.c подключает заголовки SDK"
else
	ok "П7: main.c не подключает заголовков SDK"
fi
if [ -f "$FW_SRC/logic/api/api.c" ] && grep -Eq '"(info|uptime|led_[a-z]+|button|pi|pi_start|profiling|profiling_reset)"' "$(fw_code "$FW_SRC/logic/api/api.c")"; then
	fail "П2: в api.c есть имена команд прибора, кроме help"
else
	ok "П2: в api.c из имён команд только help"
fi
PRINTS=""
for f in $(find "$FW_SRC" "$FW_LIBS" -name '*.c' -not -path '*/build/*' | sort); do
	case "$(basename "$f")" in api.c|api-callbacks.c|log.c|stdio-text-protocol.c) continue ;; esac
	grep -Eq '\b(printf|puts|putchar)[[:space:]]*\(' "$(fw_code "$f")" && PRINTS="$PRINTS $(basename "$f")"
done
if [ -z "$PRINTS" ]; then
	ok "П3: ответы печатают только api.c и api-callbacks.c, журнал — только logging"
else
	fail "П3: печатают модули:$PRINTS"
	note "Модули возвращают данные. Печать ответа — дело api."
fi

# ---------- сборка ----------

BUILD_KEEP=1
BUILD_DIR=""
build_project "$FW_SRC"
if [ -n "$BUILD_DIR" ]; then
	WARNINGS="$(grep -c 'warning:' "$BUILD_DIR/make.log" || true)"
	if [ "$WARNINGS" -eq 0 ]; then
		ok "Н4: проект собирается с -Wall без предупреждений"
	else
		fail "Н4: при сборке $WARNINGS предупреждений"
		grep 'warning:' "$BUILD_DIR/make.log" | head -5
	fi
	BIN="$(ls "$BUILD_DIR"/*.bin 2>/dev/null | head -1)"
	if [ -n "$BIN" ]; then
		SIZE="$(wc -c < "$BIN" | tr -d ' ')"
		if [ "$SIZE" -le 49152 ]; then
			ok "Н3: образ .bin — $SIZE байт, не больше 48 КБ"
		else
			fail "Н3: образ .bin — $SIZE байт, больше 48 КБ"
		fi
	fi

	if [ -n "${PICO_SDK_PATH:-}" ]; then
		# П4: заголовок SDK в логике и в библиотеках без SDK останавливает сборку
		COPY="$(mktemp -d)"
		cp -R "$FW_SRC" "$COPY/project"
		cp -R "$FW_LIBS" "$COPY/libs"
		rm -rf "$COPY/project/build"
		for f in project/logic/api/api.c libs/logging/src/log.c libs/button/src/button.c; do
			[ -f "$COPY/$f" ] && { printf '#include "pico/stdlib.h"\n'; cat "$COPY/$f"; } > "$COPY/$f.new" && mv "$COPY/$f.new" "$COPY/$f"
		done
		cmake -S "$COPY/project" -B "$COPY/build" -G "Unix Makefiles" > "$COPY/cmake.log" 2>&1
		# /fast собирает одну цель без зависимостей: ошибка в одной библиотеке не мешает другой
		make -k -C "$COPY/build" --no-print-directory logic/fast logging/fast button/fast > "$COPY/make.log" 2>&1
		STOPPED=""
		for f in api.c log.c button.c; do
			grep -Eq "$f.*pico/stdlib\.h: No such file" "$COPY/make.log" && STOPPED="$STOPPED $f"
		done
		if [ "$STOPPED" = " api.c log.c button.c" ]; then
			ok "П4: #include \"pico/stdlib.h\" в api.c, log.c и button.c останавливает сборку"
		else
			fail "П4: заголовок SDK остановил сборку только в:${STOPPED:- ни одном файле}"
			note "Логика и библиотеки без железа не подключают SDK, и сборка сама проверяет эту границу."
		fi
		rm -rf "$COPY"

		# Ф6.3: профилирование выключается одной строкой
		COPY="$(mktemp -d)"
		cp -R "$FW_SRC" "$COPY/project"
		cp -R "$FW_LIBS" "$COPY/libs"
		rm -rf "$COPY/project/build"
		sed -i.bak 's/PROFILING_ENABLED=1/PROFILING_ENABLED=0/' "$COPY/project/CMakeLists.txt"
		if ! grep -q 'PROFILING_ENABLED=0' "$COPY/project/CMakeLists.txt"; then
			fail "Ф6.3: в CMakeLists.txt нет строки PROFILING_ENABLED=1, которую можно переключить"
		elif cmake -S "$COPY/project" -B "$COPY/build" -G "Unix Makefiles" > "$COPY/cmake.log" 2>&1 &&
			make -C "$COPY/build" --no-print-directory > "$COPY/make.log" 2>&1; then
			OFF="$(ls "$COPY/build"/*.bin | head -1)"
			OFF_SIZE="$(wc -c < "$OFF" | tr -d ' ')"
			OFF_ELF="$(ls "$COPY/build"/*.elf | head -1)"
			if arm-none-eabi-nm "$OFF_ELF" 2>/dev/null | grep -Eq ' (profiling_start|profiling_stop)$'; then
				fail "Ф6.3: в сборке без профилирования остались вызовы секундомеров"
			elif [ "$OFF_SIZE" -lt "$SIZE" ]; then
				ok "Ф6.3: без профилирования образ меньше ($OFF_SIZE против $SIZE байт), секундомеров в нём нет"
			else
				fail "Ф6.3: без профилирования образ не меньше: $OFF_SIZE против $SIZE байт"
			fi
		else
			fail "Ф6.3: с PROFILING_ENABLED=0 проект не собирается"
			tail -10 "$COPY/make.log"
		fi
		rm -rf "$COPY"
	fi
	rm -rf "$BUILD_DIR"
fi

finish "$TITLE"
