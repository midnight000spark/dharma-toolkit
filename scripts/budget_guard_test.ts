/**
 * budget_guard_test.ts — детерминированный тест стража бюджета (`.opencode/plugins/budget-guard.ts`).
 *
 * Запуск: `bun test scripts/budget_guard_test.ts` (bun ≥ 1.4).
 *
 * Тест намеренно проверяет ПОВЕДЕНИЕ, а не факт загрузки модуля:
 *   - повторные апдейты одного сообщения не удваивают счёт (иначе бюджет
 *     «сгорает» на пустом месте);
 *   - `tool.execute.before` бросает ошибку на пороге и выше, но пропускает ниже;
 *   - стоимость одной сессии не блокирует другую;
 *   - отказ sqlite3 не ломает страж (деградация на событийный счётчик);
 *   - авторитетная стоимость из БД подхватывается, когда события её не донесли.
 *
 * Каждый тест обязан падать при поломке соответствующего поведения —
 * проверено мутациями (см. отчёт пакета infra-cost-guard).
 */
import { afterEach, beforeEach, describe, expect, test } from "bun:test"
import {
  BudgetGuard,
  DEFAULT_BUDGET_USD,
  createBudgetState,
  isExceeded,
  resolveBudget,
  trackMessage,
  trackSession,
  trackedCost,
} from "../.opencode/plugins/budget-guard.ts"

type BeforeHook = (input: { tool: string; sessionID: string; callID: string }) => Promise<void>
type EventHook = (input: { event: unknown }) => Promise<void>

/** Минимальный стенд: подменяем BunShell и спрашиваем хуки у настоящего плагина. */
async function standIn(options: { dbCost?: string | (() => string); dbCheck?: boolean } = {}) {
  const previous = process.env.OPENCODE_BUDGET_DB_CHECK
  process.env.OPENCODE_BUDGET_DB_CHECK = options.dbCheck === false ? "0" : "1"
  const calls: string[] = []
  const shell = (() => ({
    text: async () => {
      calls.push("sqlite3")
      const value = options.dbCost
      if (value === undefined) throw new Error("sqlite3: command not found")
      return typeof value === "function" ? value() : value
    },
  })) as unknown as Parameters<typeof BudgetGuard>[0]["$"]

  const hooks = await BudgetGuard({
    client: {},
    project: {},
    directory: process.cwd(),
    worktree: process.cwd(),
    experimental_workspace: { register: () => {} },
    serverUrl: new URL("http://localhost"),
    $: shell,
  })

  const restore = () => {
    if (previous === undefined) delete process.env.OPENCODE_BUDGET_DB_CHECK
    else process.env.OPENCODE_BUDGET_DB_CHECK = previous
  }

  return {
    before: hooks["tool.execute.before"] as unknown as BeforeHook,
    event: hooks.event as unknown as EventHook,
    sqliteCalls: calls,
    restore,
  }
}

/** Событие `message.updated` в форме, которую отдаёт ядро OpenCode 1.18.x. */
function assistantMessage(sessionID: string, id: string, cost: number) {
  return { type: "message.updated", properties: { info: { role: "assistant", sessionID, id, cost } } }
}

const SESSION = "ses_test"

let envBackup: Record<string, string | undefined>

beforeEach(() => {
  envBackup = {
    OPENCODE_BUDGET_USD: process.env.OPENCODE_BUDGET_USD,
    OPENCODE_BUDGET_DB: process.env.OPENCODE_BUDGET_DB,
    OPENCODE_BUDGET_LOG: process.env.OPENCODE_BUDGET_LOG,
    OPENCODE_BUDGET_DB_CHECK: process.env.OPENCODE_BUDGET_DB_CHECK,
  }
  process.env.OPENCODE_BUDGET_LOG = "/tmp/opencode-budget-test.log"
  delete process.env.OPENCODE_BUDGET_USD
})

afterEach(() => {
  for (const [key, value] of Object.entries(envBackup)) {
    if (value === undefined) delete process.env[key]
    else process.env[key] = value
  }
})

describe("счётчик", () => {
  test("повторный апдейт одного сообщения не удваивает стоимость", () => {
    const state = createBudgetState()
    trackMessage(state, SESSION, "msg_1", 0.1)
    trackMessage(state, SESSION, "msg_1", 0.15) // тот же id, стоимость выросла
    trackMessage(state, SESSION, "msg_1", 0.15) // дубль того же апдейта
    expect(trackedCost(state, SESSION)).toBeCloseTo(0.15, 10)
  })

  test("стоимости разных сообщений складываются", () => {
    const state = createBudgetState()
    trackMessage(state, SESSION, "msg_1", 0.2)
    trackMessage(state, SESSION, "msg_2", 0.25)
    expect(trackedCost(state, SESSION)).toBeCloseTo(0.45, 10)
  })

  test("стоимости разных сессий не смешиваются", () => {
    const state = createBudgetState()
    trackMessage(state, SESSION, "msg_1", 0.4)
    trackMessage(state, "ses_other", "msg_2", 0.05)
    expect(trackedCost(state, SESSION)).toBeCloseTo(0.4, 10)
    expect(trackedCost(state, "ses_other")).toBeCloseTo(0.05, 10)
  })

  test("авторитетная стоимость сессии подхватывается, если события отстают", () => {
    const state = createBudgetState()
    trackMessage(state, SESSION, "msg_1", 0.1)
    trackSession(state, SESSION, 0.42)
    expect(trackedCost(state, SESSION)).toBeCloseTo(0.42, 10)
  })

  test("сумма сообщений не затирается меньшим значением сессии", () => {
    const state = createBudgetState()
    trackMessage(state, SESSION, "msg_1", 0.3)
    trackMessage(state, SESSION, "msg_2", 0.3)
    trackSession(state, SESSION, 0.1)
    expect(trackedCost(state, SESSION)).toBeCloseTo(0.6, 10)
  })

  test("мусорные значения игнорируются, а не отравляют счёт", () => {
    const state = createBudgetState()
    trackMessage(state, SESSION, "msg_1", Number.NaN)
    trackMessage(state, SESSION, "msg_2", -5)
    trackSession(state, SESSION, Number.POSITIVE_INFINITY)
    expect(trackedCost(state, SESSION)).toBe(0)
  })
})

