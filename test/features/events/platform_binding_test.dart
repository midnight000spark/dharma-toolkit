/// Проводка портов в composition root (блок D пакета 6.2).
///
/// Проверяется именно **связка**, а не классы по отдельности: тест вызывает ту
/// же функцию `platformPortOverrides`, что и `main()`/`start()`, и требует,
/// чтобы порты ядра (источник особых дней, планировщик) были привязаны, а без
/// проводки — падали громко (StateError), а не молча отдавали пустоту
/// (мутация «убрал оверрайд» обязана красить тест, урок 1).
///
/// Здесь же — сквозной сценарий смены традиции: он подтверждает, что план
/// напоминаний строится по **текущему** пресету, а не по значениям реактивного
/// слоя, который к моменту события ещё не переключился (иначе после смены
/// традиции напоминания оставались бы от покинутой).
library;

import 'dart:async';

import 'package:dharma_toolkit/core/calendar/special_day.dart';
import 'package:dharma_toolkit/core/calendar/special_days_source.dart';
import 'package:dharma_toolkit/core/config/preset_manager.dart';
import 'package:dharma_toolkit/core/config/preset_schema.dart';
import 'package:dharma_toolkit/core/db/app_database.dart';
import 'package:dharma_toolkit/core/events/event_bus.dart';
import 'package:dharma_toolkit/core/events/event_bus_provider.dart';
import 'package:dharma_toolkit/core/storage/storage_module.dart';
import 'package:dharma_toolkit/features/calendar/data/calendar_special_days_source.dart';
import 'package:dharma_toolkit/features/calendar/presentation/providers/calendar_providers.dart';
import 'package:dharma_toolkit/features/events/domain/notification_scheduler.dart';
import 'package:dharma_toolkit/features/events/domain/notification_settings.dart';
import 'package:dharma_toolkit/features/events/presentation/providers/event_providers.dart';
import 'package:dharma_toolkit/main.dart';
import 'package:dharma_toolkit/shared/providers/app_providers.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'in_memory_notification_scheduler.dart';

/// Источник дней, отдающий заранее заданные особые дни своего тега.
class _StubSource implements SpecialDaysSource {
  _StubSource(this.traditionTag, this.days);

  @override
  final String traditionTag;
  final List<SpecialDay> days;

  @override
  List<SpecialDay> getSpecialDays(DateTime from, DateTime to) => [
        for (final d in days)
          if (!d.date.isBefore(from) && !d.date.isAfter(to)) d,
      ];

  @override
  List<DateTime>? resolveTibetanMonthDay({
    required int month,
    required int day,
    required DateTime from,
    required DateTime to,
  }) =>
      null;
}

