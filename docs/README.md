# docs/ — индекс документации (traffic cop)

> _Freshness — owner: пользователь · reviewed: 2026-09-17 · verified-by: `./scripts/check_docs.sh` (PASSED)._

Карта документации проекта. **Горячий слой** читается всегда; **холодный**
(`archive/`, `reference/`) — адресно по якорю, только когда нужен конкретный факт
или тело (D-38).

| Документ | Назначение | Когда читать | Статус |
|----------|------------|--------------|--------|
| `../CONTEXT.md` | суть и статус проекта за 30 секунд | старт сессии | hot |
| `../STATE.md` | статус, открытые R-/B- полными телами, индексы всех номеров | перед каждым шагом | hot |
| `../ROADMAP.md` | план и критерии этапов | начало этапа | hot |
| `../AGENT.md` | конституция: принципы, правила приёмки, модельная стратегия | начало этапа / потеря контекста | hot |
| `BFT-v1.15.md` | бизнес-функциональные требования | при работе с требованиями | **hot** (актуальная версия) |
| `BFT-v1.14.md` | бизнес-функциональные требования (предыдущая версия) | сверка истории требований | cold |
| `BFT-v1.0.md` … `BFT-v1.13.md` | история требований | адресно | reference (read-only) |
| `MIGRATIONS.md` | процедура миграций БД (D-17) | при изменении схемы | reference |
| `REVIEW-2026-08-31.md` | внешний аудит (B-3…B-11, R-8…R-17) | адресно | reference |
| `dcp.md` | механика DCP/compress: refs, диагностика «not available», регресс serve-auth и фикс | при работе с compress / поломках контекст-менеджмента | reference |
| `archive/state-journal-phases-0-5.md` | хроника журнала фаз 0–5 | адресно | archive (read-only) |
| `archive/state-journal-phases-6.md` | хроника журнала фазы 6 (2026-09-02…2026-09-17) | адресно | archive (read-only) |
| `archive/state-journal-phases-7.md` | хроника журнала фазы 7 (пакет 7.0) | адресно | archive (read-only) |
| `archive/state-journal-fix-1.md` | хроника пакета FIX-1 (воспроизводимость + целостность данных) | адресно | archive (read-only) |
| `archive/state-closed-hypotheses.md` | тела завершённых гипотез H- | адресно по якорю | archive (read-only) |
| `archive/r18-chronicle.md` | хроника обрывов сессий R-18 (#12–#16) | адресно | archive (read-only) |
| `archive/state-closed-risks.md` | тела закрытых угроз R- | адресно по якорю | archive (read-only) |
| `archive/state-closed-bugs.md` | тела закрытых багов B- | адресно по якорю | archive (read-only) |
| `archive/constitution-history.md` | история конституции AGENT v1…v2.12 | адресно | archive (read-only) |
| `reference/decisions.md` | тела решений D- | адресно по якорю | reference (read-only) |
| `reference/facts.md` | тела фактов F- | адресно по якорю | reference (read-only) |
| `../README.md` | внешний обзор проекта | — | hot (external) |
| `../.opencode/agent/dharma.md` | конфиг основного агента | — | config |

Конвенция «read-only»: файлы `docs/archive/` и `docs/reference/` не редактируются —
правка истории оформляется новым номером (F-/D-/R-/B-) в горячем STATE, а не
переписыванием тела (I-2, I-7).

## Конвенция БФТ (файл-на-версию)

- **Актуальная версия — файл с наибольшим номером** (`BFT-v1.N.md`); сегодня это
  `BFT-v1.15.md`.
- Новая версия требований = новый файл; старые версии **не редактируются**
  (read-only история).
- Правка требований → новый файл + запись в §15 БФТ и в «Changelog плана» ROADMAP.

## Research-файлы

Файлы исследований (agent1/agent2/agent3) в репозитории **отсутствуют — вне репо**
(пакет `docs-arch-1`, блок 5). Если появятся — место `docs/research/` с
индекс-саммари и статусом.
