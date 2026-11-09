#!/usr/bin/env bash
# Задание п3.2.5 «Запись испытательного сигнала».
# Вывод GP20 отдан блоку ШИМ, команда generate_tone <Hz> держит на нём тон, перемычка ведёт
# тон на GP26. rec_audio.py --melody играет припев и сохраняет его в melody.wav, итог — в melody.log.
# Читает код и собирает проект, читает заголовок WAV и лог, находит в записи ноты
# и сравнивает их частоты с нотами припева.
# Использование: check-3-2-5.sh <путь к репозиторию> [папка проекта]
set -u

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
. "$LIB/report.sh"
. "$LIB/build.sh"
. "$LIB/code.sh"
. "$LIB/device.sh"
. "$LIB/firmware.sh"

fw_start "Задание 3.2.5 — Запись испытательного сигнала" 321-audio-recorder "${1:-.}" "${2:-}"

fw_need PLATFORM_C platform.c
fw_need API_C api-callbacks.c

if [ -n "$PLATFORM_C" ]; then
	PLATFORM="$(fw_code "$PLATFORM_C")"
	if grep -Eq 'GPIO_FUNC_PWM' "$PLATFORM" &&
		grep -Eq '#define[[:space:]]+[A-Z_]*PIN[[:space:]]+20([^0-9]|$)|gpio_set_function[[:space:]]*\([[:space:]]*20[[:space:]]*,' "$PLATFORM"; then
		ok "platform: вывод GP20 отдан блоку ШИМ"
	else
		fail "platform: вывод GP20 не отдан блоку ШИМ"
		note "Вывод отдаёт блоку ШИМ gpio_set_function(<вывод>, GPIO_FUNC_PWM), разобрано в т3.2.3."
	fi
	if grep -Eq 'pwm_set_wrap[[:space:]]*\(' "$PLATFORM" && grep -Eq 'pwm_set_(gpio|chan)_level[[:space:]]*\(' "$PLATFORM"; then
		ok "platform: тон задают период и порог блока ШИМ"
	else
		fail "platform: нет pwm_set_wrap() и pwm_set_gpio_level()"
		note "Период тона — wrap блока ШИМ, половина периода — порог."
	fi
fi

if [ -n "$API_C" ]; then
	API="$(fw_code "$API_C")"
	if grep -Eq '"generate_tone"' "$API"; then
		ok "api: команда generate_tone в таблице команд"
	else
		fail "api: нет команды generate_tone"
	fi
	if grep -Eq '(^|[^a-z_])pwm_[a-z_]+[[:space:]]*\(' "$API"; then
		fail "api-callbacks.c: команда обращается к блоку ШИМ напрямую"
		note "Блок ШИМ — железо, им место в platform."
	else
		ok "api-callbacks.c: к блоку ШИМ обращается только platform"
	fi
fi

LOGIC="$(mktemp)"
find "$FW_SRC/logic" -type f \( -name '*.c' -o -name '*.h' \) 2>/dev/null | sort |
	while read -r f; do cat "$(fw_code "$f")"; done > "$LOGIC"
if grep -Eq '#include[[:space:]]*[<"](pico|hardware)/|(^|[^a-z_])(adc|dma|pwm)_[a-z_]+[[:space:]]*\(|time_us_' "$LOGIC"; then
	fail "logic: код логики обращается к SDK"
else
	ok "logic: логика по-прежнему без SDK"
fi

build_project "$FW_SRC"

for f in rec_audio.py melody.wav melody.log; do
	if [ -f "$FW_SRC/$f" ]; then
		ok "Файл $f на месте"
	else
		file_missing "$f"
	fi
done

WAV="$FW_SRC/melody.wav"
if [ -f "$WAV" ]; then
	if [ "$(head -c 4 "$WAV")" != "RIFF" ] || [ "$(dd if="$WAV" bs=1 skip=8 count=4 2> /dev/null)" != "WAVE" ]; then
		fail "melody.wav: не файл WAV"
	else
		FMT="$(od -An -j 20 -N 2 -t u2 "$WAV" | tr -d ' ') $(od -An -j 22 -N 2 -t u2 "$WAV" | tr -d ' ') $(od -An -j 24 -N 4 -t u4 "$WAV" | tr -d ' ') $(od -An -j 34 -N 2 -t u2 "$WAV" | tr -d ' ')"
		if [ "$FMT" = "1 1 44100 16" ]; then
			ok "melody.wav: PCM, один канал, 44100 Гц, 16 бит"
		else
			fail "melody.wav: формат, каналы, частота, разрядность — $FMT, а нужно 1 1 44100 16"
		fi
	fi
fi

