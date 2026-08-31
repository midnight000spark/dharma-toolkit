import 'package:dharma_toolkit/core/config/config_module.dart';
import 'package:dharma_toolkit/core/db/database_module.dart';
import 'package:dharma_toolkit/core/module/module_registry.dart';
import 'package:dharma_toolkit/core/storage/storage_module.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ModuleRegistry integration', () {
    setUp(() async {
      // Reset singleton state between tests
      await ModuleRegistry.instance.disposeAll();
      SharedPreferences.setMockInitialValues({});
    });

    test('all three modules register without errors', () {
      final registry = ModuleRegistry.instance;

      registry.register(DatabaseModule());
      registry.register(StorageModule());
      registry.register(ConfigModule());

      expect(registry.get('database'), isNotNull);
      expect(registry.get('storage'), isNotNull);
      expect(registry.get('config'), isNotNull);
    });

    test('initAll initializes all modules', () async {
      final registry = ModuleRegistry.instance;

      registry.register(DatabaseModule());
      registry.register(StorageModule());
      registry.register(ConfigModule());

      await registry.initAll();

      // Verify each module is accessible after init
      final dbModule = registry.get('database') as DatabaseModule;
      expect(dbModule.database, isNotNull);

      final storageModule = registry.get('storage') as StorageModule;
      // StorageModule should be initialized (no StateError)
      expect(() => storageModule.getString('test'), returnsNormally);

      final configModule = registry.get('config') as ConfigModule;
      // ConfigModule читает манифест index.json и грузит перечисленные пресеты.
      expect(configModule.getPreset('nyingma'), isNotNull);
      expect(configModule.getPreset('theravada_default'), isNotNull);
      expect(configModule.availablePresetIds,
          containsAll(<String>['nyingma', 'theravada_default']));
      // tree.json — не мёртвый ассет: дерево традиций прочитано (B-4).
      expect(configModule.tree, isNotEmpty);
      expect(configModule.tree.map((t) => t.id), contains('vajrayana'));
      // Ньингма-пресет материализуем: четыре практики нёндро объявлены.
      expect(configModule.getPreset('nyingma')!.practices, hasLength(4));
    });

    test('disposeAll completes without errors', () async {
      final registry = ModuleRegistry.instance;

      registry.register(DatabaseModule());
      registry.register(StorageModule());
      registry.register(ConfigModule());

      await registry.initAll();
      await registry.disposeAll();

      // After disposeAll, registry should be empty
      expect(registry.get('database'), isNull);
      expect(registry.get('storage'), isNull);
      expect(registry.get('config'), isNull);
    });
  });
}
