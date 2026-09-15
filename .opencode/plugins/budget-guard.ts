/**
 * budget-guard — жёсткая остановка сессии OpenCode при превышении бюджета.
 *
 * Зачем: агент изнутри сессии видит стоимость неточно (прецедент: отчёт заявил
 * ~$0.45 при фактических $0.71). Триггер остановки по лимиту обязан опираться на
 * объективный счётчик, а не на самооценку модели.
 *
 * Как работает:
 *   1. Слушает события `message.updated` и `session.updated`, накапливая стоимость
 *      по каждому сообщению/сессии (повторные апдейты одного сообщения не двоят счёт).
 *   2. Перед выполнением любого инструмента (`tool.execute.before`) сверяет
 *      накопленную стоимость с бюджетом и **бросает ошибку** при превышении —
 *      это блокирует вызов инструмента.
 *   3. Дополнительно (не чаще одного раза в `DB_CACHE_MS` на сессию) читает
 *      авторитетную стоимость прямо из SQLite OpenCode — страховка от пропущенных
 *      событий. Если `sqlite3` недоступен, тихо остаётся на счётчике событий.
 *
 * Конфигурация (переменные окружения):
 *   - `OPENCODE_BUDGET_USD` — бюджет сессии в долларах (default: 0.5).
 *   - `OPENCODE_BUDGET_LOG` — путь журнала срабатываний (default: /tmp/opencode-budget.log).
 *   - `OPENCODE_BUDGET_DB`  — путь к SQLite OpenCode (default: XDG data dir opencode.db).
 *   - `OPENCODE_BUDGET_DB_CHECK` — `0` отключает сверку с БД (default: включена).
 *
 * Публичный API (используется тестом `scripts/budget_guard_test.ts`):
 *   - `createBudgetState()` — чистое состояние счётчиков.
 *   - `trackMessage(state, sessionID, messageID, cost)` — учесть стоимость сообщения.
 *   - `trackSession(state, sessionID, cost)` — учесть авторитетную стоимость сессии.
 *   - `trackedCost(state, sessionID)` — текущая оценка стоимости сессии.
 *   - `resolveBudget(raw?)` — разбор бюджета (некорректное значение → default).
 *   - `isExceeded(cost, budget)` — предикат превышения (строго «больше или равно»).
 */
import type { Plugin, PluginInput } from "@opencode-ai/plugin"
import { appendFileSync } from "node:fs"

/** Бюджет сессии по умолчанию, USD. */
export const DEFAULT_BUDGET_USD = 0.5

/** Путь журнала срабатываний по умолчанию. */
export const DEFAULT_LOG_PATH = "/tmp/opencode-budget.log"

/** Минимальный интервал между сверками с БД (мс) — ограничивает стоимость проверки. */
export const DB_CACHE_MS = 5_000

/** Стоимость сообщения: последний известный апдейт (не сумма), поэтому берём максимум. */
export type BudgetState = {
  /** messageID → максимальная известная стоимость этого сообщения */
  messages: Map<string, number>
  /** sessionID → авторитетная стоимость сессии из `session.updated` */
  sessions: Map<string, number>
}

/** Создаёт пустое состояние счётчиков. */
export function createBudgetState(): BudgetState {
  return { messages: new Map(), sessions: new Map() }
}

/** Событийный ключ «сессия + сообщение» (в одном процессе живут разные сессии). */
function messageKey(sessionID: string, messageID: string): string {
  return `${sessionID}\u0000${messageID}`
}

/** Учитывает стоимость сообщения. Повторные апдейты того же сообщения не двоят счёт. */
export function trackMessage(
  state: BudgetState,
  sessionID: string,
  messageID: string,
  cost: number
): void {
  if (!Number.isFinite(cost) || cost < 0) return
  const key = messageKey(sessionID, messageID)
  const prev = state.messages.get(key) ?? 0
  if (cost > prev) state.messages.set(key, cost)
}

/** Учитывает авторитетную стоимость сессии (событие `session.updated`). */
export function trackSession(state: BudgetState, sessionID: string, cost: number): void {
  if (!Number.isFinite(cost) || cost < 0) return
  const prev = state.sessions.get(sessionID) ?? 0
  if (cost > prev) state.sessions.set(sessionID, cost)
}

/**
 * Оценка стоимости сессии: максимум из суммы по сообщениям и авторитетного
 * значения сессии. Источники дополняют друг друга, поэтому берём большее.
 */
export function trackedCost(state: BudgetState, sessionID: string): number {
  let sum = 0
  const prefix = `${sessionID}\u0000`
  for (const [key, cost] of state.messages) {
    if (key.startsWith(prefix)) sum += cost
  }
  const session = state.sessions.get(sessionID) ?? 0
  return Math.max(sum, session)
}

