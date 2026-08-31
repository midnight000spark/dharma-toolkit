import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../features/tracker/data/tracker_tables.dart';

part 'app_database.g.dart';

/// Row class for presets table.
class PresetRow {
  final String id;
  final String name;
  final String version;
  final String tradition;
  final String data;

  PresetRow({
    required this.id,
    required this.name,
    required this.version,
    required this.tradition,
    required this.data,
  });
}

/// Presets table — stores applied presets as JSON.
@UseRowClass(PresetRow)
class Presets extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get version => text()();
  TextColumn get tradition => text()();
  TextColumn get data => text()(); // Full JSON of PresetSchema

  @override
  Set<Column> get primaryKey => {id};
}

/// Main application database using Drift (SQLite).
///
/// Handles all persistent data storage for the application.
/// Migrations are managed through [MigrationStrategy].
@DriftDatabase(tables: [Presets, Practices, CountHistory])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Constructor for testing with in-memory database.
  AppDatabase.forTesting(super.executor);

  /// Текущая версия схемы БД.
  ///
  /// Порядок изменения схемы (см. `docs/MIGRATIONS.md`):
  /// 1. изменить таблицы и перегенерировать код (`build_runner`);
  /// 2. увеличить это число на единицу;
  /// 3. добавить ветку в [_migrateToVersion];
  /// 4. добавить тест перехода в `test/core/db/migration_test.dart`.
  ///
  /// Шаг 3 нельзя пропустить молча: без своей ветки миграция бросает
  /// [StateError] при первом же открытии базы (R-8).
  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        if (from > to) {
          throw StateError(
            'Понижение версии схемы БД не поддерживается: $from → $to. '
            'Данные на устройстве новее установленного приложения.',
          );
        }
        // Версии применяются последовательно: 1→2, затем 2→3 и так далее.
        // Пропуск промежуточных версий (например, обновление приложения
        // через несколько релизов) обрабатывается тем же циклом.
        for (var target = from + 1; target <= to; target++) {
          await _migrateToVersion(m, target);
        }
      },
    );
  }

  /// Один шаг миграции: приводит схему с версии `version - 1` к `version`.
  ///
  /// Каждая версия обязана иметь свою ветку. Отсутствие ветки — ошибка
  /// разработчика, а не повод ничего не делать: прежняя реализация
  /// (`if (from < 2) await m.createAll()`) при переходе на версию 3
  /// не выполнила бы ничего, и пользователь получил бы «no such table»
  /// в рантайме вместо понятной ошибки на этапе разработки (R-8).
  ///
  /// Новые таблицы добавляются через [Migrator.createTable], новые колонки —
  /// через [Migrator.addColumn]. `createAll()` здесь использовать нельзя:
  /// он не изменяет уже существующие таблицы.
  Future<void> _migrateToVersion(Migrator m, int version) async {
    switch (version) {
      case 2:
        // Этап 4: модуль «Практика» — трекеры и история счёта.
        await m.createTable(practices);
        await m.createTable(countHistory);
        break;
      default:
        throw StateError(
          'Нет миграции на версию $version схемы БД. '
          'Добавьте ветку в AppDatabase._migrateToVersion и тест перехода '
          'в test/core/db/migration_test.dart (см. docs/MIGRATIONS.md).',
        );
    }
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'dharma_toolkit.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
