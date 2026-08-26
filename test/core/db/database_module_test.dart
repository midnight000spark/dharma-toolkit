import 'package:dharma_toolkit/core/db/database_module.dart';
import 'package:dharma_toolkit/core/module/app_module.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DatabaseModule', () {
    test('implements AppModule', () {
      final module = DatabaseModule();
      expect(module, isA<AppModule>());
    });

    test('has correct id, name, version', () {
      final module = DatabaseModule();

      expect(module.id, 'database');
      expect(module.name, 'База данных');
      expect(module.version, '1.0.0');
    });

    test('throws StateError when accessing database before init', () {
      final module = DatabaseModule();

      expect(() => module.database, throwsA(isA<StateError>()));
    });

    test('init completes without error', () async {
      final module = DatabaseModule();

      await module.init();

      // Database should be accessible after init
      expect(module.database, isNotNull);

      // Cleanup
      await module.dispose();
    });

    test('dispose can be called multiple times safely', () async {
      final module = DatabaseModule();

      await module.init();
      await module.dispose();
      await module.dispose(); // Should not throw

      expect(true, isTrue);
    });
  });
}
