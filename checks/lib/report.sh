#!/usr/bin/env bash
# Общий отчёт проверок: вывод в терминал и в сводку GitHub Actions.

CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_REPORT=""

# Номер задания из имени скрипта: check-1-1-3.sh → 1.1.3
CHECKS_TASK="$(basename "$0" .sh | sed 's/^check-//; s/-/./g')"
# Пункты для JSON-отчёта копятся отдельным файлом (см. report.py).
CHECKS_ITEMS="${CHECKS_JSON:+${CHECKS_JSON}.items}"
[ -n "$CHECKS_ITEMS" ] && : > "$CHECKS_ITEMS"

# item <ok|fail> <текст> — строка для JSON-отчёта, если сборка отчёта включена
item() {
	[ -n "$CHECKS_ITEMS" ] && printf '%s\t%s\n' "$1" "$2" >> "$CHECKS_ITEMS"
	return 0
}

ok() {
	CHECKS_PASSED=$((CHECKS_PASSED + 1))
	CHECKS_REPORT+="- ✅ $1"$'\n'
	item ok "$1"
	echo "✅ $1"
}

fail() {
	CHECKS_FAILED=$((CHECKS_FAILED + 1))
	CHECKS_REPORT+="- ❌ $1"$'\n'
	item fail "$1"
	echo "❌ $1"
}

note() {
	CHECKS_REPORT+="  $1"$'\n'
	echo "   $1"
}

# Проверка по регулярному выражению: match <файл> <выражение> <текст успеха> <текст неудачи>
match() {
	if grep -Eq "$2" "$1"; then
		ok "$3"
	else
		fail "$4"
	fi
}

finish() {
	local title="$1"
	local total=$((CHECKS_PASSED + CHECKS_FAILED))
	echo
	echo "Пройдено $CHECKS_PASSED из $total."
	if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
		{
			echo "## $title"
			echo
			echo "$CHECKS_REPORT"
			echo "**Пройдено $CHECKS_PASSED из $total.**"
		} >> "$GITHUB_STEP_SUMMARY"
	fi
	if [ -n "${CHECKS_JSON:-}" ]; then
		python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/report.py" \
			--task "$CHECKS_TASK" --title "$title" \
			--passed "$CHECKS_PASSED" --total "$total" \
			--items "$CHECKS_ITEMS" > "$CHECKS_JSON"
	fi

	[ "$CHECKS_FAILED" -eq 0 ]
}
