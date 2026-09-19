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

/// База, объявляющая версию схемы 5, для которой миграции не написано.
///
/// Регрессия на R-8: прежняя реализация в такой ситуации молча ничего
/// не делала, и ошибка всплывала у пользователя как «no such table».
/// Теперь она обязана упасть на первом же открытии базы.
///
/// Версия держится ровно на одну выше текущей: когда у схемы появится ветка 5,
/// этот класс обязан переехать на 6 (иначе тест начнёт проверять существующую
/// миграцию и «покраснеет» по неверной причине).
class _AppDatabaseV5 extends AppDatabase {
  // ignore: use_super_parameters — см. комментарий у _AppDatabaseV1
  _AppDatabaseV5(QueryExecutor executor) : super.forTesting(executor);

  @override
  int get schemaVersion => 5;
}

/// База «старого приложения» — версия схемы на 1 ниже текущей.
///
/// Миграционную стратегию **наследует** от [AppDatabase] (в отличие от
/// `_AppDatabaseV1`/`_AppDatabaseV2`, которые переопределяют её целиком):
/// нужен именно downgrade-проверочный путь `onUpgrade` актуального кода —
/// переход 3 → 2 обязан упасть на ветке `from > to` (B-12, хвост R-8).
/// Значение 3 согласовано с тестом ниже: тест проверяет, что это ровно
/// `schemaVersion - 1`, и краснеет, если версия схемы уедет без обновления
/// препосылки.
class _AppDatabaseDowngrade extends AppDatabase {
  // ignore: use_super_parameters — см. комментарий у _AppDatabaseV1
  _AppDatabaseDowngrade(QueryExecutor executor) : super.forTesting(executor);

  @override
  int get schemaVersion => 3;
}

/// DDL версии 2 из снимка генератора (`test/fixtures/schema_v2_drift.sql`).
///
/// Фикстура снималась прогоном настоящего кода ревизии `f0b6c5e`, а не
/// переписывалась глазами (W27): рукописная версия отличалась от генератора и
/// статическим `DEFAULT 1725000000` вместо `strftime(...)`, и формулировкой
/// внешнего ключа. Править файл руками нельзя — гард ниже сверяет, что replay
/// даёт ровно ту схему, что задекларирована в снимке.
List<String> _schemaV2Statements() => File('test/fixtures/schema_v2_drift.sql')
    .readAsLinesSync()
    .map((line) => line.trim())
    .where((line) => line.isNotEmpty && !line.startsWith('--'))
    .map((line) =>
        line.endsWith(';') ? line.substring(0, line.length - 1) : line)
    .toList();

/// База версии 2 со СТАРОЙ схемой практик и истории — из снимка генератора.
///
/// Использовать актуальные классы Drift-таблиц здесь нельзя: они генерируют
/// уже v3-DDL (с колонкой preset_practice_id и каскадом). Снимок фиксирует
/// именно то состояние, в котором живут пользовательские базы до 5.0.2.
class _AppDatabaseV2 extends AppDatabase {
  // ignore: use_super_parameters — см. комментарий у _AppDatabaseV1
  _AppDatabaseV2(QueryExecutor executor) : super.forTesting(executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          for (final statement in _schemaV2Statements()) {
            await customStatement(statement);
          }
        },
      );
}

/// База, зафиксированная ровно на версии 3 (последняя до 6.1).
///
/// Нужна, чтобы получить файл в состоянии «до появления настроек уведомлений»
/// **настоящей** миграцией 2 → 3 (стратегия наследуется от [AppDatabase]),
/// а не сырым DDL: так проверяется реальный переход 3 → 4, а не имитация.
class _AppDatabaseV3Step extends AppDatabase {
  // ignore: use_super_parameters — см. комментарий у _AppDatabaseV1
  _AppDatabaseV3Step(QueryExecutor executor) : super.forTesting(executor);

