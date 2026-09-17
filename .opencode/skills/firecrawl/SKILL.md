---
name: firecrawl
description: Веб-ресерч через Firecrawl — поиск, скрейп, интеракция со страницей, парсинг документов, научный индекс, мониторинг, готовые артефакты. Используй, когда агенту нужны данные из веба в текущей сессии.
license: MIT
compatibility: opencode
metadata:
  audience: developer
  workflow: web-research
  source: https://github.com/firecrawl/cli
  source_doc: https://docs.firecrawl.dev/ai-onboarding
---

## Что я делаю

Firecrawl даёт агентам быстрый и надёжный доступ к веб-контексту: сильный
поиск, скрейп, интеракция с живыми страницами, парсинг локальных документов,
научный ресерч и мониторинг изменений. Навык нужен, чтобы выбрать путь под
задачу: получить данные **в текущей сессии**, написать **код интеграции**,
собрать **готовый артефакт** или **создать аккаунт/ключ**.

## Статус установки в этом окружении

- CLI установлен глобально: `firecrawl --version` → `1.23.3`
  (`npm install -g firecrawl-cli@latest`; бинарь `~/.npm-global/bin/firecrawl`).
- Аутентификация — в пользовательском конфиге Firecrawl (вне репозитория).
- Проверка перед работой:

```bash
firecrawl --status
# ожидаем: ● Authenticated via stored credentials + Concurrency + Credits
```

## Безопасность (обязательно)

- **API-ключ не хранится в репозитории.** Он лежит в пользовательском конфиге
  Firecrawl; в файлы проекта, отчёты и payload он не попадает.
- **Не использовать `firecrawl env` в каталоге проекта**: он пишет `.env`,
  который может уехать в git. Аутентификация — `firecrawl login -k <key>`
  (креды вне репо) или переменная окружения.
- Если `--status` показывает `Not authenticated` — сообщить владельцу, не
  выдумывать обход.

## Установка, обновление, диагностика

```bash
# полная установка: CLI + core-скиллы + workflow-скиллы + браузерная авторизация
npx -y firecrawl-cli@latest init --all --browser

# варианты init: --skip-auth, --skip-install, --skip-skills, --agent <name>, -k <key>
firecrawl init --help

# точечные интеграции
firecrawl setup <core|build|workflows|mcp|defaults>   # core = alias skills
#   -g/--global | --project (для mcp; ключи в проектные файлы не пишутся)
#   -a/--agent <name> | all     --keyless (анонимный hosted MCP)
#   -y/--yes                    --browser (логин, если ключа нет)
#   --undo (вернуть нативные веб-инструменты)

# проверка установки (как в источнике)
mkdir -p .firecrawl
firecrawl --status
firecrawl scrape "https://firecrawl.dev" -o .firecrawl/install-check.md

firecrawl doctor                # диагностика окружения
firecrawl doctor <job-id>       # разбор конкретной упавшей задачи
firecrawl credit-usage          # расход кредитов
firecrawl version               # версия
```

`init --all` устанавливает **core CLI-скиллы** (учат агента водить CLI: какую
команду запускать, когда scrape vs search vs interact, как чейнить результаты,
как восстанавливаться после сбоя) и **workflow-скиллы** (превращают веб-данные
в готовые артефакты: research brief, SEO-аудит, список лидов, QA-отчёт, база
знаний, клон дизайна).

---

# Пути использования

Выбор пути под задачу:

| Нужно | Путь |
|---|---|
| Веб-данные в текущей сессии | **A** (живые инструменты) |
| Добавить Firecrawl в код приложения | **B** (интеграция) |
| Готовый артефакт из веб-данных | **C** (workflow-скиллы) |
| Создать аккаунт / получить API-ключ | **D** (авторизация) |
| Ничего не устанавливать | **E** (REST API напрямую) |
| Нет ключа, и человек не может зарегистрироваться | **F** (keyless free tier) |

---

## Путь A: живые веб-инструменты

