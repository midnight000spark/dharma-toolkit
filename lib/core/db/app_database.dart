import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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
@DriftDatabase(tables: [Presets])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Constructor for testing with in-memory database.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        // Future migrations go here
      },
    );
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'dharma_toolkit.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
