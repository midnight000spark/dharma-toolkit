/// Проводка фичи событий: провайдеры на контрактах (D-22, D-37; блок E).
///
/// Проверяется, что фича собирается **из оверрайдов**, а не из синглтонов:
/// лента берёт дни только через порт ядра, паки — через инъектированный
/// читатель, настройки — из инъектированной БД, а непривязанный планировщик
/// падает громко (паттерн D-22/R-13).
library;

import 'package:dharma_toolkit/core/calendar/special_day.dart';
import 'package:dharma_toolkit/core/calendar/special_days_source.dart';
import 'package:dharma_toolkit/core/db/app_database.dart';
import 'package:dharma_toolkit/features/events/data/event_pack_loader.dart';
import 'package:dharma_toolkit/features/events/domain/feed_entry.dart';
import 'package:dharma_toolkit/features/events/domain/notification_settings.dart';
import 'package:dharma_toolkit/features/events/presentation/providers/event_providers.dart';
import 'package:dharma_toolkit/shared/providers/app_providers.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'preset_helper.dart';

/// Источник особых дней, который фича видит через порт ядра.
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

final _now = DateTime(2026, 6, 1, 12);

/// Пресет с объявленным паком (данные, не хардкод фичи).
const _packJson = '''
{
  "packId": "synthetic_provider_pack",
  "traditionTag": "nyingma",
  "version": "1",
  "verified": false,
  "entries": [
    {
      "id": "e1",
      "type": "festival",
      "name": "Синтетическое событие пака",
      "dateRule": {"kind": "gregorian_yearly", "month": 6, "day": 3},
      "source": "синтетическая фикстура теста"
    }
  ]
}
''';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  ProviderContainer containerWith({
    List<String> packAssets = const [],
    SpecialDaysSource? source,
  }) {
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      eventsClockProvider.overrideWithValue(() => _now),
      activeTraditionTagProvider.overrideWith((ref) => Stream.value('nyingma')),
      activePresetStreamProvider.overrideWith(
          (ref) => Stream.value(presetWithEventPacks(packAssets))),
      specialDaysSourceProvider.overrideWithValue(source),
      eventPackLoaderProvider.overrideWithValue(
        EventPackLoader(
          readAsset: (key) async {
            if (key == 'assets/events/synthetic.json') return _packJson;
            throw StateError('нет ассета $key');
          },
        ),
      ),
    ]);
    addTearDown(container.dispose);
    // Потоковые провайдеры обязаны иметь подписчика: без него контейнер не
    // дожидается первого эвента (в приложении подписчиком выступает UI).
    container.listen(activePresetStreamProvider, (_, _) {});
    container.listen(activeTraditionTagProvider, (_, _) {});
    return container;
  }

  group('eventFeedProvider — сборка из порта ядра и паков пресета', () {
    test('дни календаря приходят через порт, паки — из пресета', () async {
      final container = containerWith(
        packAssets: const ['assets/events/synthetic.json'],
        source: _StubSource('nyingma', [
          SpecialDay(
            date: DateTime(2026, 6, 2),
            type: SpecialDayType.tibetan10,
            name: 'День календаря',
          ),
        ]),
      );

      // Дожидаемся загрузки паков (FutureProvider).
      await container.read(eventPacksProvider.future);
      final feed = container.read(eventFeedProvider);

      expect(feed.entries.map((e) => e.title),
          ['День календаря', 'Синтетическое событие пака']);
      expect(feed.entries.last.source, FeedEntrySource.pack);
      expect(feed.entries.last.isVerified, isFalse);
      expect(feed.notes.join('\n'), contains('не подтверждён'));
    });

    test('паков в пресете нет → лента без сбоев (честная пустота)', () async {
      final container = containerWith(source: _StubSource('nyingma', const []));

      expect(container.read(activeEventPackAssetsProvider), isEmpty);
      final result = await container.read(eventPacksProvider.future);
      expect(result.packs, isEmpty);
      expect(result.failures, isEmpty);
    });

    test('сбой загрузки пака виден в ленте, а не проглочен', () async {
      final container = containerWith(
        packAssets: const ['assets/events/missing.json'],
        source: _StubSource('nyingma', const []),
      );

      await container.read(eventPacksProvider.future);
      final feed = container.read(eventFeedProvider);

      expect(feed.entries, isEmpty);
      expect(feed.notes.join('\n'), contains('missing.json'));
    });

    test('календаря нет (порт привязан к null) → лента объясняет пустоту',
        () async {
      final container = containerWith(packAssets: const [], source: null);

      final feed = container.read(eventFeedProvider);
      expect(feed.entries, isEmpty);
      expect(feed.notes.join('\n'), contains('Календаря'));
    });
  });

  group('notificationPlanProvider — настройки и план', () {
    test('дефолт D-36: план включён, время 08:00', () async {
      final container = containerWith(
        source: _StubSource('nyingma', [
          SpecialDay(
            date: DateTime(2026, 6, 2),
            type: SpecialDayType.tibetan10,
            name: 'День календаря',
          ),
        ]),
      );

      await container.read(eventPacksProvider.future);
      final plan = container.read(notificationPlanProvider);

      expect(plan.items.single.scheduledAt, DateTime(2026, 6, 2, 8));
    });

    test('настройки из БД управляют планом, поток реактивен', () async {
      final container = containerWith(
        source: _StubSource('nyingma', [
          SpecialDay(
            date: DateTime(2026, 6, 2),
            type: SpecialDayType.tibetan10,
            name: 'День календаря',
          ),
        ]),
      );

      await container.read(eventPacksProvider.future);
      // Держим подписку на поток настроек живой (иначе он не обновит план).
      container.listen(notificationSettingsProvider, (_, _) {});
      await pumpEventQueue();
      expect(container.read(notificationPlanProvider).items, hasLength(1));

      // Выключаем уведомления в БД — план обязан опустеть (FR-EVT-3).
      final store = container.read(notificationSettingsStoreProvider);
      await store.write('nyingma',
          NotificationSettings(enabled: false, hour: 8, minute: 0));
      await pumpEventQueue();

      expect(
        container.read(notificationSettingsProvider).value,
        NotificationSettings(enabled: false, hour: 8, minute: 0),
      );
      expect(container.read(notificationPlanProvider).items, isEmpty);
    });

    test('без активной традиции — дефолт настроек, не исключение', () async {
      final container = ProviderContainer(overrides: [
        appDatabaseProvider.overrideWithValue(db),
        eventsClockProvider.overrideWithValue(() => _now),
        activeTraditionTagProvider.overrideWith((ref) => const Stream.empty()),
        specialDaysSourceProvider.overrideWithValue(null),
      ]);
      addTearDown(container.dispose);

      container.listen(notificationSettingsProvider, (_, _) {});
      expect(await container.read(notificationSettingsProvider.future),
          NotificationSettings.defaults);
    });
  });

  group('порт планировщика (D-34)', () {
    test('не привязан → StateError с указанием пакета-владельца', () {
      final container = containerWith();

      expect(
        () => container.read(notificationSchedulerProvider),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', contains('6.2'))),
      );
    });
  });
}
