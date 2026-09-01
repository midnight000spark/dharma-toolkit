#!/usr/bin/env bash
# Dharma Toolkit — односторонние уведомления в Telegram.
# Вызывается из пакетов dharma-flash по D-27.
#
# Использование: ./scripts/notify.sh "✅ 5.0.2 завершён: 64 теста зелёные"
#   DHARMA_NOTIFY_DEBUG=1 — печатать итоговый статус доставки в stderr
#   (текст сообщения не логируется).
# Конфиг: ~/.config/dharma/telegram (token=, chat=), права 600.
# Fail-silent: любой сбой — выход 0, пакет агента не ломается.

set -u
CFG="${DHARMA_NOTIFY_CONFIG:-$HOME/.config/dharma/telegram}"
MSG="${1:-Dharma: задача выполнена}"

# Проверка конфига — тихий выход, если отсутствует
[ -r "$CFG" ] || exit 0

TOKEN="$(sed -n 's/^token=//p' "$CFG" 2>/dev/null | head -n1)"
CHAT="$(sed -n 's/^chat=//p' "$CFG" 2>/dev/null | head -n1)"
[ -n "$TOKEN" ] && [ -n "$CHAT" ] || exit 0

API="https://api.telegram.org/bot${TOKEN}/sendMessage"
JSON_OK='^[[:space:]]*\{"ok":true'

# Payload собирается кодированием, а не интерполяцией (B-22): кавычка или
# обратный слэш в тексте ломали JSON и уведомление терялось молча.
payload() {
  if command -v jq >/dev/null 2>&1; then
    jq -cn --arg c "$CHAT" --arg t "$MSG" --arg m "$1" \
      '{chat_id:$c, text:$t} + (if $m == "" then {} else {parse_mode:$m} end)'
  else
    python3 -c '
import json, sys
p = {"chat_id": sys.argv[1], "text": sys.argv[2]}
if sys.argv[3]:
    p["parse_mode"] = sys.argv[3]
print(json.dumps(p, ensure_ascii=False))' "$CHAT" "$MSG" "$1"
  fi
}

# $1 — режим разбора markdown ("" = обычный текст)
post() {
  curl -s -m 10 -X POST "$API" \
    -H "Content-Type: application/json" \
    -d "$(payload "$1")" 2>/dev/null
}

send() {
  local body
  body="$(post "$1")"
  [[ "$body" =~ $JSON_OK ]]
}

# Markdown-разметка — причина тихой потери пуша: несовместимый символ
# (например `_` в имени переменной) даёт 400, и сообщение не доходило.
# Поэтому: пробуем Markdown, при отказе — один повтор обычным текстом.
if send "Markdown"; then
  rc=0
elif send ""; then
  rc=0
else
  rc=1
fi

[ "${DHARMA_NOTIFY_DEBUG:-0}" = "1" ] &&
  { [ "$rc" = 0 ] && echo "notify: delivered" >&2 || echo "notify: FAILED (сообщение потеряно)" >&2; }

exit 0
