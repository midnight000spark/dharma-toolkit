# DCP (Dynamic Context Pruning) — механика `compress` и диагностика

> Служебный документ для агентских сессий dharma. Актуально на 2026-09-15.
> Источники: исходники `@tarquinen/opencode-dcp@3.1.15`, БД/логи opencode 1.18.31, curl-тесты API, DCP issue #551.

## Что это

Плагин DCP даёт инструмент `compress` — сжатие закрытых фрагментов диалога в резюме (блоки `bN`), чтобы держать контекст под контролем.

- Спецификация плагина: `opencode.json` (поле `plugin`: `@tarquinen/opencode-dcp@latest`).
- Кэш установки: `~/.cache/opencode/packages/@tarquinen/opencode-dcp@*/`.
- Конфиг проекта: `.opencode/dcp.jsonc` (`compress.minContextLimit` / `maxContextLimit`; `debug: true` — логи в `~/.config/opencode/logs/dcp/`, включается после рестарта).
- Состояние сессий: `~/.local/share/opencode/storage/plugin/dcp/ses_<session>.json`.
  Важно: `messageIds` (карта refs) **не персистится** — живёт в памяти процесса; после рестарта пересобирается автоматически.

## Механика refs (главное)

- Каждому сообщению сессии DCP присваивает алиас `mNNNN` **по порядку**: `m0001` — первое сообщение, `m0002` — второе и т.д.
  (пропускаются «ignored» user-сообщения; в субагент-сессиях — первое user-сообщение).
- Алиасы видны в контексте как теги `<dcp-message-id>mNNNN</dcp-message-id>` на сообщениях и результатах инструментов.
  **Для `compress` использовать именно эти свежие теги.**
- Диапазон: `content:[{startId, endId, summary}]`, start ≤ end; пересекающиеся диапазоны в одном вызове запрещены.
- Сжатый фрагмент становится блоком `bN`; при повторных сжатиях `(bN)` можно вкладывать в резюме.
- Ошибка `startId/endId … is not available in the current conversation context` = ref не найден в lookup
  (`state.messageIds.byRef` ∩ список сообщений сессии).

## Диагностика «все refs недоступны» (регресс 11–15.09.2026)

Симптом: ЛЮБОЙ ref (включая свежайший) отклоняется «not available».
Это НЕ про неправильный ref: значит **`fetchSessionMessages` вернул пусто** — запрос
`GET /session/:id/message` к локальному серверу opencode завершился ошибкой
(пустой ответ → `filterMessages` → `[]` → пустой lookup).

Проверка (сессия живёт под serve на порту 8080):

```bash
# без авторизации (ожидаемо 401, если у сервиса включён пароль):
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080/session/<id>/message
# с basic-auth из ~/.config/opencode/server.env (ожидаемо 200 и полный JSON):
curl -s -u "$OPENCODE_SERVER_USERNAME:$OPENCODE_SERVER_PASSWORD" http://localhost:8080/session/<id>/message
```

Установленная причина (2026-09-11): с 00:45 создан headless-serve (`opencode-server.service`,
`server.env`; правка 01:28), сессии стали обслуживаться сервером **с паролем**; внутренние
API-вызовы плагина DCP аутентификацию не проходят → 401 → пустой список → compress ломается
**для всех** сессий (с 11.09 01:51 нет ни одного успешного compress; до — десятки успешных).
Внешний контекст: DCP issue #551 — та же ошибка при «error payload → пустой lookup»
(другие триггеры: auto-compaction, schema rejection).

## Фикс

Эксперимент (проверен владельцем вручную): отключить пароль у сервиса и перезапустить.

```bash
# закомментировать OPENCODE_SERVER_USERNAME/OPENCODE_SERVER_PASSWORD в ~/.config/opencode/server.env
systemctl --user daemon-reload && systemctl --user restart opencode-server
# после рестарта: reattach, затем вызвать compress с маленьким диапазоном из свежих тегов
```

Долгосрочные варианты (выбор владельца):

1. serve без пароля на `127.0.0.1` (мобильный доступ — через SSH/Tailscale);
2. serve без пароля на `0.0.0.0` (только доверенная сеть);
3. оставить пароль и патчить DCP (добавить Basic-auth в его client-вызовы) — сложнее, нужен разбор бандла.

## Полезное

- Полный JSON сообщений сессии: `curl -s -u "$OPENCODE_SERVER_USERNAME:$OPENCODE_SERVER_PASSWORD" http://localhost:8080/session/<id>/message`.
- БД opencode: `~/.local/share/opencode/opencode.db` (SQLite; python3, только чтение: `file:...?mode=ro`).
- Версии DCP: 3.1.15 — последняя (16.08.2026); boundary-логика в 3.1.14/3.1.15 идентична — проблема не в версии DCP,
  а в окружении (serve-auth).
- DCP поддерживает автообновление; version-locked spec (`@tarquinen/opencode-dcp@X.Y.Z`) его отключает.
- Проверка «compress жив»: вызвать с диапазоном из двух свежих видимых тегов; успех = механизм в порядке.
