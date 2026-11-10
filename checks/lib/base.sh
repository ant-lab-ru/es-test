#!/usr/bin/env bash
# Базовый набор команд прибора. Проект растёт по вехам: от шаблона занятия 2.3 до рекордера
# занятия 3.2, и команды в нём копятся. Задание проверяет свои команды, а базовые —
# каждый раз заново: если задание сломало то, что прибор умел, базовая команда пропадёт
# из help или перестанет отвечать в логе.
#
# Базовый набор — help, info, version и uptime. Они не привязаны к периферии задания:
# help и info — опись прибора, version — номер прошивки, uptime — признак живого суперцикла.
# Команду, которая нужна одному заданию, проверяет только это задание.
#
# Подключается после lib/exchange.sh. pipefail проверки ставят не везде: без него
# `echo "$answer" | grep -q` ищет совпадение до конца, а не до первого совпадения.
set +o pipefail

BASE_COMMANDS="help info version uptime"
# Команды, ответ которых обязан быть в логе каждого задания: остальные базовые
# проверяются только в перечне help.
BASE_LOGGED="help info"

# base_spec <команда> — регулярное выражение ответа на базовую команду по протоколу
# ТЗ 2.3, приложение А и приложение Б
base_spec() {
	case "$1" in
		help) echo '^help[[:space:]]+[^[:space:]]' ;;
		info) echo '^name:[[:space:]]*[^[:space:]]' ;;
		version) echo '^version: [0-9]+\.[0-9]+\.[0-9]+$' ;;
		uptime) echo '^uptime: [0-9]+ ms$' ;;
	esac
}

# base_help <ответ на help> — проверяет, что базовые команды есть в перечне help
base_help() {
	local out="$1" c missing=""
	for c in $BASE_COMMANDS; do
		echo "$out" | grep -Eq "^$c[[:space:]]+[^[:space:]]" || missing="$missing $c"
	done
	if [ -z "$missing" ]; then
		ok "help перечисляет базовые команды: $BASE_COMMANDS"
	else
		fail "В ответе help нет базовых команд:$missing"
		note "Прибор копит команды: то, что работало, задание ломать не должно."
	fi
}

# base_replies <лог> — проверяет, что на каждую базовую команду в логе есть ответ
# по протоколу. У help и info ответ спрашивают все скрипты заданий, поэтому их ответ
# в логе обязателен. version и uptime — сборка прибора и признак живого суперцикла:
# в перечне help они проверяются, а обязанности слать их в каждом логе нет.
# Ответ берётся из таблицы обмена, а не через функцию ответа проверки: та отбрасывает
# первую строку, и у help это строка про саму help.
base_replies() {
	local log="$1" c n count spec table found
	table="$(exchange_table "$log")"
	for c in $BASE_COMMANDS; do
		count="$(exchange_calls "$log" "$c")"
		spec="$(base_spec "$c")"
		if [ "$count" -eq 0 ]; then
			case " $BASE_LOGGED " in
				*" $c "*)
					fail "В логе нет базовой команды $c"
					note "Скрипт задания спрашивает help и info у каждого прибора."
					;;
				*)
					note "Ответ на $c в логе не проверялся: скрипт задания её не спрашивал."
					;;
			esac
			continue
		fi
		found=""
		n=1
		while [ "$n" -le "$count" ]; do
			found="$(exchange_replies "$table" "$c" "$n" | cut -f2 | grep -E "$spec" | head -1)"
			if [ -z "$found" ] && [ "$n" -lt "$count" ]; then
				n=$((n + 1))
				continue
			fi
			break
		done
		if [ -n "$found" ]; then
			ok "Базовая команда $c отвечает в логе: $found"
		else
			fail "Ответ на базовую команду $c не по протоколу"
			note "Задание сломало команду, которую прибор умел раньше: $c вызывалась $count раз, ответа по протоколу нет."
		fi
	done
}

# base_run <лог> — базовый набор на логе обмена: перечень help и ответ на каждую команду.
# Ответ берётся из таблицы, а не через функцию ответа проверки: та отбрасывает первую
# строку, и у help это строка про саму help.
base_run() {
	base_help "$(exchange_replies "$(exchange_table "$1")" help 1 | cut -f2)"
	base_replies "$1"
}