  @override
  int get schemaVersion => 3;
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

/// Состояние `PRAGMA foreign_keys` на текущем соединении (W7).
Future<bool> _foreignKeysEnabled(GeneratedDatabase db) async {
  final row = await db.customSelect('PRAGMA foreign_keys').getSingle();
  return row.read<int>('foreign_keys') == 1;
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
        containsAll(<String>[
          'presets',
          'practices',
          'count_history',
          'notification_settings',
        ]),
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
        final v2 = _AppDatabaseV2(NativeDatabase(dbFile()));

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

    test('апгрейд 3 → 4: таблица настроек уведомлений создана, данные целы',
        () async {
      // Сессия 1: старая база версии 2 с пользовательскими данными.
      {
        final v2 = _AppDatabaseV2(NativeDatabase(dbFile()));
        await v2.customStatement(
          "INSERT INTO presets VALUES "
          "('nyingma', 'Ньингма', '1.0.0', 'vajrayana', '{}')",
        );
        await v2.customStatement(
          "INSERT INTO practices (id, name, type, tradition_tag, current_count) "
          "VALUES (1, 'Простирания', 'counter', 'nyingma', 108)",
        );
        await v2.customStatement(
          'INSERT INTO count_history (practice_id, count) VALUES (1, 108)',
        );
        await v2.close();
      }

      // Сессия 2: доводим файл до версии 3 настоящей миграцией 2 → 3.
      {
        final v3 = _AppDatabaseV3Step(NativeDatabase(dbFile()));
        expect(await _userVersion(v3), 3);
        expect(await _tableNames(v3), isNot(contains('notification_settings')));
        await v3.close();
      }

      // Сессия 3: актуальная версия выполняет ветку 4.
      {
        final db = AppDatabase.forTesting(
          NativeDatabase(dbFile(), setup: enableForeignKeys),
        );
        expect(await _userVersion(db), db.schemaVersion);

        expect(await _tableNames(db), contains('notification_settings'));
        expect(
          await _columnNames(db, 'notification_settings'),
          containsAll(<String>[
            'tradition_tag',
            'enabled',
            'hour',
            'minute',
            'updated_at',
          ]),
        );

        // Данные пользователя целы: переход добавил только новую таблицу.
        expect((await db.select(db.practices).get()).single.currentCount, 108);
        expect(await _columnCount(db, 'count_history'), 1);
        expect(await _columnCount(db, 'presets'), 1);

        // Пустая таблица настроек — штатное состояние: строка появляется
        // только когда пользователь меняет настройки (дефолт D-36 живёт
        // в домене, а не в БД).
        expect(await _columnCount(db, 'notification_settings'), 0);

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

      // Открываем базой, которая объявляет версию 5 без миграции на неё.
      // Раньше это тихо не делало ничего — теперь обязано упасть.
      final v5 = _AppDatabaseV5(NativeDatabase(dbFile()));

      await expectLater(
        _tableNames(v5),
        throwsA(
          predicate<Object>(
            (error) => error.toString().contains('Нет миграции на версию 5'),
            'ошибка называет отсутствующую версию миграции',
          ),
        ),
      );

      // v5 намеренно не закрываем: соединение не открылось.
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

    test('цепочка миграций атомарна: сбой посередине откатывает схему (W6)',
        () async {
      const lastBranch = 4; // совпадает с assert-ниже: последняя ветка цепочки

      // Сессия 1: пользовательская база версии 2 со счётом.
      {
        final v2 = _AppDatabaseV2(NativeDatabase(dbFile()));
        await v2.customStatement(
          "INSERT INTO presets VALUES "
          "('nyingma', 'Ньингма', '1.0.0', 'vajrayana', '{}')",
        );
        await v2.customStatement(
          "INSERT INTO practices (id, name, type, tradition_tag, current_count) "
          "VALUES (1, 'Простирания', 'counter', 'nyingma', 21000)",
        );
        await v2.customStatement(
          'INSERT INTO count_history (practice_id, count) VALUES (1, 21000)',
        );
        expect(await _userVersion(v2), 2);
        await v2.close();
      }

      // Сессия 2: апгрейд 2 → актуальная версия падает перед последней
      // веткой. Шов debugFailBeforeVersion — единственный способ уронить
      // середину цепочки, не порча данных и не игра с таймингами.
      {
        final db = AppDatabase.forTesting(NativeDatabase(dbFile()));
        expect(db.schemaVersion, lastBranch,
            reason: 'тест написан под цепочку, где 4 — последняя ветка; '
                'при добавлении версии обновить и это ожидаемое, и сценарий');
        db.debugFailBeforeVersion = (target) async {
          if (target == lastBranch) {
            throw StateError('инjected: сбой перед веткой $target');
          }
        };
        await expectLater(
          _tableNames(db),
          throwsA(
            predicate<Object>(
              (error) => error.toString().contains('инjected: сбой перед веткой'),
              'всплывает именно подброшенная причина, а не «no such table»',
            ),
          ),
        );
        await db.close();
      }

      // Сессия 3: файл выглядит так, будто апгрейда не было вовсе — и по
      // номеру версии, и по составу схемы. Это и есть гард транзакции:
      // без неё ветка 3 (addColumn + индекс + пересоздание count_history)
      // осталась бы на диске при user_version = 2.
      {
        final after = _AppDatabaseV2(NativeDatabase(dbFile()));
        expect(await _userVersion(after), 2);
        expect(await _columnNames(after, 'practices'),
            isNot(contains('preset_practice_id')));
        expect(await _tableNames(after), isNot(contains('notification_settings')));
        expect(await _columnCount(after, 'practices'), 1);
        expect(await _columnCount(after, 'count_history'), 1);
        await after.close();
      }

      // Сессия 4: откат не сломал базу — тот же файл до мигрируется до
      // конца, данные целы.
      {
        final db = AppDatabase.forTesting(NativeDatabase(dbFile()));
        expect(await _userVersion(db), db.schemaVersion);
        expect(await _columnNames(db, 'practices'), contains('preset_practice_id'));
        expect(await _columnCount(db, 'practices'), 1);
        final history = await db.select(db.countHistory).get();
        expect(history.single.count, 21000);
        await db.close();
      }
    });

    test('FK включены на тест-пути без setup: pragma ON и каскад (W7)',
        () async {
      // Ровно та ветка, что раньше молча жила с FK OFF: forTesting +
      // NativeDatabase.memory() без `setup: enableForeignKeys`.
      final db = AppDatabase.forTesting(NativeDatabase.memory());

      expect(await _foreignKeysEnabled(db), isTrue,
          reason: 'PRAGMA обязан применяться в migration.beforeOpen, а не '
              'только в setup: прод-соединения');

      final id = await db.into(db.practices).insert(
            PracticesCompanion.insert(
              name: 'Простирания',
              type: 'counter',
              traditionTag: 'nyingma',
              currentCount: const Value(108),
            ),
          );
      await db.into(db.countHistory).insert(
            CountHistoryCompanion.insert(practiceId: id, count: 108),
          );
      await (db.delete(db.practices)..where((t) => t.id.equals(id))).go();

      // Без pragma каскад не сработал бы: строки истории осиротели, а тест
      // остался зелёным (расхождение прод/тест в семантике удалений, B-22).
      expect(await _columnCount(db, 'count_history'), 0);

      await db.close();
    });

    test('FK включены и на прод-пути (NativeDatabase + setup) (W7)', () async {
      final db = AppDatabase.forTesting(
        NativeDatabase(dbFile(), setup: enableForeignKeys),
      );

      expect(await _foreignKeysEnabled(db), isTrue);

      final id = await db.into(db.practices).insert(
            PracticesCompanion.insert(
              name: 'Практика с историей',
              type: 'counter',
              traditionTag: 'nyingma',
            ),
          );
      await db.into(db.countHistory).insert(
            CountHistoryCompanion.insert(practiceId: id, count: 1000000),
          );
      // Сирота запрещён уровнем соединения: без FK такая вставка прошла бы
      // молча, и тест перестал бы отличать каскад от его отсутствия.
      await expectLater(
        db.into(db.countHistory).insert(
              CountHistoryCompanion.insert(practiceId: 9999, count: 1),
            ),
        throwsA(isA<SqliteException>()),
      );
      await (db.delete(db.practices)..where((t) => t.id.equals(id))).go();
      expect(await _columnCount(db, 'count_history'), 0);

      await db.close();
    });

    test('фикстура v2 — DDL генератора, единицы времени — секунды (W27)',
        () async {
      // (1) Что пишет drift на прод-подобном пути: DateTime колонка — это
      // целое ЧИСЛО СЕКУНД (mapToSql: millisecondsSinceEpoch ~/ 1000).
      // (2) Что даёт DEFAULT из снимка v2 — те же секунды, потому что DEFAULT
      // в снимке дословно тот же `strftime('%s', CURRENT_TIMESTAMP)`.
      final instant = DateTime.utc(2024, 9, 1, 12);
      {
        final v2 = _AppDatabaseV2(NativeDatabase(dbFile()));
        await v2.customInsert(
          'INSERT INTO practices (id, name, type, tradition_tag, created_at) '
          'VALUES (?, ?, ?, ?, ?)',
          variables: [
            Variable.withInt(1),
            Variable.withString('Простирания'),
            Variable.withString('counter'),
            Variable.withString('nyingma'),
            Variable.withInt(instant.millisecondsSinceEpoch ~/ 1000),
          ],
        );
        await v2.customStatement(
          "INSERT INTO practices (name, type, tradition_tag) "
          "VALUES ('Без явной даты', 'counter', 'nyingma')",
        );
        final raw = await v2
            .customSelect('SELECT id, created_at FROM practices ORDER BY id')
            .get();
        final explicit = raw[0].data['created_at'] as int;
        final defaulted = raw[1].data['created_at'] as int;
        final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;

        expect(explicit, instant.millisecondsSinceEpoch ~/ 1000);
        expect((defaulted - nowSeconds).abs(), lessThan(60),
            reason: 'DEFAULT из снимка v2 обязан давать секунды: значение '
                '$defaulted рядом с now=$nowSeconds');
        expect(defaulted.toString().length, 10,
            reason: '13 знаков = миллисекунды; фикстура не должна возвращаться '
                'на выдуманные единицы');
        await v2.close();
      }

      // (3) Значения фикстуры читаются drift-маппингом как те же самые
      // моменты, что и записи прод-пути: после миграции 2 → текущая версия
      // дата не уезжает в 1970-й или в 45-й век.
      {
        final db = AppDatabase.forTesting(NativeDatabase(dbFile()));
        final rows = await db.select(db.practices).get();
        expect(rows.map((r) => r.name), containsAll(['Простирания', 'Без явной даты']));
        final stored = rows.firstWhere((r) => r.name == 'Простирания').createdAt;
        expect(stored.difference(instant.toLocal()).abs().inSeconds,
            lessThan(2),
            reason: 'drift читает секунды из фикстуры — тот же миг, что и писали');
        await db.close();
      }
    });
  });
}