PresetSchema preset(String id, String name) => PresetSchema(
      id: id,
      name: name,
      version: '1.0.0',
      modules: const ['calendar'],
      tradition: 'vajrayana',
      practices: const [],
      eventPacks: const [],
      contentPacks: const [],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('platformPortOverrides — порты привязаны композиционным корнем', () {
    ProviderContainer containerWith(NotificationScheduler scheduler) {
      final container = ProviderContainer(overrides: [
        activeTraditionTagProvider
            .overrideWith((ref) => Stream.value('nyingma')),
        ...platformPortOverrides(scheduler: scheduler),
      ]);
      addTearDown(container.dispose);
      container.listen(activeTraditionTagProvider, (_, _) {});
      container.listen(specialDaysSourceProvider, (_, _) {});
      return container;
    }

    test('планировщик и источник дней активной традиции приходят из оверрайдов',
        () async {
      final scheduler = InMemoryNotificationScheduler();
      final container = containerWith(scheduler);
      // Первое значение потокового провайдера приходит асинхронно: до него
      // «активной традиции нет» — это и есть честная деградация, а не ошибка.
      await pumpEventQueue();

      expect(container.read(notificationSchedulerProvider), same(scheduler));
      expect(container.read(specialDaysSourceProvider),
          isA<CalendarSpecialDaysSource>());
      expect(container.read(specialDaysSourceProvider)!.traditionTag, 'nyingma');
    });

    test('источник дней доступен и по явному тегу; неизвестный тег — null',
        () async {
      final container = containerWith(InMemoryNotificationScheduler());
      await pumpEventQueue();

      expect(container.read(specialDaysSourceForTagProvider('nyingma')),
          isA<CalendarSpecialDaysSource>());
      expect(
          container.read(specialDaysSourceForTagProvider('unknown_tag')), isNull);
    });

    test('без оверрайдов порты падают громко, а не отдают пустоту', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(() => container.read(specialDaysSourceProvider),
          throwsA(isA<StateError>()));
      expect(() => container.read(specialDaysSourceForTagProvider('nyingma')),
          throwsA(isA<StateError>()));
      expect(() => container.read(notificationSchedulerProvider),
          throwsA(isA<StateError>()));
    });

    test('смена тега переключает источник дней без перезапуска', () async {
      final tags = StreamController<String>();
      addTearDown(tags.close);
      final container = ProviderContainer(overrides: [
        activeTraditionTagProvider.overrideWith((ref) => tags.stream),
      ]);
      addTearDown(container.dispose);
      container.listen(activeSpecialDaysSourceProvider, (_, _) {});

      tags.add('nyingma');
      await pumpEventQueue();
      expect(container.read(activeSpecialDaysSourceProvider)!.traditionTag,
          'nyingma');

      tags.add('theravada_default');
      await pumpEventQueue();
      final theravada = container.read(activeSpecialDaysSourceProvider)!;
      expect(theravada.traditionTag, 'theravada_default');
      // Лунный календарь тибетских дат не знает — честный отказ (F-59).
      expect(
        theravada.resolveTibetanMonthDay(
            month: 1, day: 10, from: DateTime(2026), to: DateTime(2027)),
        isNull,
      );

      tags.add('');
      await pumpEventQueue();
      expect(container.read(activeSpecialDaysSourceProvider), isNull);
    });
  });

  group('смена традиции: напоминания перепланируются по текущему пресету', () {
    late AppDatabase db;
    late StorageModule storage;
    late PresetManager presetManager;
    late EventBus bus;
    late InMemoryNotificationScheduler scheduler;
    late ProviderContainer container;

    final nyingmaDay = SpecialDay(
      date: DateTime(2026, 6, 2),
      type: SpecialDayType.tibetan10,
      name: 'День традиции A',
    );
    final theravadaDay = SpecialDay(
      date: DateTime(2026, 6, 5),
      type: SpecialDayType.uposatha,
      name: 'День традиции B',
    );

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase.forTesting(NativeDatabase.memory());
      storage = StorageModule();
      await storage.init();
      bus = EventBus();
      presetManager = PresetManager(() => db, storage, eventBus: bus);
      await presetManager.init();
      scheduler = InMemoryNotificationScheduler();

      container = ProviderContainer(overrides: [
        appDatabaseProvider.overrideWithValue(db),
        presetManagerProvider.overrideWithValue(presetManager),
        eventBusProvider.overrideWithValue(bus),
        eventsClockProvider.overrideWithValue(() => DateTime(2026, 6, 1, 12)),
        specialDaysSourceForTagProvider.overrideWith((ref, tag) {
          switch (tag) {
            case 'nyingma':
              return _StubSource('nyingma', [nyingmaDay]);
            case 'theravada_default':
              return _StubSource('theravada_default', [theravadaDay]);
            default:
              return null;
          }
        }),
        notificationSchedulerProvider.overrideWithValue(scheduler),
      ]);
      addTearDown(container.dispose);
      addTearDown(() async {
        await storage.dispose();
        await db.close();
        bus.dispose();
      });
    });

    test('смена пресета снимает напоминания покинутой традиции', () async {
      await presetManager.applyPreset(preset('nyingma', 'Ньингма'));
      final replanner = container.read(notificationReplannerProvider);
      replanner.start();
      await replanner.settled;

      expect(scheduler.scheduled.values.single.title, 'День традиции A');
      expect(scheduler.scheduled.values.single.scheduledAt,
          DateTime(2026, 6, 2, 8));

      await presetManager
          .applyPreset(preset('theravada_default', 'Тхеравада'));
      // Событие доезжает до подписчика микротаском шины, и только затем
      // отрабатывает очередь перепланирований.
      await pumpEventQueue();
      await replanner.settled;

      expect(scheduler.scheduled.keys.toList(), [100000]);
      expect(scheduler.scheduled.values.single.title, 'День традиции B');
      expect(scheduler.scheduled.values.single.scheduledAt,
          DateTime(2026, 6, 5, 8));
    });

    test('настройки традиции управляют планом после смены пресета', () async {
      await presetManager.applyPreset(preset('nyingma', 'Ньингма'));
      final replanner = container.read(notificationReplannerProvider);
      replanner.start();
      await replanner.settled;

      // Пишем настройки НЕ той традиции, чей пресет активен: план обязан
      // остаться прежним (изоляция данных, принцип №3).
      await container
          .read(notificationSettingsStoreProvider)
          .write('theravada_default',
              NotificationSettings(enabled: false, hour: 8, minute: 0));
      await pumpEventQueue();
      await replanner.settled;
      expect(scheduler.scheduled, hasLength(1));

      // Выключаем активную традицию — напоминания снимаются полностью.
      await container
          .read(notificationSettingsStoreProvider)
          .write('nyingma',
              NotificationSettings(enabled: false, hour: 8, minute: 0));
      await pumpEventQueue();
      await replanner.settled;
      expect(scheduler.scheduled, isEmpty);
    });
  });
}
