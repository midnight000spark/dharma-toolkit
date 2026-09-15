/**
 * budget_guard_test.ts — поведенческий тест стража бюджета (`.opencode/plugins/budget-guard.ts`).
 *
 * Запуск: `bun test scripts/budget_guard_test.ts` (bun ≥ 1.4).
 *
 * Тест поднимает НАСТОЯЩИЙ плагин (тот же файл, что грузит OpenCode) и дёргает его
 * хуки — проверяется наблюдаемое поведение, а не внутренности:
 *   - повторные апдейты одного сообщения не удваивают счёт (иначе бюджет
 *     «сгорает» на пустом месте);
 *   - `tool.execute.before` бросает ошибку на пороге и выше, но пропускает ниже;
 *   - стоимость одной сессии не блокирует другую;
 *   - отказ sqlite3 не ломает страж (деградация на событийный счётчик);
 *   - авторитетная стоимость из БД подхватывается, когда события её не донесли.
 *
 * Каждый тест обязан падать при поломке соответствующего поведения — проверено
 * мутациями (см. отчёт пакета infra-cost-guard).
 */
import { afterEach, beforeEach, describe, expect, test } from "bun:test"
import budgetGuardModule from "../.opencode/plugins/budget-guard.ts"

type BeforeHook = (input: { tool: string; sessionID: string; callID: string }) => Promise<void>
type EventHook = (input: { event: unknown }) => Promise<void>

