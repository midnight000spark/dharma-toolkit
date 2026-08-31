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

/// База, объявляющая версию схемы 3, для которой миграции не написано.
///
/// Регрессия на R-8: прежняя реализация в такой ситуации молча ничего
/// не делала, и ошибка всплывала у пользователя как «no such table».
/// Теперь она обязана упасть на первом же открытии базы.
class _AppDatabaseV3 extends AppDatabase {
  // ignore: use_super_parameters — см. комментарий у _AppDatabaseV1
  _AppDatabaseV3(QueryExecutor executor) : super.forTesting(executor);

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
        expect(await _userVersion(db), 2);

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

    test('объявленная, но нереализованная версия падает громко (R-8)',
        () async {
      // Готовим базу актуальной версии 2.
      {
        final db = AppDatabase.forTesting(NativeDatabase(dbFile()));
        await _tableNames(db);
        await db.close();
      }

      // Открываем базой, которая объявляет версию 3 без миграции на неё.
      // Раньше это тихо не делало ничего — теперь обязано упасть.
      final v3 = _AppDatabaseV3(NativeDatabase(dbFile()));

      await expectLater(
        _tableNames(v3),
        throwsA(
          predicate<Object>(
            (error) => error.toString().contains('Нет миграции на версию 3'),
            'ошибка называет отсутствующую версию миграции',
          ),
        ),
      );

      // v3 намеренно не закрываем: соединение не открылось.
    });
  });
}
