#!/usr/bin/env bash
# Dharma Toolkit — односторонние уведомления в Telegram.
# Вызывается из пакетов dharma-flash по D-27.
#
# Использование: ./scripts/notify.sh "✅ 5.0.2 завершён: 64 теста зелёные"
# Конфиг: ~/.config/dharma/telegram (token=, chat=), права 600.
# Fail-silent: любой сбой — молчаливый выход 0, пакет агента не ломается.

set -u
CFG="${DHARMA_NOTIFY_CONFIG:-$HOME/.config/dharma/telegram}"
MSG="${1:-Dharma: задача выполнена}"

# Проверка конфига — тихий выход, если отсутствует
[ -r "$CFG" ] || exit 0

TOKEN="$(sed -n 's/^token=//p' "$CFG" 2>/dev/null | head -n1)"
CHAT="$(sed -n 's/^chat=//p' "$CFG" 2>/dev/null | head -n1)"
[ -n "$TOKEN" ] && [ -n "$CHAT" ] || exit 0

# Отправка через Telegram Bot API, таймаут 10 секунд
curl -s -m 10 -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
  -H "Content-Type: application/json" \
  -d "{\"chat_id\":\"${CHAT}\",\"text\":\"${MSG}\",\"parse_mode\":\"Markdown\"}" \
  -o /dev/null 2>/dev/null || true

exit 0