Когда данные нужны агенту прямо сейчас: поиск, скрейп известных URL,
интеракция с живыми страницами, обход документации, карта сайта, парсинг
локальных документов, научные статьи, мониторинг изменений.

После установки передаётся CLI-скиллу (имена для handoff):

| Скилл | Когда |
|---|---|
| `firecrawl` | общий workflow команд |
| `firecrawl-search` | нужен сначала поиск |
| `firecrawl-scrape` | URL уже известен |
| `firecrawl-interact` | странице нужны клики, формы, логин |
| `firecrawl-agent` | автономное извлечение нескольких страниц в структурный JSON |
| `firecrawl-crawl` | массовое извлечение |
| `firecrawl-map` | разведка URL сайта |
| `firecrawl-download` | сохранить сайт/раздел локально (эксперим. `firecrawl x download`) |
| `firecrawl-parse` | источник — **локальный файл** (PDF, DOCX, DOC, ODT, RTF, XLSX, XLS, HTML) |
| `firecrawl-monitor` | нужно **уведомление об изменении** (cron или «раз в 30 минут»), а не разовое чтение |
| `firecrawl-research-index` | научный/инженерный ресерч (`research search-papers`, `inspect-paper`, `read-paper`, `related-papers`, `search-github`) |
| `firecrawl-developer-index` | вопросы про сам Firecrawl (`firecrawl developer "<вопрос>"`) |

### Команды

| Задача | Команда |
|---|---|
| Поиск по вебу | `firecrawl search "запрос" --limit 5` |
| Поиск + контент страниц | `firecrawl search "запрос" --limit 5 --scrape` |
| Чтение одного URL | `firecrawl scrape "URL" -o out.md` |
| Обход сайта | `firecrawl crawl <url>` |
| Карта URL сайта | `firecrawl map <url>` |
| Локальный документ → markdown | `firecrawl parse ./file.pdf -o out.md` |
| Парсинг + AI-сводка / вопрос по документу | `firecrawl parse ./report.pdf -S` / `-Q "вопрос"` |
| Научный индекс | `firecrawl research search-papers "запрос"` |
| Документация/CLI/API Firecrawl | `firecrawl developer "вопрос"` |
| Извлечение структурных данных | `firecrawl agent "<промпт>"` |
| Мониторинг изменений | `firecrawl monitor create ...` |
| Разбор упавшей задачи | `firecrawl doctor <job-id>` |
| Фидбек по результату поиска (возврат 1 кредита) | `firecrawl search-feedback <searchId>` |

Публичные URL-документы (PDF и т.п.) идут через `firecrawl scrape`;
`parse` — только для **локальных/непубличных** файлов.

### Флаги `search`

- `--limit N` — число результатов (default 5, max 100).
- `--sources web,news,images` — источник выдачи (default `web`).
- `--categories github,research,pdf,developer` — фильтр категорий:
  `research` — сайты исследовательских организаций (**не** индекс статей
  `research search-papers`), `pdf` — PDF-документы, `developer` — GitHub
  issues/PR/README и документация.
- `--tbs qdr:h|d|w|m|y` — за час/день/неделю/месяц/год.
- `--country <ISO>` / `--location` — гео-таргетинг.
- `--highlights` / `--no-highlights` — выдержки вместо сниппетов.
- `--scrape` + `--scrape-formats markdown,html,links` — сразу тянуть контент.
- `-o/--output <path>`, `--json` — вывод в файл / компактный JSON.

### Порядок по умолчанию

1. **`search`** — когда нужна разведка.
2. **`scrape`** — когда URL уже известен.
3. **`interact`** — только если странице нужны клики/формы/логин.
4. **`parse`** — когда источник локальный файл, а не URL.
5. **`monitor`** — если запрос подразумевает повторение/уведомления
   («сообщи когда», «следи за страницей»), а не разовое чтение.
6. **`firecrawl doctor <job-id>`** — если задача упала или вернула неожиданное.
   Не гадать о причине.

