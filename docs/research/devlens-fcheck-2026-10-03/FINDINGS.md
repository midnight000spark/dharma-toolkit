# DevLens 1.2.0 / fcheck 1.5.0 — дистиллят полезного (2026-10-03)

> _Статус: research (read-only) · снимок внешнего анализа 2026-10-03 · перенесён
> в репозиторий 2026-10-03 из `.tmp` (`.tmp` вне git и сохранность не гарантирует)._
> _Источник (вне репо, домашний каталог): файл `devlens-fcheck-analysis-2026-10-03.md`;
> дистиллят `.tmp/devlens-fcheck-findings-2026-10-03.md`
> (`sha256 508d179d0caad32f64de5dcb2542c93bd3a18e097aba9862a3aae4e121f188b1`)._
> _Снимок: песочницы 17:43, HEAD **`13d4d59`** (текущий HEAD на момент дистиллята — `93be15d`)._
> _Инструменты запускались только на копиях в `/tmp`; на реальном дереве — ничего._

## 1. Вердикт в одну строку
Оба оценки — **не метрика качества**: `Architecture Score 95/100` и
`Compliance 64%` отражают несовпадение набора анализаторов с Flutter/Riverpod.
Полезны отдельные находки, а не проценты.

## 2. Что подтвердилось как реальное

| # | Находка | Проверка | Статус |
|---|---|---|---|
| 1 | Дублирование `_parseDateRule` (28 строк) и `_intInRange` (12) между `content/data/content_pack_parser.dart` и `events/data/event_pack_parser.dart` | `diff` вручную: расходятся только имена типов | **реально**, осознанное (D-35); кандидат на общий парсер |
| 2 | `folderCycle` × 4 (`core/db`, `features/events/data`, `features/tracker/data`, `features/tracker/domain`) | разложено по коду (см. §3) | **реально, но объяснимо**; 1 из 4 — кандидат |
| 3 | `wrongFolderLayer`: `core/recovery/recovery_screen.dart` → `shared/l10n`, `shared/utils` | `rg` импортов подтверждает | **реально**: `core → shared` (лёгкая инверсия слоёв) |
| 4 | `gittoken.md` в рабочем каталоге (148 Б, `.gitignore:55`, в индексе нет) | `git check-ignore` + `git ls-files` | **гигиена секретов**, решение владельца |

## 3. Разложение folderCycle (DevLens 0 файловых циклов ≠ fcheck 4 папковых)
- `core/db ↔ features/*/data` — **принятое ослабление D-20** (`app_database.dart`
  агрегирует таблицы фич). Не дефект.
- `core/db ↔ features/tracker/domain` — причина: `tracker/domain/practice.dart:46`
  `factory PracticeEntity.fromRow(Practice row)` тянет Drift-строку из `core/db`.
  **Домен знает слой БД** — тот же класс запаха, что `domain→data` (T1-сторож его
  не ловит, т.к. это `core/db`, а не feature-`data`). Кандидат.
- `core/db/dev_seeder.dart → core/config` — внутри ядра, шум.

## 4. Ложные срабатывания (не переоткрывать)
- `'nyingma'`/`'theravada_default'` в `calendar_providers.dart:63-64` — это
  **реестр D-32** (единственное место связи тега и календаря), защищён сторожем
  `calendar_registry_manifest_guard_test.dart`. Хардкод школы в ядре/навигации — нет.
- `README.md: missingReadme` — артефакт песочницы: `cp` в §9 отчёта README не копирует.
- 344 magic numbers — отступы Material (`16`, `24.0`, `12`, `8`).
- 33 unusedVariable — параметры замыканий (`context`, `ref`, `error`) — Dart не считает ошибкой.
- 21 one_class_per_file — внутренние `State`-классы Flutter (норма).
- `content/**` в dead_code — не подключён UI чтения дня (Q3/SCR-13), код рабочий.
- `main.dart` «god class» 25 импортов — это composition root, так и должно быть.

## 5. Риски инструментов (для памяти)
- `fcheck --fix` **переписывает `.dart` на месте** (сортировка членов/импортов,
  относительные → `package:`). На реальном дереве не запускать.
- DevLens «Offline HTML Dashboard» — неправда: тянет `unpkg.com`/`fonts.googleapis.com`.
- fcheck 1.5.0: `fcheck.mmd`/`fcheck.puml` пустые (работают только SVG).
- Оба: секрет-скан fcheck холостой (файл не был в песочнице).

## 6. Что делать / не делать
**Делать (кандидаты, owner-gated):**
1. `tracker/domain → core/db` — вынести `fromRow` в data-репозиторий? (домен чистый, folder-цикл уходит).
2. `core/recovery → shared` — ревизия слоя (либо обосновать, либо вынести общее).
3. Дублирование парсеров — общий generic-парсер (объём и риск оценить).
4. `gittoken.md` — убедиться, что файл не коммитится и не содержит живого токена.
5. Записать внешний анализ как проверяемый артефакт (reference) + STATE [ФАКТ].

**Не делать:** гнаться за fcheck-score/`--strict`, «чинить» magic numbers,
убирать `main.dart`-импорты, трогать `fcheck --fix`.

## 7. Воспроизведение
См. §9 исходного отчёта. Удаление: `rm -rf /tmp/devlens-cache /tmp/devlens-run
/tmp/fcheck-run /tmp/opencode/fcheck_full.json`.