/** Минимальный стенд: подменяем BunShell и спрашиваем хуки у настоящего плагина. */
async function standIn(options: { dbCost?: string; dbCheck?: boolean } = {}) {
  const previous = process.env.OPENCODE_BUDGET_DB_CHECK
  process.env.OPENCODE_BUDGET_DB_CHECK = options.dbCheck === false ? "0" : "1"
  const calls: string[] = []
  const shell = (() => ({
    text: async () => {
      calls.push("sqlite3")
      const value = options.dbCost
      if (value === undefined) throw new Error("sqlite3: command not found")
      return value
    },
  })) as unknown as Parameters<typeof budgetGuardModule.server>[0]["$"]

  const hooks = await budgetGuardModule.server({
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

/** Событие `session.updated` с авторитетной стоимостью сессии. */
function sessionUpdated(sessionID: string, cost: number) {
  return { type: "session.updated", properties: { info: { id: sessionID, cost } } }
}

const SESSION = "ses_test"
const otherSession = (sessionID: string) => ({ tool: "bash", sessionID, callID: "c" })

let envBackup: Record<string, string | undefined>

beforeEach(() => {
  envBackup = {
    OPENCODE_BUDGET_USD: process.env.OPENCODE_BUDGET_USD,
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

describe("счётчик стоимости (через события)", () => {
  test("повторный апдейт одного сообщения не удваивает стоимость", async () => {
    process.env.OPENCODE_BUDGET_USD = "0.5"
    const s = await standIn({ dbCheck: false })
    try {
      await s.event({ event: assistantMessage(SESSION, "msg_1", 0.3) })
      await s.event({ event: assistantMessage(SESSION, "msg_1", 0.4) }) // тот же id, выросла цена
      await s.event({ event: assistantMessage(SESSION, "msg_1", 0.4) }) // дубль апдейта
      // Суммирование без дедупликации дало бы 0.7 и заблокировало бы вызов.
      await expect(s.before(otherSession(SESSION))).resolves.toBeUndefined()
    } finally {
      s.restore()
    }
  })

  test("стоимости разных сообщений складываются", async () => {
    process.env.OPENCODE_BUDGET_USD = "0.5"
    const s = await standIn({ dbCheck: false })
    try {
      await s.event({ event: assistantMessage(SESSION, "msg_1", 0.3) })
      await s.event({ event: assistantMessage(SESSION, "msg_2", 0.3) })
      await expect(s.before(otherSession(SESSION))).rejects.toThrow(/budget/i)
    } finally {
      s.restore()
    }
  })

  test("стоимость одной сессии не блокирует другую", async () => {
    process.env.OPENCODE_BUDGET_USD = "0.5"
    const s = await standIn({ dbCheck: false })
    try {
      await s.event({ event: assistantMessage("ses_a", "msg_1", 0.9) })
      await expect(s.before(otherSession("ses_b"))).resolves.toBeUndefined()
      await expect(s.before(otherSession("ses_a"))).rejects.toThrow(/budget/i)
    } finally {
      s.restore()
    }
  })

  test("авторитетная стоимость сессии подхватывается, если события отстают", async () => {
    process.env.OPENCODE_BUDGET_USD = "0.4"
    const s = await standIn({ dbCheck: false })
    try {
      await s.event({ event: assistantMessage(SESSION, "msg_1", 0.1) })
      await s.event({ event: sessionUpdated(SESSION, 0.42) })
      await expect(s.before(otherSession(SESSION))).rejects.toThrow(/budget/i)
    } finally {
      s.restore()
    }
  })

  test("меньшее значение сессии не затирает сумму сообщений", async () => {
    process.env.OPENCODE_BUDGET_USD = "0.5"
    const s = await standIn({ dbCheck: false })
    try {
      await s.event({ event: assistantMessage(SESSION, "msg_1", 0.3) })
      await s.event({ event: assistantMessage(SESSION, "msg_2", 0.3) })
      await s.event({ event: sessionUpdated(SESSION, 0.1) })
      await expect(s.before(otherSession(SESSION))).rejects.toThrow(/budget/i)
    } finally {
      s.restore()
    }
  })

  test("мусорные значения игнорируются, а не отравляют счёт", async () => {
    process.env.OPENCODE_BUDGET_USD = "0.5"
    const s = await standIn({ dbCheck: false })
    try {
      await s.event({ event: assistantMessage(SESSION, "msg_1", Number.NaN) })
      await s.event({ event: assistantMessage(SESSION, "msg_2", -5) })
      await s.event({ event: sessionUpdated(SESSION, Number.POSITIVE_INFINITY) })
      // Мусор сам по себе не блокирует...
      await expect(s.before(otherSession(SESSION))).resolves.toBeUndefined()
      // ...и не ломает счёт: следующая валидная стоимость обязана сработать.
      // (Отравленный NaN'ом счёт не заблокировал бы и её.)
      await s.event({ event: assistantMessage(SESSION, "msg_ok", 0.6) })
      await expect(s.before(otherSession(SESSION))).rejects.toThrow(/budget/i)
    } finally {
      s.restore()
    }
  })
})

describe("порог и разбор бюджета", () => {
  test("по умолчанию бюджет $0.5: ниже — пропуск, на равенстве — блок", async () => {
    const s = await standIn({ dbCheck: false })
    try {
      await s.event({ event: assistantMessage(SESSION, "msg_1", 0.49) })
      await expect(s.before(otherSession(SESSION))).resolves.toBeUndefined()
      await s.event({ event: assistantMessage(SESSION, "msg_2", 0.01) }) // ровно 0.5
      await expect(s.before(otherSession(SESSION))).rejects.toThrow(/budget/i)
    } finally {
      s.restore()
    }
  })

  test("битое значение бюджета откатывается к умолчанию ($0.5)", async () => {
    process.env.OPENCODE_BUDGET_USD = "abc"
    const s = await standIn({ dbCheck: false })
    try {
      await s.event({ event: assistantMessage(SESSION, "msg_1", 0.49) })
      await expect(s.before(otherSession(SESSION))).resolves.toBeUndefined()
      await s.event({ event: assistantMessage(SESSION, "msg_2", 0.01) })
      await expect(s.before(otherSession(SESSION))).rejects.toThrow(/budget/i)
    } finally {
      s.restore()
    }
  })

  test("отрицательный бюджет откатывается к умолчанию, а не отключает страж", async () => {
    process.env.OPENCODE_BUDGET_USD = "-1"
    const s = await standIn({ dbCheck: false })
    try {
      await s.event({ event: assistantMessage(SESSION, "msg_1", 0.6) })
      await expect(s.before(otherSession(SESSION))).rejects.toThrow(/budget/i)
    } finally {
      s.restore()
    }
  })

  test("нулевой бюджет блокирует с первого же вызова", async () => {
    process.env.OPENCODE_BUDGET_USD = "0"
    const s = await standIn({ dbCheck: false })
    try {
      await expect(s.before(otherSession(SESSION))).rejects.toThrow(/budget/i)
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
})

describe("сверка с SQLite (fallback)", () => {
  test("стоимость из БД блокирует сессию, даже если события молчали", async () => {
    process.env.OPENCODE_BUDGET_USD = "0.5"
    const s = await standIn({ dbCost: "0.71" })
    try {
      await expect(s.before(otherSession(SESSION))).rejects.toThrow(/0\.71/)
      expect(s.sqliteCalls.length).toBeGreaterThan(0)
    } finally {
      s.restore()
    }
  })

  test("недоступная БД не ломает страж (деградация на события)", async () => {
    process.env.OPENCODE_BUDGET_USD = "0.5"
    const s = await standIn() // shell бросает — sqlite3 «не установлен»
    try {
      await s.event({ event: assistantMessage(SESSION, "msg_1", 0.1) })
      await expect(s.before(otherSession(SESSION))).resolves.toBeUndefined()
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