describe("разбор бюджета", () => {
  test("по умолчанию — $0.5", () => {
    expect(resolveBudget(undefined)).toBe(DEFAULT_BUDGET_USD)
    expect(DEFAULT_BUDGET_USD).toBe(0.5)
  })

  test("число принимается, включая ноль", () => {
    expect(resolveBudget("0.1")).toBe(0.1)
    expect(resolveBudget("0")).toBe(0)
  })

  test("битое и отрицательное значение откатывается к умолчанию", () => {
    expect(resolveBudget("abc")).toBe(DEFAULT_BUDGET_USD)
    expect(resolveBudget("")).toBe(DEFAULT_BUDGET_USD)
    expect(resolveBudget("-1")).toBe(DEFAULT_BUDGET_USD)
  })

  test("порог срабатывает на равенстве", () => {
    expect(isExceeded(0.5, 0.5)).toBe(true)
    expect(isExceeded(0.5000001, 0.5)).toBe(true)
    expect(isExceeded(0.4999, 0.5)).toBe(false)
  })
})

describe("хук tool.execute.before (настоящий плагин)", () => {
  test("ниже бюджета инструмент не блокируется", async () => {
    process.env.OPENCODE_BUDGET_USD = "0.5"
    const s = await standIn({ dbCheck: false })
    try {
      await s.event({ event: assistantMessage(SESSION, "msg_1", 0.2) })
      await expect(s.before({ tool: "bash", sessionID: SESSION, callID: "c1" })).resolves.toBeUndefined()
    } finally {
      s.restore()
    }
  })

  test("на пороге инструмент блокируется", async () => {
    process.env.OPENCODE_BUDGET_USD = "0.5"
    const s = await standIn({ dbCheck: false })
    try {
      await s.event({ event: assistantMessage(SESSION, "msg_1", 0.5) })
      await expect(s.before({ tool: "bash", sessionID: SESSION, callID: "c1" })).rejects.toThrow(
        /budget/i
      )
    } finally {
      s.restore()
    }
  })

  test("после превышения блокируется каждая следующая попытка", async () => {
    process.env.OPENCODE_BUDGET_USD = "0.5"
    const s = await standIn({ dbCheck: false })
    try {
      await s.event({ event: assistantMessage(SESSION, "msg_1", 0.6) })
      await expect(s.before({ tool: "bash", sessionID: SESSION, callID: "c1" })).rejects.toThrow()
      await expect(s.before({ tool: "read", sessionID: SESSION, callID: "c2" })).rejects.toThrow()
    } finally {
      s.restore()
    }
  })

  test("чужая сессия не блокируется стоимостью соседней", async () => {
    process.env.OPENCODE_BUDGET_USD = "0.5"
    const s = await standIn({ dbCheck: false })
    try {
      await s.event({ event: assistantMessage(SESSION, "msg_1", 0.9) })
      await expect(
        s.before({ tool: "bash", sessionID: "ses_other", callID: "c1" })
      ).resolves.toBeUndefined()
    } finally {
      s.restore()
    }
  })

  test("стоимость из БД блокирует сессию, даже если события молчали", async () => {
    process.env.OPENCODE_BUDGET_USD = "0.5"
    const s = await standIn({ dbCost: "0.71" })
    try {
      await expect(s.before({ tool: "bash", sessionID: SESSION, callID: "c1" })).rejects.toThrow(
        /0\.71/
      )
      expect(s.sqliteCalls.length).toBeGreaterThan(0)
    } finally {
      s.restore()
    }
  })

  test("недоступная БД не ломает страж (деградация на события)", async () => {
    process.env.OPENCODE_BUDGET_USD = "0.5"
    const s = await standIn() // dbCost === undefined → shell бросает
    try {
      await s.event({ event: assistantMessage(SESSION, "msg_1", 0.1) })
      await expect(s.before({ tool: "bash", sessionID: SESSION, callID: "c1" })).resolves.toBeUndefined()
    } finally {
      s.restore()
    }
  })

  test("сверка с БД кэшируется и не спавнит sqlite3 на каждый вызов", async () => {
    process.env.OPENCODE_BUDGET_USD = "0.5"
    const s = await standIn({ dbCost: "0.01" })
    try {
      await s.before({ tool: "bash", sessionID: SESSION, callID: "c1" })
      await s.before({ tool: "bash", sessionID: SESSION, callID: "c2" })
      await s.before({ tool: "bash", sessionID: SESSION, callID: "c3" })
      expect(s.sqliteCalls.length).toBe(1)
    } finally {
      s.restore()
    }
  })
})
