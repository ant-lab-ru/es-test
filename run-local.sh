#!/usr/bin/env bash
# Локальный прогон проверок по репозиторию обучающегося — тот же код, что и в CI.
# Использование: ./run-local.sh <путь к репозиторию> [номер задания]
#   ./run-local.sh ../es-student          — все проверки занятия 1.1
#   ./run-local.sh ../es-student 1.1.2    — одна проверка
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${1:-}"
TASK="${2:-}"

if [ -z "$REPO" ]; then
	echo "Использование: $0 <путь к репозиторию> [номер задания]" >&2
	exit 2
fi

if [ -n "$TASK" ]; then
	SCRIPTS="$ROOT/checks/check-${TASK//./-}.sh"
else
	SCRIPTS="$(find "$ROOT/checks" -maxdepth 1 -name 'check-*.sh' | sort)"
fi

FAILED=0
for script in $SCRIPTS; do
	if [ ! -x "$script" ]; then
		echo "Нет проверки: $script" >&2
		exit 2
	fi
	echo
	echo "── $(basename "$script") ──"
	"$script" "$REPO" || FAILED=1
done

echo
if [ "$FAILED" -eq 0 ]; then
	echo "Все проверки пройдены."
else
	echo "Есть непройденные проверки."
fi
exit "$FAILED"