Если задача превращается в «встроить Firecrawl в код продукта» — переходить на путь B.

---

## Путь B: интеграция Firecrawl в приложение

Установить build-скиллы: `firecrawl setup build`.

Когда интеграция будет **жить внутри продукта** (веб-приложение, backend,
скрипт, агентный цикл), а не в терминальной сессии агента: код берёт
`FIRECRAWL_API_KEY` из `.env` или runtime-конфига и использует SDK на языке
проекта.

- **Новый проект** — выбрать стек, поставить SDK, прописать env, прогнать smoke-test.
- **Существующий проект** — сперва изучить репо, встраивать туда, где уже
  работают API и секреты.

Ключ в окружение продукта:

```dotenv
FIRECRAWL_API_KEY=fc-...
```

Build-скиллы: `firecrawl-build`, `firecrawl-build-onboarding` (auth и setup
проекта), `firecrawl-build-scrape`, `firecrawl-build-search`,
`firecrawl-build-interact`.

Обязательный вопрос пути: **что Firecrawl должен делать в продукте?** Ответ
маршрутизирует на `/search`, `/scrape`, `/interact`, `/parse`, `/crawl`,
`/map`, `/monitor` или research-индекс — затем один реальный запрос как
smoke-test.

---

## Путь C: повторяемые артефакты

Когда цель — **готовый документ** на веб-данных Firecrawl: research brief,
SEO-аудит, QA-отчёт, список лидов, база знаний, competitive intel, клон
дизайн-системы — а не сырое извлечение и не код.

