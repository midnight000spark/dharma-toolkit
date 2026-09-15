#!/usr/bin/env bash
# cost-check.sh — стоимость последних сессий OpenCode из локальной SQLite.
#
# Назначение: fallback-источник для budget-guard (`.opencode/plugins/budget-guard.ts`),
# когда плагин недоступен. Стоимость сессии в БД (`session.cost`) — авторитетный
# факт: агент изнутри сессии видит цену неточно (прецедент: отчёт заявил ~$0.45
# при фактических $0.71 — см. F-60).
#
# Использование:
#   ./scripts/cost-check.sh [LIMIT]     # по умолчанию 10 последних сессий
#
# Переменные окружения:
#   OPENCODE_DB — путь к базе (по умолчанию XDG data dir / opencode / opencode.db)
#
# Exit: 0 — вывод получен; 1 — нет базы или нет sqlite3.
# Скрипт read-only: база открывается на чтение транзакции не пишутся.
set -euo pipefail

DB="${OPENCODE_DB:-${XDG_DATA_HOME:-$HOME/.local/share}/opencode/opencode.db}"
LIMIT="${1:-10}"

if [[ ! -f "$DB" ]]; then
  echo "Ошибка: база OpenCode не найдена ($DB)" >&2
  exit 1
fi

if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "Ошибка: sqlite3 не установлен — чтение стоимости недоступно" >&2
  exit 1
fi

if [[ ! "$LIMIT" =~ ^[0-9]+$ ]]; then
  echo "Ошибка: LIMIT должен быть числом (получено: $LIMIT)" >&2
  exit 1
fi

# Запрос идёт в WAL-режиме поверх живой базы, поэтому задаём busy_timeout:
# параллельная запись со стороны OpenCode не должна давать «database is locked».
sqlite3 -cmd ".timeout 2000" "$DB" <<SQL
.mode column
.headers on
SELECT
  datetime(time_updated / 1000, 'unixepoch', 'localtime') AS session_time,
  printf('\$%.2f', cost) AS cost,
  tokens_input   AS inp,
  tokens_output  AS outp,
  tokens_reasoning AS think,
  json_extract(model, '\$.providerID') AS provider,
  substr(id, 1, 24) AS session
FROM session
WHERE cost > 0
ORDER BY time_updated DESC
LIMIT ${LIMIT};
SQL
