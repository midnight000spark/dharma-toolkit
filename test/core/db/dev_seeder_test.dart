import 'dart:convert';

import 'package:dharma_toolkit/core/config/config_module.dart';
import 'package:dharma_toolkit/core/config/preset_manager.dart';
import 'package:dharma_toolkit/core/db/app_database.dart';
import 'package:dharma_toolkit/core/db/dev_seeder.dart';
import 'package:dharma_toolkit/core/storage/storage_module.dart';
import 'package:dharma_toolkit/features/tracker/data/practice_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// B-20: ядро не знает о конкретных школах — сидер берёт первый пресет
/// манифеста, а не литерал `'nyingma'`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late StorageModule storage;
  late PresetManager presets;
  late ConfigModule config;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    storage = StorageModule();
    await storage.init();
    presets = PresetManager(() => db, storage);
    config = ConfigModule();
    await config.init();
  });

  tearDown(() async {
    await db.close();
  });

  test('сеет первый пресет манифеста, а не литерал школы (B-20)', () async {
    // Порядок берём из самого манифеста — независимо от ConfigModule.
    final manifest = jsonDecode(
      await rootBundle.loadString('presets/index.json'),
    ) as Map<String, dynamic>;
    final manifestOrder = (manifest['presets'] as List).cast<String>();

    // Тест различает «первый» и «единственный» только при ≥2 пресетах.
    expect(manifestOrder.length, greaterThanOrEqualTo(2),
        reason: 'иначе мутация «available.first → available.last» не ловится');

    await DevSeeder.seedIfEmpty(presets: presets, config: config);

    expect(presets.activePreset?.id, manifestOrder.first,
        reason: 'источник — порядок presets/index.json, а не хардкод школы');

    // Сид идёт реальным путём applyPreset: данные материализованы (B-3).
    final materialized =
        await PracticeRepository(db).getByTradition(manifestOrder.first);
    expect(materialized, isNotEmpty);
  });

  test('идемпотентен: при активном пресете ничего не меняет', () async {
    await DevSeeder.seedIfEmpty(presets: presets, config: config);
    final firstId = presets.activePreset?.id;

    await DevSeeder.seedIfEmpty(presets: presets, config: config);

    expect(presets.activePreset?.id, firstId);
  });
}
