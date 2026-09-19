-- Историческая схема БД версии 2 — DDL, эмитированный генератором drift, а не
-- написанный рукой (W27: рукописная фикстура расходилась с генератором).
--
-- Как снято (полная процедура — docs/MIGRATIONS.md, раздел «Историческая
-- фикстура v2»):
--   git archive f0b6c5e | tar -x -C <чистая папка>   # schemaVersion == 2
--   flutter pub get                                    #(lock той ревизии)
--   тест: AppDatabase.forTesting(NativeDatabase.memory()) → первый запрос
--         → SELECT type, name, sql FROM sqlite_master
--
-- f0b6c5e — коммит, добавивший practices и count_history; presets существовал
-- и раньше (e209bdf = версия 1). Строки ниже — дословный вывод генератора.
--
-- Исключено из дампа: `CREATE TABLE sqlite_sequence(name,seq)` — служебную
-- таблицу AUTOINCREMENT создаёт сам SQLite при появлении первой
-- AUTOINCREMENT-таблицы; воссоздавать её руками нельзя.
--
-- Единицы времени: drift хранит DateTime колонки как целое ЧИСЛО СЕКУНД
-- (mapToSql: millisecondsSinceEpoch ~/ 1000), и DEFAULT здесь же —
-- strftime('%s', ...). Не миллисекунды.
CREATE TABLE "presets" ("id" TEXT NOT NULL, "name" TEXT NOT NULL, "version" TEXT NOT NULL, "tradition" TEXT NOT NULL, "data" TEXT NOT NULL, PRIMARY KEY ("id"));
CREATE TABLE "practices" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "preset_id" TEXT NULL, "name" TEXT NOT NULL, "type" TEXT NOT NULL, "target" INTEGER NULL, "unit" TEXT NULL, "tradition_tag" TEXT NOT NULL, "current_count" INTEGER NOT NULL DEFAULT 0, "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)), "updated_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)));
CREATE TABLE "count_history" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "practice_id" INTEGER NOT NULL REFERENCES practices (id), "count" INTEGER NOT NULL, "timestamp" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)), "note" TEXT NULL);
