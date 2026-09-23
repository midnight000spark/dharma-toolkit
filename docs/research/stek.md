# stek.md — целевой стек инструментов dharma-toolkit (без конфликтов)

> **Статус (2026-09-24): архив плана.** Вердикт принят владельцем: гигиена исполнена,
> **trace-mcp отложен** (D-47; факты по первоисточникам — F-72), experimental
> background subagents / touchkale не включать. Условия пересмотра — в D-47.
> Исследование (read-only), 2026-09-24. Конфиги и доки **не менялись**.
> Источники: `/home/midnight/projects/dharma-toolkit/opencode.json` (project),
> `/home/midnight/.config/opencode/opencode.jsonc`,
> `/home/midnight/.config/opencode/tui.json`,
> `/home/midnight/projects/dharma-toolkit/.opencode/*` (агенты, скиллы, plugins, hooks, dcp.jsonc),
> `/home/midnight/projects/dharma-toolkit/docs/dcp.md`,
> `/home/midnight/projects/dharma-toolkit/docs/README.md`,
> `/home/midnight/projects/dharma-toolkit/ROADMAP.md`,
> `/home/midnight/projects/dharma-toolkit/CONTEXT.md`,
> `/home/midnight/.tmp/research/trace-mcp-flutter.md`,
> `/home/midnight/.tmp/research/opencode-dashboards.md`,
> доки/исходники OpenCode v1 (task tool, agents),
> issues anomalyco/opencode (#29952, #28738, #31789, #14195, #28034).
> Статус: план на согласование; замена trace (A–D), touchkale и
> **`OPENCODE_EXPERIMENTAL_BACKGROUND_SUBAGENTS`** **не утверждены**.
> Окружение: OpenCode **v1.18.32** (остаёмся на v1).

## Суть

Собрать один связный стек, в котором модули **усиливают** друг друга и **не дублируют**
зоны ответственности: код/Dart, навигация по дереву, решения (jev), контекст (DCP),
бюджет, секреты, лимиты подписки. Канban MCP исключён; OpenCode остаётся **v1**.

---

## 1. Целевые слои

| Слой | Компонент | Роль | Статус |
|------|-----------|------|--------|
| MCP: код/Dart | `dart mcp-server` | analyze, LSP, pub, диагностика Dart/Flutter | Уже включён (project) |
| MCP: навигация | `trace-mcp` (nikolai-vysotskyi) | symbol search + outline по `.dart` — меньше лишних чтений файлов | **Добавить** (§3) |
| MCP: решения | `jev-mcp` | review / risk / requirement — advisory, метка `[ГИПОТЕЗА]` (D-46) | Project: enabled; global: disabled |
| Плагин: контекст | `@tarquinen/opencode-dcp` | `compress`, refs `mNNNN` / блоки `bN` | Работает (serve-auth баг закрыт) |
| Плагин: секреты | `opencode-vibeguard` | редакция секретов → плейсхолдеры `__VG_*` | Работает |
| Плагин: бюджет | `/home/midnight/projects/dharma-toolkit/.opencode/plugins/budget-guard.ts` | жёсткий стоп по `OPENCODE_BUDGET_USD` (default $0.50/сессия) | Работает |
| Хук: качество | `/home/midnight/projects/dharma-toolkit/.opencode/hooks/post-turn.sh` | `flutter analyze --fatal-infos 0 \|\| exit 1` каждый ход | Работает |
| TUI: лимиты | `oc-usage-limits-plugin` + `/home/midnight/.config/opencode/usage-limits.jsonc` | лимиты подписки sidebar/footer (OpenCode GO) | Работает, устраивает |
| TUI: расходы | `/home/midnight/.config/opencode/plugins/token-tracker.tsx` | расходы по сессиям | Работает, устраивает |
| Агенты | `/home/midnight/projects/dharma-toolkit/.opencode/agent/{dharma,dharma-routine,big-pickle-helper,research-scout}.md` | primary / рутинный код / конфиги / веб-ресерч | Работает |
| Скиллы | `/home/midnight/projects/dharma-toolkit/.opencode/skills/{jev-mcp,firecrawl,telegram-notify}/SKILL.md` | решения, веб, пуши D-27 (`✅/🛑/👀`) | Работает |
| Опц. аналитика | touchkale/opencode-dashboard (GitHub) | heatmap, burn rate, tokens/commit | Опционально; **не ставить по умолчанию** |

**Сознательно вне стека:** kanban MCP (исключён пользователем), OpenCode v2 (остаёмся на v1),
официальный `opencode web` как usage-дашборд (это чат-UI, не метрики).

---

## 2. Матрица дублей и конфликтов

| Пара | Тип | Вердикт |
|------|-----|---------|
| `@opencode-trace/plugin` (global) vs `trace-mcp` | **Замена** | Установленный плагин — HTTP-логгер AI-запросов (`/home/midnight/.opencode-trace/`, 150+ `ses_*`), **не** дерево кода. Не миссконфиг — другой продукт. Кандидат на удаление из global; замена — `trace-mcp` в project. |
| `dart mcp` vs `trace-mcp` (outline) | **Разделение зон** | Dart MCP = диагностика/analyze; trace-mcp = навигация. Не дублируются при таком разделении. |
| trace-mcp для Dart/Flutter | **Ограничение** | Только symbols/outline/search: **без** call/import/type edges; Flutter как framework **не поддерживается**; `.g.dart` / freezed / `.dart_tool/` — через `.traceignore` (будет `/home/midnight/projects/dharma-toolkit/.traceignore`). Call graph не заменяет. |
| `jev-mcp` global (disabled) vs project (enabled) | Двойная регистрация | Оставить **только project**; global disabled убрать при чистке. |
| usage-limits vs token-tracker | Дополнение | Лимиты подписки ≠ расходы — оставить оба. |
| TUI-metrics vs touchkale | Частичный дубль | Dashboard даёт heatmap/burn/commit сверх TUI — только при нужде в расширенной аналитике. |
| DCP vs budget-guard | Разные оси | Контекст-окно vs USD/сессию — комплементарны. |
| vibeguard vs DCP/budget | Нет пересечения | Секреты vs контекст vs деньги. |
| `post-turn` analyze vs `dart mcp` | Разные точки | Hook — после каждого хода; dart MCP — по запросу. |
| `post-turn` vs CI | Разные слои | Hook — fast-feedback; CI — авторитетный гейт (D-33). Оставить оба. |
| Foreground `task()` vs основная модель | **Ожидаемое поведение** | Дефолтный task **блокирует** родителя до возврата субагента — «замирание» не баг. Неблокирующий путь — experimental `background=true` (§6). |
| Parallel `task()` (одно сообщение) vs «не замирать» | Частичное | Несколько task в одном сообщении параллельны **между собой**; родитель всё равно ждёт **весь батч** — для него это по-прежнему ожидание. |

---

## 3. Убрать / оставить / добавить

### Убрать (только по явному «да» владельца)
1. `@opencode-trace/plugin` из **global** `/home/midnight/.config/opencode/opencode.jsonc` — не дерево кода, шум + диск в `/home/midnight/.opencode-trace/`.
2. Дублирующий `jev-mcp` (`enabled: false`) из global — оставить только `/home/midnight/projects/dharma-toolkit/opencode.json`.
3. Логи `/home/midnight/.opencode-trace/` **не чистить** без отдельного подтверждения (confirm_cleanup).

### Оставить как есть
- `dart mcp`, `jev-mcp` (project), DCP + `/home/midnight/projects/dharma-toolkit/.opencode/dcp.jsonc` (min 200k / max 290k),
  vibeguard + `/home/midnight/projects/dharma-toolkit/vibeguard.config.json`,
  `/home/midnight/projects/dharma-toolkit/.opencode/plugins/budget-guard.ts`,
  `/home/midnight/projects/dharma-toolkit/.opencode/hooks/post-turn.sh`,
  оба TUI-плагина (`/home/midnight/.config/opencode/usage-limits.jsonc`,
  `/home/midnight/.config/opencode/plugins/token-tracker.tsx`),
  все 4 агента в `/home/midnight/projects/dharma-toolkit/.opencode/agent/`,
  3 скилла в `/home/midnight/projects/dharma-toolkit/.opencode/skills/`,
  pin Flutter **3.47.5** / Dart **3.13.4** (D-… / `/home/midnight/projects/dharma-toolkit/AGENT.md` v2.18+).

### Добавить
1. **`trace-mcp`** в project `/home/midnight/projects/dharma-toolkit/opencode.json`:
   ```jsonc
   "trace": {
     "type": "local",
     "command": ["trace", "serve"],
     "enabled": true
   }
   ```
2. **`.traceignore`** — `/home/midnight/projects/dharma-toolkit/.traceignore`:
   ```
   .dart_tool/
   **/*.g.dart
   **/*.freezed.dart
   **/*.gr.dart
   build/
   ```
3. Опционально LSP Dart в `/home/midnight/projects/dharma-toolkit/.trace/.config.json` (`dart language-server --protocol=lsp`) — **не** даёт call graph для Dart; для MVP не обязателен.
4. Опционально **touchkale/opencode-dashboard** (GitHub) — только если нужны heatmap / burn rate / tokens/commit поверх TUI.
5. Опционально env **`OPENCODE_EXPERIMENTAL_BACKGROUND_SUBAGENTS=true`** — неблокирующие `task(background=true)` (§6); **не включать** без отдельного «да».

### Не делать
- Не ставить OpenCode v2.
- Не добавлять kanban MCP.
- Не включать глобальный `jev-mcp` параллельно с project (`/home/midnight/projects/dharma-toolkit/opencode.json`).
- Не рассчитывать на call graph / Flutter-интеллект от trace-mcp.
- Не выдумывать `/home/midnight/projects/dharma-toolkit/.codegraph` — каталога в дереве нет.
- Не включать experimental background-субагентов молча — только по решению владельца (§6).

---

## 4. Плюсы и минусы

| Выбор | Плюсы | Минусы / риски |
|-------|-------|----------------|
| dart MCP + trace-mcp | Диагностика ≠ навигация; меньше полных чтений | Для Dart — только symbols; нужен `/home/midnight/projects/dharma-toolkit/.traceignore` |
| jev только project | Одна точка включения | В другие репо — регистрация заново |
| DCP + budget-guard | Контекст и деньги разведены; уже проверены | Стоп по $0.50 может оборвать длинную сессию |
| vibeguard | Секреты не утекают в payload | `__VG_*` не принимать за данные (уже в `/home/midnight/projects/dharma-toolkit/.opencode/agent/research-scout.md`) |
| post-turn analyze | Медленнее каждый ход; `exit 1` прерывает | Принятая стратегия гейта |
| TUI-limits + token-tracker | Без браузера | Нет heatmap/history → при нужде touchkale |
| touchkale (опц.) | Один Python-файл, local-only, heatmap | WebUI (не фаворит), 2★ |
| Без kanban / без v2 | Меньше частей, стабильный v1 | Kanban вручную |
| Background subagents (опц.) | Основная модель не ждёт субагента | Experimental; interrupt/cleanup-риски; порядок analyze→commit ломается, если фон пишет те же файлы |

---

## 5. Целевая архитектура (одним блоком)

```
[Агенты]  dharma (primary) ─ dharma-routine / big-pickle-helper / research-scout
          /home/midnight/projects/dharma-toolkit/.opencode/agent/*.md
[Скиллы]  jev-mcp · firecrawl · telegram-notify (D-27)
          /home/midnight/projects/dharma-toolkit/.opencode/skills/*/SKILL.md
[MCP]     dart ── trace-mcp (symbols/outline) ── jev-mcp (advisory)
[Plugins] DCP (context) · vibeguard (secrets) · budget-guard (USD)
          /home/midnight/projects/dharma-toolkit/.opencode/plugins/budget-guard.ts
[Hooks]   post-turn → flutter analyze --fatal-infos
          /home/midnight/projects/dharma-toolkit/.opencode/hooks/post-turn.sh
[TUI]     oc-usage-limits · token-tracker
          /home/midnight/.config/opencode/usage-limits.jsonc
          /home/midnight/.config/opencode/plugins/token-tracker.tsx
[Exec]    foreground task (дефолт, блокирует) | background=true (experimental, опц.)
[Opt]     touchkale dashboard — только расширенная аналитика
[Убрать]  @opencode-trace/plugin (global) · дубль jev-mcp global
          /home/midnight/.config/opencode/opencode.jsonc
```

---

## 6. Субагенты: foreground vs background (почему основная «замирает»)

### Почему замирает (сейчас, без флагов)

| Режим | Поведение |
|-------|-----------|
| **Foreground** (дефолт `task()`) | Tool call **ждёт** завершения субагента → основная модель не получает следующий ход. Ожидаемый дизайн: «foreground — когда результат нужен до продолжения». |
| **Background** (`background=true`) | Возвращает `task_id` **сразу**; родитель работает дальше; по готовности — авто-уведомление (+ опционально `task_status`). |

«Замирание» — **не баг**, а foreground-дефолт. Параллельные `task()` в одном сообщении идут параллельно **между собой**, но родитель ждёт **весь батч**.

### Как включить неблокирующий режим (v1.18.32)

Фоновые субагенты есть с ~1.14.51, за experimental-флагом:

```bash
export OPENCODE_EXPERIMENTAL_BACKGROUND_SUBAGENTS=true
```

Без флага `background=true` падает:

> Background subagents require `OPENCODE_EXPERIMENTAL_BACKGROUND_SUBAGENTS=true`

```text
task(subagent_type="...", background=true, prompt="...")
→ task_id (сразу)
→ основная сессия продолжает
→ авто-нотификация по готовности
→ опц. task_status(task_id=...)
```

### Ограничения и риски

| Тема | Факт |
|------|------|
| Experimental | Не stable; в dharma **не включён**; включать только по «да» владельца. |
| Esc / interrupt родителя | Фоновый субагент **не отменяется** автоматически (#28738) — может жить дальше. |
| Ошибки LLM у foreground | Нет timeout/cancel у task → при падении провайдера родитель может зависнуть навсегда (#29952, closed not_planned). |
| Re-dispatch / attach | Баги на больших батчах с оркестратор-плагинами (#31789); на чистом task — аккуратнее. |
| Глубина | `subagent_depth` default **1** — субагент не плодит свои без конфига. |
| Parallel ≠ non-blocking | Батч foreground параллелен между субагентами, но родитель всё равно ждёт всех. |
| Навигация TUI | Child-сессии (`session_child_first`, Right/Left/Up) открываются, но родительская цепочка tool до возврата стоит. |
| budget-guard / post-turn | Живут на **родителе** (`/home/midnight/projects/dharma-toolkit/.opencode/plugins/budget-guard.ts`, `/home/midnight/projects/dharma-toolkit/.opencode/hooks/post-turn.sh`): пока тот ждёт task, новые tool/hook-шаги родителя не идут. |

### Когда что использовать (dharma)

| Сценарий | Режим |
|----------|--------|
| Research / ContextScout / параллельный ресерч без записи | Можно `background=true` (после включения флага) — основная не замирает |
| Пакет analyze → tests → commit (порядок критичен) | **Foreground** — иначе race с хуками/бюджетом и нарушение «персист → compress» |
| Много независимых субагентов | Foreground-batch (параллель между собой, ждёт батч) **или** все background + сбор уведомлений (experimental, осторожно) |
| bash в фоне (не LLM) | Отдельная фича (#28034) — **не** путать с background-субагентами |

**Итог:** основная модель **может** работать, пока субагенты в фоне — через `task(background=true)` + `OPENCODE_EXPERIMENTAL_BACKGROUND_SUBAGENTS=true`. Сейчас без флага — только foreground-ожидание. **Статус: не утверждено.**

---

## 7. Статус решений (не утверждены)

### Замена trace — варианты A–D
| Вариант | Действие |
|---------|----------|
| **A** (рекомендуется) | Снять global `@opencode-trace/plugin` из `/home/midnight/.config/opencode/opencode.jsonc`, добавить `trace-mcp` в `/home/midnight/projects/dharma-toolkit/opencode.json` + `/home/midnight/projects/dharma-toolkit/.traceignore` |
| **B** | Оставить HTTP-trace как осознанный логгер; trace-mcp не ставить |
| **C** | Временно оба, затем снять плагин |
| **D** | Ничего не трогать |

### touchkale dashboard
- Ставить / не ставить — решить отдельно; по умолчанию **не ставить**.

### Background subagents
- Включать / не включать `OPENCODE_EXPERIMENTAL_BACKGROUND_SUBAGENTS=true` — решить отдельно; по умолчанию **не включать** (experimental, риски §6).

---

## 8. Ссылки

### Research-файлы (не удалять)
- `/home/midnight/.tmp/research/trace-mcp-flutter.md` — Dart/Flutter в trace-mcp
- `/home/midnight/.tmp/research/opencode-dashboards.md` — shortlist dashboard'ов
- `/home/midnight/.tmp/research/trace-mcp-flutter.src/` (если есть сырьё рядом с research)

### Конфиги проекта (dharma-toolkit)
- `/home/midnight/projects/dharma-toolkit/opencode.json` — project MCP/plugins/agents
- `/home/midnight/projects/dharma-toolkit/.opencode/dcp.jsonc` — DCP compress limits
- `/home/midnight/projects/dharma-toolkit/vibeguard.config.json` — patterns секретов
- `/home/midnight/projects/dharma-toolkit/.opencode/plugins/budget-guard.ts` — стоп по бюджету
- `/home/midnight/projects/dharma-toolkit/.opencode/hooks/post-turn.sh` — analyze каждый ход
- `/home/midnight/projects/dharma-toolkit/.opencode/package.json` — `@opencode-ai/plugin` 1.18.11
- `/home/midnight/projects/dharma-toolkit/package.json` — `opencode-vibeguard`
- `/home/midnight/projects/dharma-toolkit/stek.md` — этот файл

### Конфиги OpenCode (global)
- `/home/midnight/.config/opencode/opencode.jsonc` — global plugins/MCP
- `/home/midnight/.config/opencode/tui.json` — TUI-плагины
- `/home/midnight/.config/opencode/usage-limits.jsonc` — лимиты OpenCode GO
- `/home/midnight/.config/opencode/plugins/token-tracker.tsx` — расходы в TUI
- `/home/midnight/.opencode-trace/` — логи HTTP-trace плагина (кандидат на чистку после решения)

### Агенты и скиллы
- `/home/midnight/projects/dharma-toolkit/.opencode/agent/dharma.md`
- `/home/midnight/projects/dharma-toolkit/.opencode/agent/dharma-routine.md`
- `/home/midnight/projects/dharma-toolkit/.opencode/agent/big-pickle-helper.md`
- `/home/midnight/projects/dharma-toolkit/.opencode/agent/research-scout.md`
- `/home/midnight/projects/dharma-toolkit/.opencode/skills/jev-mcp/SKILL.md`
- `/home/midnight/projects/dharma-toolkit/.opencode/skills/firecrawl/SKILL.md`
- `/home/midnight/projects/dharma-toolkit/.opencode/skills/telegram-notify/SKILL.md`

### Доки проекта
- `/home/midnight/projects/dharma-toolkit/docs/dcp.md` — compress, serve-auth
- `/home/midnight/projects/dharma-toolkit/docs/README.md` — hot/cold индекс
- `/home/midnight/projects/dharma-toolkit/docs/reference/decisions.md` — тела D-
- `/home/midnight/projects/dharma-toolkit/AGENT.md` — конституция
- `/home/midnight/projects/dharma-toolkit/STATE.md` — горячий статус
- `/home/midnight/projects/dharma-toolkit/CONTEXT.md` — суть за 30 сек
- `/home/midnight/projects/dharma-toolkit/ROADMAP.md` — план этапов

### Уроки / внешние источники
- Урок OpenCode 1.18: каждый экспорт файла-плагина — функция (`budget-guard.ts`).
- OpenCode docs Agents: https://opencode.ai/docs/agents
- Исходники task tool:
  - https://github.com/anomalyco/opencode/blob/dev/packages/opencode/src/tool/task.ts
  - https://github.com/anomalyco/opencode/blob/dev/packages/opencode/src/tool/task.txt
- Issues:
  - https://github.com/anomalyco/opencode/issues/29952 — foreground hang on LLM fail
  - https://github.com/anomalyco/opencode/issues/28738 — interrupt ≠ cancel фон
  - https://github.com/anomalyco/opencode/issues/31789 — re-dispatch
  - https://github.com/anomalyco/opencode/issues/14195 — parallel task
  - https://github.com/anomalyco/opencode/issues/28034 — bash background ≠ LLM background
