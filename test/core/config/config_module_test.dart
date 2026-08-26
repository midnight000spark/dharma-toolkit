import 'package:dharma_toolkit/core/config/config_module.dart';
import 'package:dharma_toolkit/core/config/preset_schema.dart';
import 'package:dharma_toolkit/core/module/app_module.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PresetSchema', () {
    test('fromJson parses valid JSON', () {
      final json = {
        'id': 'theravada',
        'name': 'Тхеравада',
        'version': '1.0.0',
        'modules': ['calendar', 'tracker'],
        'description': 'Тхеравада буддизм',
      };

      final preset = PresetSchema.fromJson(json);

      expect(preset.id, 'theravada');
      expect(preset.name, 'Тхеравада');
      expect(preset.version, '1.0.0');
      expect(preset.modules, ['calendar', 'tracker']);
      expect(preset.description, 'Тхеравада буддизм');
    });

    test('fromJson throws on invalid JSON', () {
      final json = {
        'id': 'test',
        // Missing required fields
      };

      expect(() => PresetSchema.fromJson(json), throwsA(isA<TypeError>()));
    });
  });

  group('ConfigModule', () {
    test('implements AppModule', () {
      final module = ConfigModule();
      expect(module, isA<AppModule>());
    });

    test('has correct id, name, version', () {
      final module = ConfigModule();

      expect(module.id, 'config');
      expect(module.name, 'Конфигурация');
      expect(module.version, '1.0.0');
    });
  });
}
