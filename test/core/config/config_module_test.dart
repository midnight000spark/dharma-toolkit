import 'dart:convert';

import 'package:dharma_toolkit/core/config/config_module.dart';
import 'package:dharma_toolkit/core/config/preset_schema.dart';
import 'package:dharma_toolkit/core/module/app_module.dart';
import 'package:dharma_toolkit/core/module/module_registry.dart';
import 'package:dharma_toolkit/core/recovery/startup.dart';
import 'package:flutter/services.dart'
    show ByteData, Uint8List, rootBundle;
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('PresetSchema', () {
    test('fromJson parses valid JSON without moduleConfigs (R-20)', () {
      final json = {
        'id': 'nyingma',
        'name': 'Ньингма',
        'version': '1.0.0',
        'tradition': 'vajrayana',
        'modules': ['calendar', 'tracker'],
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
      expect(preset.practices, hasLength(1));
      expect(preset.practices.first.id, 'prostrations');
      expect(preset.practices.first.target, 100000);
      expect(preset.eventPacks, ['vajrayana_holidays']);
      expect(preset.contentPacks, ['nyingma_quotes']);
      expect(preset.description, 'Школа Ньингма');
    });

    // R-20 (D-32): легаси-строки в таблице presets хранят JSON, записанный
    // до 5b.4, — с ключом moduleConfigs. Разбор обязан игнорировать
    // неизвестные поля, иначе сохранённые пресеты перестанут читаться.
    test('легаси-JSON с moduleConfigs парсится — неизвестный ключ игнорируется',
        () {
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
        'practices': <Object>[],
        'eventPacks': <String>[],
        'contentPacks': <String>[],
      };

      final preset = PresetSchema.fromJson(json);
      expect(preset.id, 'nyingma');
      expect(preset.tradition, 'vajrayana');
      // toJson() нового поля не отдаёт — второй источник истины не возродится.
      expect(preset.toJson().containsKey('moduleConfigs'), isFalse);
    });

    test('toJson roundtrip preserves data', () {
      final original = PresetSchema(
        id: 'test',
        name: 'Тест',
        version: '2.0.0',
        tradition: 'theravada',
        modules: ['calendar'],
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

  group('target практики (B-24)', () {
    Map<String, dynamic> practiceJson(Object? target) => {
          'id': 'p',
          'name': 'Практика',
          'type': 'counter',
          'target': target,
          'unit': 'раз',
        };

    test('отрицательная цель отклоняется на границе домена', () {
      expect(
        () => PresetPractice.fromJson(practiceJson(-5)),
        throwsA(isA<PresetValidationException>()
            .having((e) => e.field, 'поле', 'target')),
      );
    });

    test('нулевая цель отклоняется (не «ноль прогресса», а бессмыслица)', () {
      expect(
        () => PresetPractice.fromJson(practiceJson(0)),
        throwsA(isA<PresetValidationException>()),
      );
    });

    test('положительная цель принимается', () {
      expect(PresetPractice.fromJson(practiceJson(1)).target, 1);
      expect(PresetPractice.fromJson(practiceJson(100000)).target, 100000);
    });

    test('null-цель по-прежнему допустима (цель не задана)', () {
      expect(PresetPractice.fromJson(practiceJson(null)).target, isNull);
    });

    test('через PresetSchema поле называется practices[0].target', () {
      final json = {
        'id': 'x',
        'name': 'X',
        'version': '1.0.0',
        'tradition': 'vajrayana',
        'modules': <String>[],
        'practices': [practiceJson(-1)],
        'eventPacks': <String>[],
        'contentPacks': <String>[],
      };

      expect(
        () => PresetSchema.fromJson(json),
        throwsA(isA<PresetValidationException>()
            .having((e) => e.field, 'поле', 'practices[0].target')),
      );
    });
  });

  group('presets/tree.json (B-18)', () {
    test('мёртвый узел custom несёт указатель на владельца-этап', () async {
      final json = jsonDecode(await rootBundle.loadString('presets/tree.json'))
          as Map<String, dynamic>;
      final custom = json['custom'] as Map<String, dynamic>;

      // Политика отложенных намерений (v2.12): мёртвые данные без владельца
      // теряются. Узел не читается кодом сегодня — значит, обязан нести
      // ссылку на запись-владельца в плане.
      expect(custom['_plan'], isNotNull,
          reason: 'B-18: у отложенного узла обязан быть владелец');
      expect(custom['_plan'], contains('plan-8'));
      // Узел остаётся инертным: сам он в дерево традиций не попадает.
      final traditions = (json['traditions'] as List).cast<Map<String, dynamic>>();
      expect(traditions.any((t) => t['id'] == 'custom'), isFalse);
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

  // C1(1): путь старта обязан различать «битый один элемент» и «подсистема не
  // работает» — пофайловый сбой уже честен в EventPackLoader/ContentPackLoader.
  // Ассеты подаются мок-обработчиком канала flutter/assets: реальные файлы
  // сборки подделать нельзя, а молчаливая деградация проверяется именно на
  // границе «один файл бракованный».
  group('C1(1): пофайловый отказ конфигурации', () {
    const goodPreset = '{"id":"good","name":"Хороший","version":"1.0.0",'
        '"tradition":"vajrayana","modules":["tracker"],"practices":[],'
        '"eventPacks":[],"contentPacks":[]}';
    const tree = '{"traditions":[{"id":"vajrayana","name":"Ваджраяна",'
        '"presets":["good"]}]}';

    void serveAssets(Map<String, String> files) {
      // Кэш rootBundle глобален на isolate файла: предыдущие тесты уже
      // прочитали настоящий presets/tree.json, и без очистки мок его бы не
      // перезаписал.
      rootBundle.clear();
      final messenger = TestDefaultBinaryMessengerBinding.instance
          .defaultBinaryMessenger;
      messenger.setMockMessageHandler('flutter/assets',
          (ByteData? message) async {
        final key = utf8.decode(message!.buffer.asUint8List());
        final content = files[key];
        if (content == null) return null;
        final bytes = utf8.encode(content);
        return ByteData.sublistView(Uint8List.fromList(bytes));
      });
      addTearDown(() {
        messenger.setMockMessageHandler('flutter/assets', null);
        // Корневой bundle кэширует строки: без очистки следующий тест в этом
        // же файле увидел бы мок вместо настоящего ассета.
        rootBundle.clear();
      });
    }

    test('битый presets/broken.json пропускается, остальные загружены',
        () async {
      serveAssets({
        'presets/index.json': '{"presets":["good","broken"]}',
        'presets/good.json': goodPreset,
        'presets/broken.json': '{"id":"broken"',
        'presets/tree.json': tree,
      });

      final module = ConfigModule();
      await module.init();

      expect(module.availablePresetIds, contains('good'),
          reason: 'один бракованный файл не имеет права валить загрузку всех');
      expect(module.allPresets, hasLength(1));
      expect(module.tree, hasLength(1));
      expect(module.ownFailures.single.kind, FailureKind.presetAssetSkipped);
      expect(module.ownFailures.single.subject, 'presets/broken.json');
    });

    test('битый манифест остаётся фатальным — «ни одного пресета» не тихий успех',
        () async {
      serveAssets({
        'presets/index.json': 'не json',
        'presets/tree.json': tree,
      });

      final module = ConfigModule();

      await expectLater(module.init(), throwsA(isA<StateError>()));
      expect(module.ownFailures, isEmpty,
          reason: 'отказ всей подсистемы — не пофайловая деградация');
    });

    test('доклад доходит до StartupOutcome.degradedModules', () async {
      serveAssets({
        'presets/index.json': '{"presets":["broken1","broken2"]}',
        'presets/broken1.json': ' битый ',
        'presets/broken2.json': '{"id":',
        'presets/tree.json': tree,
      });

      final registry = ModuleRegistry.instance;
      await registry.disposeAll();
      addTearDown(registry.disposeAll);
      registry.register(ConfigModule());

      final outcome = await bootstrapModules(registry);

      expect(outcome.ok, isTrue,
          reason: 'config пережил пофайловые отказы сам (C1)');
      expect(outcome.degradedModules, hasLength(2));
      expect(
        outcome.degradedModules.map((f) => f.subject),
        ['presets/broken1.json', 'presets/broken2.json'],
      );
      expect(
        outcome.degradedModules.every((f) => f.kind == FailureKind.presetAssetSkipped),
        isTrue,
      );
    });
  });
}
