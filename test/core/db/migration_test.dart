import 'dart:io';

import 'package:dharma_toolkit/core/db/app_database.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// База, зафиксированная на схеме версии 1 — только таблица `presets`.
///
/// Нужна, чтобы создать файл БД ровно в том виде, в котором он существовал
/// до Этапа 4, и проверить настоящий переход 1 → 2, а не его имитацию.
class _AppDatabaseV1 extends AppDatabase {
  // Форму с super.executor подсказка use_super_parameters не принимает:
  // super-параметр дженерика сопоставляется только с безымянным супер-конструктором.
  // ignore: use_super_parameters
  _AppDatabaseV1(QueryExecutor executor) : super.forTesting(executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createTable(presets);
        },
      );
}

/// База, объявляющая версию схемы 4, для которой миграции не написано.
///
/// Регрессия на R-8: прежняя реализация в такой ситуации молча ничего
/// не делала, и ошибка всплывала у пользователя как «no such table».
/// Теперь она обязана упасть на первом же открытии базы.
class _AppDatabaseV4 extends AppDatabase {
  // ignore: use_super_parameters — см. комментарий у _AppDatabaseV1
  _AppDatabaseV4(QueryExecutor executor) : super.forTesting(executor);

  @override
  int get schemaVersion => 4;
}

/// База «старого приложения» — версия схемы на 1 ниже текущей.
///
/// Миграционную стратегию **наследует** от [AppDatabase] (в отличие от
/// `_AppDatabaseV1`/`_AppDatabaseV2Raw`, которые переопределяют её целиком):
/// нужен именно downgrade-проверочный путь `onUpgrade` актуального кода —
/// переход 3 → 2 обязан упасть на ветке `from > to` (B-12, хвост R-8).
/// Значение 2 согласовано с тестом ниже: тест проверяет, что это ровно
/// `schemaVersion - 1`, и краснеет, если версия схемы уедет без обновления
/// препосылки.
class _AppDatabaseDowngrade extends AppDatabase {
  // ignore: use_super_parameters — см. комментарий у _AppDatabaseV1
  _AppDatabaseDowngrade(QueryExecutor executor) : super.forTesting(executor);

  @override
  int get schemaVersion => 2;
}

/// База версии 2 со СТАРОЙ схемой практик и истории, воссозданной сырым SQL.
///
/// Использовать актуальные классы Drift-таблиц здесь нельзя: они генерируют
/// уже v3-DDL (с колонкой preset_practice_id и каскадом). Сырой DDL фиксирует
/// именно то состояние, в котором живут пользовательские базы до 5.0.2.
class _AppDatabaseV2Raw extends AppDatabase {
  // ignore: use_super_parameters — см. комментарий у _AppDatabaseV1
  _AppDatabaseV2Raw(QueryExecutor executor) : super.forTesting(executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await customStatement('''
            CREATE TABLE "presets" (
              "id" TEXT NOT NULL PRIMARY KEY,
              "name" TEXT NOT NULL,
              "version" TEXT NOT NULL,
              "tradition" TEXT NOT NULL,
              "data" TEXT NOT NULL
            )
          ''');
          // Старые practices: без preset_practice_id и без индекса.
          await customStatement('''
            CREATE TABLE "practices" (
              "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
              "preset_id" TEXT,
              "name" TEXT NOT NULL,
              "type" TEXT NOT NULL,
              "target" INTEGER,
              "unit" TEXT,
              "tradition_tag" TEXT NOT NULL,
              "current_count" INTEGER NOT NULL DEFAULT 0,
              "created_at" INTEGER NOT NULL DEFAULT 1725000000,
              "updated_at" INTEGER NOT NULL DEFAULT 1725000000
            )
          ''');
          // Старая count_history: RESTRICT вместо CASCADE (дефект B-11).
          await customStatement('''
            CREATE TABLE "count_history" (
              "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
              "practice_id" INTEGER NOT NULL
                REFERENCES "practices" ("id") ON DELETE RESTRICT,
              "count" INTEGER NOT NULL,
              "timestamp" INTEGER NOT NULL DEFAULT 1725000000,
              "note" TEXT
            )
          ''');
        },
      );
}