if device_log "$FW_SRC/melody.log" "3.2.5"; then
	L="$DEVICE_LOG"
	GOT="$(grep -E '^принято: кадров [0-9]+, отсчётов [0-9]+, пропущено кадров [0-9]+' "$L" | head -1)"
	STOP="$(grep -E '^<-- stream: stopped, [0-9]+ frames, [0-9]+ samples, [0-9]+ overruns$' "$L" | head -1)"
	if [ -z "$GOT" ] || [ -z "$STOP" ]; then
		fail "В логе нет строки «принято» или ответа stream: stopped"
		note "Лог пишет rec_audio.py, запущенный с ключами --wav melody.wav --melody."
	else
		LOST="$(echo "$GOT" | sed -E 's/.*пропущено кадров ([0-9]+).*/\1/')"
		OVER="$(echo "$STOP" | sed -E 's/.* ([0-9]+) overruns/\1/')"
		if [ "$LOST" -eq 0 ] && [ "$OVER" -eq 0 ]; then
			ok "Запись без пропущенных кадров и переполнений"
		else
			fail "В записи пропущено кадров $LOST, переполнений $OVER"
		fi
	fi
	if grep -Eq '^--> generate_tone: [0-9]+ команд' "$L"; then
		ok "Мелодию играла команда generate_tone"
	else
		fail "В логе нет строки о командах generate_tone"
		note "Запустите скрипт с ключом --melody."
	fi
fi

# Ноты в записи: участки звука между паузами, частота каждого — по переходам через ноль.
# Порядок и частоты нот припева — по таблице задания, допуск 1 %.
if [ -f "$WAV" ]; then
	NOTES="$(python3 - "$WAV" <<'EOF'
import struct, sys, wave

EXPECTED = [659, 698, 587, 659, 659, 698, 587, 659, 523, 494, 587,
            659, 698, 587, 659, 523, 587, 494, 494, 415, 349, 330,
            659, 698, 587, 659, 659, 698, 587, 659, 523, 494, 587,
            330, 587, 523, 523, 494, 587, 523, 494, 440, 440]

w = wave.open(sys.argv[1])
if w.getsampwidth() != 2:
    print("ERR запись не 16-битная"); sys.exit()
n = w.getnframes()
x = struct.unpack("<%dh" % n, w.readframes(n))
rate = w.getframerate()

# размах в окнах по 5 мс, звук — размах больше четверти наибольшего
B = rate // 200
spans = [max(x[i:i + B]) - min(x[i:i + B]) for i in range(0, n - B, B)]
level = max(spans) / 4 if spans else 0
notes, start = [], None
for k, s in enumerate(spans + [0]):
    if s > level and start is None:
        start = k
    elif s <= level and start is not None:
        if k - start >= 4:
            notes.append((start * B, k * B))
        start = None

found = []
for a, b in notes:
    # края ноты отбрасываются: там фильтр постоянной составляющей ещё не успокоился
    a += rate // 100
    b -= rate // 200
    seg = x[a:b]
    ups = [i + seg[i - 1] / (seg[i - 1] - seg[i]) for i in range(1, len(seg)) if seg[i - 1] < 0 <= seg[i]]
    if len(ups) < 3:
        found.append(0.0)
    else:
        found.append((len(ups) - 1) * rate / (ups[-1] - ups[0]))

print("COUNT %d %d" % (len(found), len(EXPECTED)))
bad = 0
for i, (f, e) in enumerate(zip(found, EXPECTED)):
    if abs(f - e) > e * 0.01:
        bad += 1
        if bad <= 3:
            print("BAD нота %d: %.1f Гц, а нужно %d Гц" % (i + 1, f, e))
print("BADS %d" % bad)
EOF
)"
	COUNT="$(echo "$NOTES" | sed -nE 's/^COUNT ([0-9]+) ([0-9]+)$/\1 \2/p')"
	set -- $COUNT
	if echo "$NOTES" | grep -q '^ERR'; then
		fail "melody.wav: $(echo "$NOTES" | sed -n 's/^ERR //p')"
	elif [ "${1:-0}" != "${2:-x}" ]; then
		fail "В записи найдено нот ${1:-0}, а в припеве ${2:-43}"
		note "Ноты разделяет пауза в 40 мс. Если нот меньше, проверьте перемычку GP20 — GP26 и что тон выключается командой generate_tone 0."
	elif [ "$(echo "$NOTES" | sed -n 's/^BADS //p')" = "0" ]; then
		ok "Нот в записи $1, как в припеве, их частоты совпадают с точностью 1 %"
	else
		fail "Частоты нот не совпадают с припевом: $(echo "$NOTES" | sed -n 's/^BAD //p' | head -1)"
		note "Если все ноты выше или ниже, частота отсчётов не 44 100 Гц или делитель блока ШИМ не 1 МГц."
	fi
fi

finish "$TITLE"
