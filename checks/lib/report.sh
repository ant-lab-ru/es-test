#!/usr/bin/env bash
# Общий отчёт проверок: вывод в терминал и в сводку GitHub Actions.

CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_REPORT=""

ok() {
	CHECKS_PASSED=$((CHECKS_PASSED + 1))
	CHECKS_REPORT+="- ✅ $1"$'\n'
	echo "✅ $1"
}

fail() {
	CHECKS_FAILED=$((CHECKS_FAILED + 1))
	CHECKS_REPORT+="- ❌ $1"$'\n'
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
	[ "$CHECKS_FAILED" -eq 0 ]
}
