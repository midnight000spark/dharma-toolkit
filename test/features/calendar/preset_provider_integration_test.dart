/// Интеграция «пресет → провайдер → особые дни» (5b.4 блок 4, R-3/R-21/D-32).
///
/// Идёт по пользовательскому пути: реальные JSON-пресеты из ассетов
/// (ConfigModule + rootBundle, F-11) → applyPreset → реактивная связка
/// активного пресета и выбора календаря (5b.4) → дни. Проверяет сразу
/// всё: схему пресета после удаления мёртвых полей (R-20/D-32), выбор по
/// тегу (D-32), проводку потока (R-21) и то, что выбранная реализация
/// держит контракт CalendarProvider (5b.1) на реальных данных традиции.
///
/// Детерминизм — уровень контейнера без виджетов (урок 5).
library;

import 'package:dharma_toolkit/core/config/config_module.dart';
import 'package:dharma_toolkit/core/config/preset_manager.dart';
import 'package:dharma_toolkit/core/config/preset_schema.dart';
import 'package:dharma_toolkit/core/db/app_database.dart';
import 'package:dharma_toolkit/features/calendar/domain/calendar_provider.dart';
import 'package:dharma_toolkit/core/storage/storage_module.dart';
import 'package:dharma_toolkit/features/calendar/data/tibetan/tibetan_calendar_provider.dart';
import 'package:dharma_toolkit/features/calendar/data/uposatha/uposatha_calendar_provider.dart';
import 'package:dharma_toolkit/features/calendar/domain/special_day.dart';
import 'package:dharma_toolkit/features/calendar/presentation/providers/calendar_providers.dart';
import 'package:dharma_toolkit/shared/providers/app_providers.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'contract_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late StorageModule storage;
  late PresetManager manager;
  late ConfigModule config;
  late ProviderContainer container;

  setUpAll(() async {
    // Реальные ассеты пресетов (путь 5.0.2: index.json → presets/<id>.json).
    config = ConfigModule();
    await config.init();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    database = AppDatabase.forTesting(
      NativeDatabase.memory(setup: enableForeignKeys),
    );
    storage = StorageModule();
    await storage.init();
    manager = PresetManager(() => database, storage);
    await manager.init();
    container = ProviderContainer(
      overrides: [presetManagerProvider.overrideWithValue(manager)],
    );
    container.listen(activeTraditionTagProvider, (_, _) {});
  });

  tearDown(() async {
    container.dispose();
    await database.close();
    try {
      await storage.dispose();
    } catch (_) {}
  });

  Future<void> settleTag(String expected) async {
    for (var i = 0; i < 50; i++) {
      if (container.read(activeTraditionTagProvider).value == expected) return;
      await Future<void>.delayed(Duration.zero);
    }
    fail('тег не стал "$expected"');
  }

  /// Ждём ожидаемый тег и возвращаем выбранный календарь. Явное ожидание
  /// вместо «сверить с текущим» — иначе после switchPreset helper мог бы
  /// увидеть ещё старый тег и провалить гонку в тест (урок 5).
  Future<CalendarProvider?> settledCal(String expectedTag) async {
    await settleTag(expectedTag);
    return container.read(activeCalendarProviderProvider);
  }

  group('пресет → провайдер → свои особые дни', () {
    test('Ньингма (ассет nyingma.json): 10/25 и Лосар на окне 2026',
        () async {
      await manager.applyPreset(config.getPreset('nyingma')!);
      final cal = await settledCal('nyingma');

      expect(cal, isA<TibetanCalendarProvider>());
      expect(cal!.traditionTag, 'nyingma');

      // Контракт CalendarProvider на выбранной реализации + реальном окне.
      expectCalendarContract(cal, DateTime(2026, 1, 1), DateTime(2026, 12, 31));

      final days = cal.getSpecialDays(DateTime(2026, 1, 1), DateTime(2026, 12, 31));
      final types = days.map((d) => d.type).toSet();
      expect(types, containsAll(<SpecialDayType>[
        SpecialDayType.tibetan10,
        SpecialDayType.tibetan25,
        SpecialDayType.festival,
      ]), reason: 'годовое окно тибетской традиции обязано дать 10-е, '
          '25-е дни и как минимум один праздник');

      // Якорь F-45: Лосар-2026 = 18 февраля.
      final losar = days
          .where((d) => d.type == SpecialDayType.festival)
          .map((d) => d.date)
          .toList();
      expect(losar, contains(DateTime(2026, 2, 18)),
          reason: 'Лосар 2026 (вектор F-45) обязан прийти через пресет');
      // Упосатх у тибетской традиции быть не должно — не подмешивается.
      expect(types, isNot(contains(SpecialDayType.uposatha)));
    });

    test('Тхеравада (ассет theravada_default.json): упосатхи, без 10/25',
        () async {
      await manager.applyPreset(config.getPreset('theravada_default')!);
      final cal = await settledCal('theravada_default');

      expect(cal, isA<UposathaCalendarProvider>());
      expect(cal!.traditionTag, 'theravada_default');

      expectCalendarContract(cal, DateTime(2026, 2, 1), DateTime(2026, 3, 31));
      final days =
          cal.getSpecialDays(DateTime(2026, 2, 1), DateTime(2026, 3, 31));
      expect(days, isNotEmpty);
      expect(days.every((d) => d.type == SpecialDayType.uposatha), isTrue,
          reason: 'лунная традиция даёт только упосатхи');
      // Четыре фазы × ~1.5 месяца → от 6 до 10 упосатх на окно.
      expect(days.length, inInclusiveRange(6, 10));
    });

    test('переключение в живом контейнере меняет и дни (R-21 + R-3)',
        () async {
      await manager.applyPreset(config.getPreset('nyingma')!);
      await settledCal('nyingma');
      await manager.switchPreset(config.getPreset('theravada_default')!);
      final cal = await settledCal('theravada_default');
      expect(cal, isA<UposathaCalendarProvider>());

      // Тибетских подсветок в выбранном календаре нет — конфликт
      // традиций через абстраструкцию по активному пресету (митигация R-3).
      final days =
          cal!.getSpecialDays(DateTime(2026, 2, 1), DateTime(2026, 2, 28));
      expect(days.any((d) => d.type == SpecialDayType.tibetan10), isFalse);
      expect(days.any((d) => d.type == SpecialDayType.tibetan25), isFalse);
    });

    test('незарегистрированная традиция: null, без падения и чужих дней',
        () async {
      // Пользовательский пресет (не из манифеста) — та же судьба, что у
      // будущей школы до добавления строки в реестр: календаря нет.
      final custom = PresetSchema(
        id: 'my_custom_set',
        name: 'Мой набор',
        version: '1.0.0',
        modules: const ['calendar', 'tracker'],
        tradition: 'mahayana',
        practices: const [],
        eventPacks: const [],
        contentPacks: const [],
      );
      await manager.applyPreset(custom);
      final cal = await settledCal('my_custom_set');

      expect(cal, isNull,
          reason: 'честная деградация: не падение и не молчаливый чужой '
              'календарь (UI SCR-11 покажет «нет календаря для традиции»)');
    });

    test('reset — календаря и тега нет', () async {
      await manager.applyPreset(config.getPreset('nyingma')!);
      await settledCal('nyingma');
      await manager.resetPreset();
      await settleTag('');
      expect(container.read(activeCalendarProviderProvider), isNull);
    });
  });
}
