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

      expect(() => PresetSchema.fromJson(json),
          throwsA(isA<PresetValidationException>()));
    });

    // 6.3: имя проблемного поля обязано быть в сообщении — по нему чинят
    // кривой JSON-пресет.
    group('PresetSchema.fromJson: валидация с именем поля (6.3)', () {
      PresetSchema valid() => PresetSchema(
            id: 'x',
            name: 'X',
            version: '1.0.0',
            modules: const [],
            tradition: 'vajrayana',
            moduleConfigs: const {},
            practices: const [],
            eventPacks: const [],
            contentPacks: const [],
          );

      Map<String, dynamic> broken(void Function(Map<String, dynamic>) tweak) {
        final json = valid().toJson();
        tweak(json);
        return json;
      }

      void expectField(void Function() action, String field) {
        expect(
          action,
          throwsA(
            isA<PresetValidationException>().having(
                (e) => e.field, 'в сообщении имя поля', field),
          ),
        );
      }

      test('отсутствующий name → поле name', () {
        expectField(
          () => PresetSchema.fromJson(broken((j) => j.remove('name'))),
          'name',
        );
      });

      test('немассивный modules → поле modules', () {
        expectField(
          () => PresetSchema.fromJson(broken((j) => j['modules'] = 5)),
          'modules',
        );
      });

      test('мусор вместо практики → practices[0]', () {
        expectField(
          () => PresetSchema.fromJson(
              broken((j) => j['practices'] = ['не объект'])),
          'practices[0]',
        );
      });

      test('практика без id → practices[0].id', () {
        expectField(
          () => PresetSchema.fromJson(broken((j) => j['practices'] = [
                {'name': 'Без айди', 'type': 'counter'}
              ])),
          'practices[0].id',
        );
      });

      test('некорректная цель практики → practices[0].target', () {
        expectField(
          () => PresetSchema.fromJson(broken((j) => j['practices'] = [
                {
                  'id': 'p',
                  'name': 'П',
                  'type': 'counter',
                  'target': 'сто'
                }
              ])),
          'practices[0].target',
        );
      });

      test('валидный сериализованный пресет проходит валидацию', () {
        final restored = PresetSchema.fromJson(valid().toJson());
        expect(restored.id, 'x');
      });
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