Future<Set<String>> _tableNames(GeneratedDatabase db) async {
  final rows = await db
      .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
      .get();
  return rows.map((row) => row.read<String>('name')).toSet();
}

Future<int> _userVersion(GeneratedDatabase db) async {
  final row = await db.customSelect('PRAGMA user_version').getSingle();
  return row.read<int>('user_version');
}

Future<Set<String>> _columnNames(GeneratedDatabase db, String table) async {
  final rows = await db.customSelect("PRAGMA table_info('$table')").get();
  return rows.map((row) => row.read<String>('name')).toSet();
}

Future<int> _columnCount(GeneratedDatabase db, String table) async {
  final row = await db
      .customSelect('SELECT COUNT(*) AS c FROM "$table"')
      .getSingle();
  return row.read<int>('c');
}

void main() {
  group('Миграции БД', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('dharma_migration_');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    File dbFile() => File('${tempDir.path}/app.sqlite');

    test('свежая установка создаёт схему текущей версии', () async {
      final db = AppDatabase.forTesting(NativeDatabase(dbFile()));

      expect(
        await _tableNames(db),
        containsAll(<String>['presets', 'practices', 'count_history']),
      );
      expect(await _userVersion(db), db.schemaVersion);

      // Индекс B-3 на свежей установке получается из объявления таблицы.
      final indexes = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'index' "
        "AND name = 'idx_practices_tradition_preset'",
      ).get();
      expect(indexes, hasLength(1));

      await db.close();
    });

    test('апгрейд 1 → 2 создаёт таблицы трекера и сохраняет данные', () async {
      // Сессия 1: база версии 1 — существует только presets.
      {
        final v1 = _AppDatabaseV1(NativeDatabase(dbFile()));

        await v1.into(v1.presets).insert(
              PresetsCompanion.insert(
                id: 'nyingma',
                name: 'Ньингма',
                version: '1.0.0',
                tradition: 'vajrayana',
                data: '{"id":"nyingma"}',
              ),
            );

        expect(await _userVersion(v1), 1);
        expect(await _tableNames(v1), isNot(contains('practices')));

        await v1.close();
      }

      // Сессия 2: открываем актуальной версией — срабатывает onUpgrade.
      {
        final db = AppDatabase.forTesting(NativeDatabase(dbFile()));

        expect(
          await _tableNames(db),
          containsAll(<String>['presets', 'practices', 'count_history']),
        );
        // Цепочка 1→2→3: цепляется до актуальной версии.
        expect(await _userVersion(db), db.schemaVersion);

        // Суть R-7: данные пользователя переживают миграцию.
        final rows = await db.select(db.presets).get();
        expect(rows, hasLength(1));
        expect(rows.first.id, 'nyingma');
        expect(rows.first.tradition, 'vajrayana');

        await db.close();
      }
    });

    test('после апгрейда трекеры работают на мигрированной базе', () async {
      // База версии 1.
      {
        final v1 = _AppDatabaseV1(NativeDatabase(dbFile()));
        await _tableNames(v1);
        await v1.close();
      }

      // Мигрируем и сразу пишем в новые таблицы: проверяем, что схема
      // создана целиком, а не только по названиям таблиц.
      {
        final db = AppDatabase.forTesting(NativeDatabase(dbFile()));

        final id = await db.into(db.practices).insert(
              PracticesCompanion.insert(
                name: 'Простирания',
                type: 'counter',
                traditionTag: 'nyingma',
                target: const Value(100000),
              ),
            );
        await db.into(db.countHistory).insert(
              CountHistoryCompanion.insert(practiceId: id, count: 7),
            );

        final practices = await db.select(db.practices).get();
        expect(practices, hasLength(1));
        expect(practices.first.target, 100000);
        expect(practices.first.currentCount, 0);

        final history = await db.select(db.countHistory).get();
        expect(history, hasLength(1));
        expect(history.first.count, 7);

        await db.close();
      }
    });

    test('колонки practices соответствуют объявленным', () async {
      final db = AppDatabase.forTesting(NativeDatabase(dbFile()));

      expect(
        await _columnNames(db, 'practices'),
        containsAll(<String>[
          'id',
          'preset_id',
          'preset_practice_id',
          'name',
          'type',
          'target',
          'unit',
          'tradition_tag',
          'current_count',
          'created_at',
          'updated_at',
        ]),
      );

      await db.close();
    });

    test('апгрейд 2 → 3: колонка, индекс и каскад истории при сохранности данных',
        () async {
      // Сессия 1: база версии 2 со СТАРЫМ DDL и пользовательскими данными.
      {
        final v2 = _AppDatabaseV2Raw(NativeDatabase(dbFile()));

        await v2.customStatement(
          "INSERT INTO presets VALUES "
          "('nyingma', 'Ньингма', '1.0.0', 'vajrayana', '{}')",
        );
        await v2.customStatement(
          "INSERT INTO practices (id, name, type, target, unit, "
          "tradition_tag, current_count) VALUES "
          "(1, 'Простирания', 'counter', 100000, 'повторений', 'nyingma', 42)",
        );
        await v2.customStatement(
          'INSERT INTO count_history (practice_id, count) VALUES (1, 42)',
        );

        expect(await _userVersion(v2), 2);
        await v2.close();
      }

      // Сессия 2: открываем актуальной версией с включёнными FK (I-2).
      {
        final db = AppDatabase.forTesting(
          NativeDatabase(dbFile(), setup: enableForeignKeys),
        );

        expect(await _userVersion(db), db.schemaVersion);

        // 1. Новая колонка появилась.
        expect(
          await _columnNames(db, 'practices'),
          contains('preset_practice_id'),
        );

        // 2. Уникальный индекс создан переходом, а не только свежей установкой.
        final indexes = await db.customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'index' "
          "AND name = 'idx_practices_tradition_preset'",
        ).get();
        expect(indexes, hasLength(1));

        // 3. Данные пользователя целы: и практика со счётом, и история.
        final practices = await db.select(db.practices).get();
        expect(practices, hasLength(1));
        expect(practices.single.name, 'Простирания');
        expect(practices.single.currentCount, 42);
        expect(await _columnCount(db, 'count_history'), 1);
        expect(await _columnCount(db, 'presets'), 1);

        // 4. Существо B-11: после миграции удаление практики каскадно
        //    убирает историю. Со старым DDL (RESTRICT) этот же delete упал бы
        //    с ошибкой FK, а без FK история осиротела бы.
        await (db.delete(db.practices)..where((t) => t.id.equals(1))).go();
        expect(await _columnCount(db, 'count_history'), 0);

        await db.close();
      }
    });

    test('уникальный индекс не даёт дублей пресетных практик, но волен '
        'для кастомных и других традиций (B-3)', () async {
      final db = AppDatabase.forTesting(
        NativeDatabase(dbFile(), setup: enableForeignKeys),
      );

      Future<int> insert(int id, String tag, String? presetPracticeId) =>
          db.customInsert(
            'INSERT INTO practices (id, name, type, tradition_tag, '
            'preset_practice_id) VALUES (?, ?, ?, ?, ?)',
            variables: [
              Variable.withInt(id),
              Variable.withString('практика'),
              Variable.withString('counter'),
              Variable.withString(tag),
              Variable<String>(presetPracticeId),
            ],
          );

      await insert(1, 'nyingma', 'ngondro_prostrations');

      // Тот же (tradition_tag, preset_practice_id) — дубль запрещён.
      await expectLater(
        insert(2, 'nyingma', 'ngondro_prostrations'),
        throwsA(isA<SqliteException>()),
      );

      // NULL preset_practice_id (кастомные трекеры) — не ограничены.
      await insert(3, 'nyingma', null);
      await insert(4, 'nyingma', null);

      // Та же пресетная практика в другой традиции — законна (изоляция).
      await insert(5, 'theravada', 'ngondro_prostrations');

      expect(await _columnCount(db, 'practices'), 4);

      await db.close();
    });

    test('объявленная, но нереализованная версия падает громко (R-8)',
        () async {
      // Готовим базу актуальной версии 3.
      {
        final db = AppDatabase.forTesting(NativeDatabase(dbFile()));
        await _tableNames(db);
        await db.close();
      }

      // Открываем базой, которая объявляет версию 4 без миграции на неё.
      // Раньше это тихо не делало ничего — теперь обязано упасть.
      final v4 = _AppDatabaseV4(NativeDatabase(dbFile()));

      await expectLater(
        _tableNames(v4),
        throwsA(
          predicate<Object>(
            (error) => error.toString().contains('Нет миграции на версию 4'),
            'ошибка называет отсутствующую версию миграции',
          ),
        ),
      );

      // v4 намеренно не закрываем: соединение не открылось.
    });

    test('препосылка downgrade-теста: старая версия ровно на 1 ниже текущей',
        () {
      // Держит _AppDatabaseDowngrade в согласии со схемой: если версия
      // уедет, downgrade-тест ниже должен быть обновлён, а не протхнуть
      // проверку «на 1 ниже» молча.
      final current = AppDatabase.forTesting(NativeDatabase.memory());
      final older = _AppDatabaseDowngrade(NativeDatabase.memory());
      expect(older.schemaVersion, current.schemaVersion - 1);
    });

    test('downgrade не поддерживается: открытие старой версией бросает '
        'StateError и не трогает данные (R-8/B-12)', () async {
      final current = AppDatabase.forTesting(NativeDatabase.memory())
          .schemaVersion;
      final older = _AppDatabaseDowngrade(NativeDatabase.memory()).schemaVersion;
      expect(older, current - 1); // согласовано с тестом-препосылкой выше

      // Сессия 1: пользовательская база текущей версии с данными.
      {
        final db = AppDatabase.forTesting(NativeDatabase(dbFile()));
        await db.into(db.presets).insert(
              PresetsCompanion.insert(
                id: 'nyingma',
                name: 'Ньингма',
                version: '1.0.0',
                tradition: 'vajrayana',
                data: '{"id":"nyingma"}',
              ),
            );
        await db.into(db.practices).insert(
              PracticesCompanion.insert(
                name: 'Простирания',
                type: 'counter',
                traditionTag: 'nyingma',
                target: const Value(100000),
                currentCount: const Value(42),
              ),
            );
        expect(await _userVersion(db), current);
        await db.close();
      }

      // Сессия 2: тот же файл открывает «старое приложение» (версия на 1
      // ниже). Поведение Drift при downgrade раньше не проверялось ничем
      // (B-12): тихое понижение user_version означало бы, что следующее
      // открытие актуальной версией пойдёт по миграционной ветке поверх
      // уже новой схемы. Ветка `from > to` обязана бросить StateError с
      // направлением «фактическая версия файла → версия приложения».
      {
        final stale = _AppDatabaseDowngrade(NativeDatabase(dbFile()));
        await expectLater(
          _tableNames(stale),
          throwsA(
            allOf(
              isA<StateError>(),
              predicate<Object>(
                (error) =>
                    error.toString().contains('Понижение версии') &&
                    error.toString().contains('$current → $older'),
                'ошибка называет переход (версия файла → версия приложения)',
              ),
            ),
          ),
        );
        // Соединение не открылось — close не вызываем (как в R-8 тесте выше).
      }

      // Сессия 3: файл не испорчен неудачной попыткой — те же данные и та
      // же версия схемы. Это суть митигации R-8: падение у разработчика,
      // а не порча пользовательских данных.
      {
        final db = AppDatabase.forTesting(NativeDatabase(dbFile()));
        expect(await _userVersion(db), current);

        final presets = await db.select(db.presets).get();
        expect(presets.single.name, 'Ньингма');
        final practices = await db.select(db.practices).get();
        expect(practices.single.currentCount, 42);

        await db.close();
      }
    });
  });
}
