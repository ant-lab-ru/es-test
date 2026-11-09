#!/usr/bin/env bash
# Самопроверка es-test: комментарий не меняет итог проверки. Нужна тем, кто пишет проверки.
# Использование: selftest/comments.sh <путь к эталону es-student>
#
# 1. Исходники читаются только через code_only, cmake_only или python_only.
#    Без очистки читают логи, CSV, .gitignore и RAW — сырой текст для пунктов о самом комментарии.
# 2. Копия эталона, испорченная комментариями, даёт те же ❌ и ⚠️, что и чистая.
#    Сборки здесь нет: PICO_SDK_PATH снят, на комментарии она не реагирует.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="${1:-}"
if [ ! -d "$REPO" ]; then
	echo "Использование: $0 <путь к эталону es-student>" >&2
	exit 2
fi

CLEANERS='code_only|cmake_only|python_only|fw_code'
RAW_READS="$(cd "$ROOT/checks" && {
	grep -n 'normalize' check-*.sh | grep -vE '(LOG|IGNORE|CSV|RAW)'
	grep -nE '(grep|awk|sed|cat|diff)[^|]*"\$(SRC|FW_SRC|FW_LIBS)/[^"]*\.(c|h|py|txt)"' check-*.sh
} | grep -vE "$CLEANERS")"

verdicts() {
	local script
	for script in "$ROOT"/checks/check-*.sh; do
		env -u PICO_SDK_PATH -u GITHUB_STEP_SUMMARY -u CHECKS_JSON "$script" "$1" 2> /dev/null |
			grep -E '^(❌|⚠️)' | sed "s/^/$(basename "$script" .sh) /"
	done | sort
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir "$WORK/clean" "$WORK/poisoned"
tar --exclude=build --exclude=.git -cf - -C "$REPO" . | tar -xf - -C "$WORK/clean"
tar --exclude=build --exclude=.git -cf - -C "$REPO" . | tar -xf - -C "$WORK/poisoned"
python3 "$ROOT/selftest/poison.py" "$WORK/poisoned"

verdicts "$WORK/clean" > "$WORK/clean.txt"
verdicts "$WORK/poisoned" > "$WORK/poisoned.txt"
CHANGED="$(diff "$WORK/clean.txt" "$WORK/poisoned.txt")"

STATUS=0
if [ -n "$RAW_READS" ]; then
	echo "Исходники читаются мимо очистки:"
	echo "$RAW_READS"
	STATUS=1
fi
if [ -n "$CHANGED" ]; then
	echo "Комментарии изменили итог проверок:"
	echo "$CHANGED"
	STATUS=1
fi
[ "$STATUS" -eq 0 ] && echo "Комментарии не влияют на проверки."
exit "$STATUS"
