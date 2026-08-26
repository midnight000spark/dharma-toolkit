import 'package:dharma_toolkit/core/config/config_module.dart';
import 'package:dharma_toolkit/core/config/preset_schema.dart';
import 'package:dharma_toolkit/core/module/app_module.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PresetSchema', () {
    test('fromJson parses valid JSON with all v1 fields', () {
      final json = {
        'id': 'nyingma',
        'name': 'Ньингма',
        'version': '1.0.0',
        'tradition': 'vajrayana',
        'modules': ['calendar', 'tracker'],
        'moduleConfigs': {
          'calendar': {'type': 'tibetan', 'highlightDays': [10, 25]},
          'tracker': {'isolationTag': 'nyingma'},
        },
        'practices': [
          {
            'id': 'prostrations',
            'name': 'Простирания',
            'type': 'counter',
            'target': 100000,
            'unit': 'повторений',
          },
        ],
        'eventPacks': ['vajrayana_holidays'],
        'contentPacks': ['nyingma_quotes'],
        'description': 'Школа Ньингма',
      };

      final preset = PresetSchema.fromJson(json);

      expect(preset.id, 'nyingma');
      expect(preset.name, 'Ньингма');
      expect(preset.version, '1.0.0');
      expect(preset.tradition, 'vajrayana');
      expect(preset.modules, ['calendar', 'tracker']);
      expect(preset.moduleConfigs['calendar']?['type'], 'tibetan');
      expect(preset.moduleConfigs['tracker']?['isolationTag'], 'nyingma');
      expect(preset.practices, hasLength(1));
      expect(preset.practices.first.id, 'prostrations');
      expect(preset.practices.first.target, 100000);
      expect(preset.eventPacks, ['vajrayana_holidays']);
      expect(preset.contentPacks, ['nyingma_quotes']);
      expect(preset.description, 'Школа Ньингма');
    });

    test('toJson roundtrip preserves data', () {
      final original = PresetSchema(
        id: 'test',
        name: 'Тест',
        version: '2.0.0',
        tradition: 'theravada',
        modules: ['calendar'],
        moduleConfigs: {
          'calendar': {'type': 'lunar'},
        },
        practices: [
          PresetPractice(
            id: 'meditation',
            name: 'Медитация',
            type: 'timer',
            target: 30,
            unit: 'минут',
          ),
        ],
        eventPacks: ['theravada_uposatha'],
        contentPacks: [],
        description: 'Описание',
      );

      final json = original.toJson();
      final restored = PresetSchema.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.tradition, original.tradition);
      expect(restored.practices.first.id, 'meditation');
      expect(restored.practices.first.type, 'timer');
    });

    test('fromJson throws on missing required fields', () {
      final json = {
        'id': 'test',
        // Missing: name, version, tradition, modules, etc.
      };

      expect(() => PresetSchema.fromJson(json), throwsA(isA<TypeError>()));
    });

    test('PresetPractice fromJson/toJson works correctly', () {
      final json = {
        'id': 'vajrasattva',
        'name': 'Мантра Ваджрасаттвы',
        'type': 'counter',
        'target': 100000,
        'unit': 'повторений',
      };

      final practice = PresetPractice.fromJson(json);

      expect(practice.id, 'vajrasattva');
      expect(practice.name, 'Мантра Ваджрасаттвы');
      expect(practice.type, 'counter');
      expect(practice.target, 100000);
      expect(practice.unit, 'повторений');

      final restored = PresetPractice.fromJson(practice.toJson());
      expect(restored.id, practice.id);
      expect(restored.target, practice.target);
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