/** Разбирает бюджет: пустое/битое/отрицательное значение → default. Ноль допустим. */
export function resolveBudget(raw?: string): number {
  if (raw === undefined || raw.trim() === "") return DEFAULT_BUDGET_USD
  const parsed = Number(raw)
  if (!Number.isFinite(parsed) || parsed < 0) return DEFAULT_BUDGET_USD
  return parsed
}

/** Превышение бюджета: срабатывает и на точном равенстве. */
export function isExceeded(cost: number, budget: number): boolean {
  return cost >= budget
}

/** Путь к базе OpenCode (XDG-aware, переопределяется `OPENCODE_BUDGET_DB`). */
function databasePath(): string {
  const explicit = process.env.OPENCODE_BUDGET_DB
  if (explicit) return explicit
  const dataHome = process.env.XDG_DATA_HOME ?? `${process.env.HOME ?? ""}/.local/share`
  return `${dataHome}/opencode/opencode.db`
}

/** Идентификатор сессии безопасен для вставки в SQL (приходит от ядра OpenCode). */
function isSafeSessionID(id: string): boolean {
  return /^[A-Za-z0-9_-]+$/.test(id)
}

/**
 * Авторитетная стоимость сессии из SQLite OpenCode.
 * Возвращает `null`, если прочитать не удалось (нет sqlite3, нет БД, ошибка) —
 * вызывающий обязан продолжить на событийном счётчике, а не падать.
 */
async function readCostFromDatabase($: PluginInput["$"], sessionID: string): Promise<number | null> {
  if (process.env.OPENCODE_BUDGET_DB_CHECK === "0") return null
  if (!isSafeSessionID(sessionID)) return null
  try {
    const query = `SELECT cost FROM session WHERE id = '${sessionID}' LIMIT 1;`
    const output = await $`sqlite3 -cmd ".timeout 2000" ${databasePath()} ${query}`.text()
    const cost = Number.parseFloat(output.trim())
    return Number.isFinite(cost) ? cost : null
  } catch {
    return null
  }
}

/** Запись в журнал срабатываний. Никогда не роняет сессию из-за журнала. */
function log(message: string): void {
  const path = process.env.OPENCODE_BUDGET_LOG ?? DEFAULT_LOG_PATH
  try {
    appendFileSync(path, `${new Date().toISOString()} ${message}\n`)
  } catch {
    // fail-silent: журнал — вспомогательный артефакт, не условие остановки
  }
}

/**
 * Плагин OpenCode. Регистрируется автоматически из `.opencode/plugins/`.
 */
export const BudgetGuard: Plugin = async ({ $ }) => {
  const budget = resolveBudget(process.env.OPENCODE_BUDGET_USD)
  const state = createBudgetState()
  /** sessionID → время последней сверки с БД (мс) */
  const lastDbCheck = new Map<string, number>()
  const announced = new Set<string>()

  /** Стоимость сессии с учётом кэшированной сверки с БД. */
  async function sessionCost(sessionID: string): Promise<number> {
    let cost = trackedCost(state, sessionID)
    const now = Date.now()
    const last = lastDbCheck.get(sessionID) ?? 0
    if (now - last >= DB_CACHE_MS) {
      lastDbCheck.set(sessionID, now)
      const authoritative = await readCostFromDatabase($, sessionID)
      if (authoritative !== null && authoritative > cost) cost = authoritative
    }
    return cost
  }

  return {
    event: async ({ event }) => {
      if (event.type === "message.updated") {
        const info = (event.properties as { info?: { role?: string; sessionID?: string; id?: string; cost?: number } })
          ?.info
        if (info?.role === "assistant" && typeof info.cost === "number") {
          trackMessage(state, info.sessionID ?? "", info.id ?? "", info.cost)
        }
        return
      }
      if (event.type === "session.updated") {
        const info = (event.properties as { info?: { id?: string; cost?: number } })?.info
        if (typeof info?.cost === "number") trackSession(state, info.id ?? "", info.cost)
      }
    },

    "tool.execute.before": async (input) => {
      const cost = await sessionCost(input.sessionID)
      if (!isExceeded(cost, budget)) return
      if (!announced.has(input.sessionID)) {
        announced.add(input.sessionID)
        log(
          `BUDGET EXCEEDED session=${input.sessionID} cost=$${cost.toFixed(4)} budget=$${budget.toFixed(4)} tool=${input.tool}`
        )
      }
      throw new Error(
        `Session budget of $${budget.toFixed(4)} exceeded (session cost $${cost.toFixed(4)}). ` +
          `Stopping tool "${input.tool}". Report to the orchestrator and start a fresh session.`
      )
    },
  }
}