Начинать с зонтичного `firecrawl-workflows` (сам маршрутизирует на нужный
workflow) либо сразу на конкретный workflow-скилл. Полный список — в
[firecrawl-workflows](https://github.com/firecrawl/firecrawl-workflows).

Порядок:

1. подтвердить workflow и финальный артефакт;
2. собрать веб-доказательства через Firecrawl;
3. сохранить/процитировать источники, чтобы утверждения были трассируемы;
4. независимые исследовательские единицы запускать параллельно;
5. синтезировать в запрошенный артефакт;
6. добавить короткий блок «rerun inputs», если workflow можно автоматизировать.

Workflow-скиллы выводят контекст сами и задают короткие уточняющие вопросы
только если вход блокирует работу.

---

## Путь D: авторизация аккаунта / API-ключ

Дефолтный путь для coding-агентов и human-in-the-loop авторизации.

Два способа получить ключ:

- **Дашборд или CLI (по умолчанию)** — браузерный вход, `--browser`-авторизация,
  установка скиллов/MCP или создание ключа в дашборде.
- **WorkOS ID-JAG (только на поддерживающих платформах)** — если платформа умеет
  минтить identity assertion WorkOS ID-JAG, следовать
  `https://www.firecrawl.dev/auth.md` целиком; браузерный/CLI-флоу в этом случае
  не запускать.

Если `FIRECRAWL_API_KEY` уже есть — этот путь пропускается.

### Браузерный вход человеком

Регистрация/вход: https://www.firecrawl.dev/signin?view=signup&source=agent-suggested

### Авторизация ключа агентом (OAuth-подобный флоу)

**Шаг 1 — сгенерировать параметры:**

```bash
SESSION_ID=$(openssl rand -hex 32)
CODE_VERIFIER=$(openssl rand -base64 32 | tr '+/' '-_' | tr -d '=\n' | head -c 43)
CODE_CHALLENGE=$(printf '%s' "$CODE_VERIFIER" | openssl dgst -sha256 -binary | openssl base64 -A | tr '+/' '-_' | tr -d '=')
```

**Шаг 2 — попросить человека открыть URL:**

```
https://www.firecrawl.dev/cli-auth?code_challenge=$CODE_CHALLENGE&source=coding-agent#session_id=$SESSION_ID
```

Человек входит (или создаёт аккаунт) и нажимает «Authorize» — ключ возвращается
автоматически.

**Шаг 3 — опрос статуса (каждые 3 секунды):**

```bash
POST https://www.firecrawl.dev/api/auth/cli/status
Content-Type: application/json

{"session_id": "$SESSION_ID", "code_verifier": "$CODE_VERIFIER"}
```

Ответы: `{"status":"pending"}` — продолжать опрос;
`{"status":"complete","apiKey":"fc-...","teamName":"..."}` — готово.

**Шаг 4 — сохранить ключ.** В этом проекте — через `firecrawl login -k <key>`
(креды вне репозитория). `echo ... >> .env` **не** использовать в каталоге
проекта: `.env` здесь не в `.gitignore`.

---

## Путь E: Firecrawl без установки

Когда не хочется ставить CLI или пакет скиллов. Ключ всё равно нужен: либо
человек вставляет `FIRECRAWL_API_KEY=fc-...` в окружение, либо путь D
проводит человека через браузерную авторизацию.

- **Base URL:** `https://api.firecrawl.dev/v2`
- **Auth header:** `Authorization: Bearer fc-YOUR_API_KEY`

### Эндпоинты

| Эндпоинт | Назначение |
|---|---|
| `POST /search` | найти страницы по запросу, опционально с полным контентом |
| `POST /scrape` | чистый markdown из одного URL (включая публичные документы: PDF, DOCX) |
| `POST /interact` | отдельная браузерная сессия; для кликов/форм по уже скрейпленной странице — `POST /scrape/{scrapeId}/interact` с промптом или кодом |
| `POST /parse` | локальный/непубличный документ как `multipart/form-data` (PDF, DOCX, DOC, ODT, RTF, XLSX, XLS, HTML; до 50 МБ) → markdown, JSON, HTML, links, images, summary |
| `POST /monitor` | регулярная проверка страниц/краула/поисковой выдачи, diff со снапшотом, AI-судья по `goal`, уведомление webhook/email; `GET /monitor` — список, `GET /monitor/{id}/checks` — результаты |
| `GET /search/research/papers` | научный индекс по natural-language запросу |
| `GET /search/research/papers/{id}` | метаданные или (с `query`) топ full-text пассажей |
| `GET /search/research/papers/{id}/similar` | связанные статьи, цитирующие, ссылки |
| `GET /search/research/github` | GitHub issues, PR, README |
| `POST /support/ask` | диагноз упавшего вызова (передать `{question}`, лучше с job ID) → prose `answer` + `fixParameters` |
| `POST /support/docs-search` | ответы «как сделать…» по официальной документации Firecrawl с цитатами |

Документация — источник истины по схемам и параметрам:
https://docs.firecrawl.dev/api-reference/v2-introduction

---

## Путь F: keyless free tier (fallback)

Когда Firecrawl нужен прямо сейчас, а ключ получить нельзя. Search, scrape,
interact, parse и research-индекс доступны без ключа при запросе от
официального клиента Firecrawl (MCP, CLI или SDK); лимиты rate-limited, это
**fallback**, а не дефолт.

- **MCP:** указать MCP-клиент на `https://mcp.firecrawl.dev/v2/mcp`
- **CLI:** `npx -y firecrawl-cli@latest` — `scrape`, `search`, `interact`,
  `parse` без логина
- **API:** эндпоинты research-индекса (`/search/research/*`) вызываются без
  заголовка `Authorization`

Ключ не нужен только для search/scrape/interact/parse/research-индекса.
Crawl, map, monitor, extract, batch scrape, agent и прочие эндпоинты требуют
ключ.

⚠️ **В этом окружении** анонимный доступ блокируется на уровне IP
(`your IP address looks suspicious...`), поэтому здесь ключ обязателен даже
для «path F». Понадобился ключ — запросить у владельца (путь D).

---

## Если Firecrawl недоступен

Fallback: встроенные `webfetch` (известный URL) и `websearch` (поиск), либо
прямой `curl` к REST API. Использование fallback фиксировать в отчёте.
