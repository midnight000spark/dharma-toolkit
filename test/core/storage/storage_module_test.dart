import 'package:dharma_toolkit/core/module/app_module.dart';
import 'package:dharma_toolkit/core/storage/storage_module.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('StorageModule', () {
    test('implements AppModule', () {
      final module = StorageModule();
      expect(module, isA<AppModule>());
    });

    test('has correct id, name, version', () {
      final module = StorageModule();

      expect(module.id, 'storage');
      expect(module.name, 'Хранилище настроек');
      expect(module.version, '1.0.0');
    });

    test('throws StateError when accessing methods before init', () {
      final module = StorageModule();

      expect(() => module.getString('key'), throwsA(isA<StateError>()));
      expect(() => module.getBool('key'), throwsA(isA<StateError>()));
      expect(() => module.getInt('key'), throwsA(isA<StateError>()));
    });

    test('set/get/remove work after init', () async {
      // Set up mock SharedPreferences
      SharedPreferences.setMockInitialValues({});

      final module = StorageModule();
      await module.init();

      // Test string
      await module.setString('name', 'Dharma');
      expect(module.getString('name'), 'Dharma');

      // Test bool
      await module.setBool('dark_mode', true);
      expect(module.getBool('dark_mode'), true);

      // Test int
      await module.setInt('count', 42);
      expect(module.getInt('count'), 42);

      // Test remove
      await module.remove('name');
      expect(module.getString('name'), isNull);

      // Cleanup
      await module.dispose();
    });
  });
}
