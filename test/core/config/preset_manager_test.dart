import 'package:dharma_toolkit/core/config/preset_manager.dart';
import 'package:dharma_toolkit/core/config/preset_schema.dart';
import 'package:dharma_toolkit/core/db/app_database.dart';
import 'package:dharma_toolkit/core/module/app_module.dart';
import 'package:dharma_toolkit/core/module/module_registry.dart';
import 'package:dharma_toolkit/core/recovery/startup.dart';
import 'package:dharma_toolkit/core/storage/storage_module.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late StorageModule storageModule;
  late PresetManager presetManager;

  setUp(() async {
    // Set up mock SharedPreferences
    SharedPreferences.setMockInitialValues({});

    // Create in-memory database for testing
    database = AppDatabase.forTesting(NativeDatabase.memory());
    storageModule = StorageModule();
    await storageModule.init();

    presetManager = PresetManager(() => database, storageModule);
    await presetManager.init();
  });

  tearDown(() async {
    await presetManager.dispose();
    await storageModule.dispose();
    await database.close();
  });

  group('PresetManager', () {
    test('implements AppModule', () {
      expect(presetManager, isA<AppModule>());
    });

    test('has correct id, name, version', () {
      expect(presetManager.id, 'preset_manager');
      expect(presetManager.name, 'Менеджер пресетов');
      expect(presetManager.version, '1.0.0');
    });

    test('applyPreset saves preset to DB and storage', () async {
      final preset = PresetSchema(
        id: 'test_preset',
        name: 'Тестовый пресет',
        version: '1.0.0',
        tradition: 'theravada',
        modules: ['calendar'],
        practices: [],
        eventPacks: [],
        contentPacks: [],
      );

      await presetManager.applyPreset(preset);

      // Check storage
      expect(storageModule.getString('active_preset_id'), 'test_preset');

      // Check active preset
      expect(presetManager.activePreset, isNotNull);
      expect(presetManager.activePreset!.id, 'test_preset');
      expect(presetManager.activePreset!.tradition, 'theravada');
    });

    test('activePreset returns applied preset', () async {
      expect(presetManager.activePreset, isNull);

      final preset = PresetSchema(
        id: 'nyingma',
        name: 'Ньингма',
        version: '1.0.0',
        tradition: 'vajrayana',
        modules: ['calendar', 'tracker'],
        practices: [
          PresetPractice(
            id: 'prostrations',
            name: 'Простирания',
            type: 'counter',
            target: 100000,
          ),
        ],
        eventPacks: [],
        contentPacks: [],
      );

      await presetManager.applyPreset(preset);

      expect(presetManager.activePreset, isNotNull);
      expect(presetManager.activePreset!.id, 'nyingma');
      expect(presetManager.activePreset!.practices, hasLength(1));
    });

    test('resetPreset clears storage and activePreset', () async {
      final preset = PresetSchema(
        id: 'test',
        name: 'Тест',
        version: '1.0.0',
        tradition: 'sample',
        modules: [],
        practices: [],
        eventPacks: [],
        contentPacks: [],
      );

      await presetManager.applyPreset(preset);
      expect(presetManager.activePreset, isNotNull);

      await presetManager.resetPreset();

      expect(presetManager.activePreset, isNull);
      expect(storageModule.getString('active_preset_id'), isNull);
    });

    test('switchPreset replaces active preset', () async {
      final preset1 = PresetSchema(
        id: 'preset1',
        name: 'Пресет 1',
        version: '1.0.0',
        tradition: 'theravada',
        modules: [],
        practices: [],
        eventPacks: [],
        contentPacks: [],
      );

      final preset2 = PresetSchema(
        id: 'preset2',
        name: 'Пресет 2',
        version: '1.0.0',
        tradition: 'vajrayana',
        modules: ['calendar'],
        practices: [],
        eventPacks: [],
        contentPacks: [],
      );

      await presetManager.applyPreset(preset1);
      expect(presetManager.activePreset!.id, 'preset1');

      await presetManager.switchPreset(preset2);
      expect(presetManager.activePreset!.id, 'preset2');
      expect(presetManager.activePreset!.tradition, 'vajrayana');
    });

    test('init loads active preset from storage', () async {
      // First, apply a preset
      final preset = PresetSchema(
        id: 'persistent',
        name: 'Сохранённый',
        version: '1.0.0',
        tradition: 'mahayana',
        modules: [],
        practices: [],
        eventPacks: [],
        contentPacks: [],
      );

      await presetManager.applyPreset(preset);

      // Create new manager instance (simulating app restart)
      final newManager = PresetManager(() => database, storageModule);
      await newManager.init();

      expect(newManager.activePreset, isNotNull);
      expect(newManager.activePreset!.id, 'persistent');

      await newManager.dispose();
    });
  });

  // C1(1): «в колонке presets.data лежит JSON, который не проходит текущую
  // схему» — штатное состояние (blob в БД не версионирован: тесты миграций
  // держат там же `data: '{"id":"nyingma"}'`), а не повод валить старт на
  // экран восстановления с единственным механизмом «стереть всё» (B-5).
  group('C1(1): неполный blob деградирует, а не роняет старт', () {
    Future<void> seedBrokenPreset() async {
      await database.into(database.presets).insert(
            PresetsCompanion.insert(
              id: 'nyingma',
              name: 'Ньингма',
              version: '1.0.0',
              tradition: 'vajrayana',
              data: '{"id":"nyingma"}', // нет name/version/tradition/practices
            ),
          );
      await storageModule.setString('active_preset_id', 'nyingma');
    }

    test('init не бросает: традиция снята, данные целы, отказ доложен',
        () async {
      await seedBrokenPreset();
      final manager = PresetManager(() => database, storageModule);

      await manager.init();

      expect(manager.activePreset, isNull,
          reason: 'состояние «активной традиции нет» — рабочий, а не отказ');
      expect(storageModule.getString('active_preset_id'), isNull,
          reason: 'ключ снят, иначе следующий старт повторил бы тот же отказ');
      final rows = await database.select(database.presets).get();
      expect(rows, hasLength(1),
          reason: 'снимается настройка, а не данные (D-26)');
      expect(
          manager.ownFailures.single.kind, FailureKind.activePresetUnreadable);
      expect(manager.ownFailures.single.subject, 'nyingma');

      await manager.dispose();
    });

    test('доклад доходит до StartupOutcome.degradedModules; ok == true',
        () async {
      await seedBrokenPreset();
      final registry = ModuleRegistry.instance;
      await registry.disposeAll();
      addTearDown(registry.disposeAll);
      final manager = PresetManager(() => database, storageModule);
      registry.register(manager);

      final outcome = await bootstrapModules(registry);

      expect(outcome.ok, isTrue,
          reason: 'критичный модуль пережил отказ внутри себя и не уводит на '
              'экран стирания (C1)');
      expect(outcome.degradedModules, hasLength(1));
      expect(outcome.degradedModules.single.moduleId, 'preset_manager');
      expect(outcome.degradedModules.single.kind.label,
          'активная традиция не прочитана');
    });

    test('без ключа активной традиции отказов нет (не выдуманная деградация)',
        () async {
      final manager = PresetManager(() => database, storageModule);
      await manager.init();
      expect(manager.ownFailures, isEmpty);
      await manager.dispose();
    });
  });
}
