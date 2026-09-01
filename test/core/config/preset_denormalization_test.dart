import 'dart:convert';

import 'package:dharma_toolkit/core/config/preset_manager.dart';
import 'package:dharma_toolkit/core/config/preset_schema.dart';
import 'package:dharma_toolkit/core/db/app_database.dart';
import 'package:dharma_toolkit/core/storage/storage_module.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Страж денормализации таблицы `presets` (R-14, пакет 5b.5 блок 4).
///
/// Диагноз R-14: колонки `name`/`version`/`tradition` дублируют поля того же
/// пресета внутри JSON в `data`, а читается только `data`
/// (`PresetManager._loadPresetFromDb`) — расходование колонок с JSON не
/// заметил бы ни один тест и ни один рантайм. Выбран вариант 4.2: колонки
/// остаются отладочной/запросной денормализацией (контракт зафиксирован в
/// шапке таблицы `Presets`), а согласованность охраняется этим тестом.
///
/// Проверка — путь сохранения (урок 4), а не отрисовка: после реального
/// `applyPreset` колонки сравниваются с полями JSON, лежащего в той же
/// строке. Повторное применение с изменёнными полями (upsert) обязано
/// рассинхронизировать их так же честно, как и первый запись.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late StorageModule storage;
  late PresetManager manager;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    database = AppDatabase.forTesting(NativeDatabase.memory());
    storage = StorageModule();
    await storage.init();
    manager = PresetManager(() => database, storage);
    await manager.init();
  });

  tearDown(() async {
    await manager.dispose();
    await storage.dispose();
    await database.close();
  });

  PresetSchema presetOf({
    required String name,
    required String version,
    required String tradition,
  }) =>
      PresetSchema(
        id: 'nyingma',
        name: name,
        version: version,
        tradition: tradition,
        modules: const ['calendar'],
        practices: const [],
        eventPacks: const [],
        contentPacks: const [],
      );

  /// Колонки строки и те же поля внутри JSON `data` — из одного чтения.
  Future<(Map<String, String> columns, Map<String, dynamic> json)>
      rowState() async {
    final row = await (database.select(database.presets)
          ..where((t) => t.id.equals('nyingma')))
        .getSingle();
    return (
      {
        'id': row.id,
        'name': row.name,
        'version': row.version,
        'tradition': row.tradition,
      },
      jsonDecode(row.data) as Map<String, dynamic>,
    );
  }

  group('денормализация presets (R-14)', () {
    test('applyPreset: колонки равны полям JSON в data', () async {
      await manager.applyPreset(
        presetOf(
          name: 'Ньингма',
          version: '1.0.0',
          tradition: 'vajrayana',
        ),
      );

      final (columns, json) = await rowState();
      expect(columns['id'], json['id']);
      expect(columns['name'], json['name']);
      expect(columns['version'], json['version']);
      expect(columns['tradition'], json['tradition']);
      // Проверка не тавтология: значения нетривиальны и взяты из разных
      // мест строки — колонки и JSON пишутся раздельными аргументами
      // insert-компаньона.
      expect(columns['name'], 'Ньингма');
      expect(columns['tradition'], 'vajrayana');
    });

    test('повторное applyPreset с другими полями обновляет и колонки, и JSON',
        () async {
      await manager.applyPreset(
        presetOf(
          name: 'Ньингма',
          version: '1.0.0',
          tradition: 'vajrayana',
        ),
      );
      // Тот же id, изменённые денормализуемые поля (upsert-путь).
      await manager.applyPreset(
        presetOf(
          name: 'Ньингма (обновлённый пресет)',
          version: '2.0.0',
          tradition: 'nyngma',
        ),
      );

      final (columns, json) = await rowState();
      expect(columns['name'], json['name']);
      expect(columns['version'], json['version']);
      expect(columns['tradition'], json['tradition']);
      // И что обновился именно весь набор, а не только JSON: устаревшие
      // колонки после upsert — тот же класс бага, что и рассинхрон записи.
      expect(columns['version'], '2.0.0');
      expect(columns['tradition'], 'nyngma');
    });

    test('источник истины — data: менеджер читает пресет из JSON', () async {
      final preset = presetOf(
        name: 'Ньингма',
        version: '1.0.0',
        tradition: 'vajrayana',
      );
      await manager.applyPreset(preset);

      // Новый менеджер поверх той же базы восстанавливает активный пресет
      // из `data` — ровно исходный объект.
      final reopened = PresetManager(() => database, storage);
      await reopened.init();
      final loaded = reopened.activePreset;
      expect(loaded, isNotNull);
      expect(loaded!.name, preset.name);
      expect(loaded.version, preset.version);
      expect(loaded.tradition, preset.tradition);
      await reopened.dispose();
    });
  });
}
