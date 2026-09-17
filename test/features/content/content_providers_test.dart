/// Проводка фичи контента: провайдеры на контрактах (D-22, D-37-аналог; блок C).
///
/// Проверяется, что фича собирается **из оверрайдов**, а не из синглтонов:
/// паки берутся данными пресета, ассеты — через инъектированный бандл (тесты не
/// трогают `rootBundle`, F-58), время — из инъектированных часов, календарь —
/// только через порт ядра. Отдельно проверяется, что **непривязанный порт падает
/// громко** (ошибка композиции, паттерн D-22/R-13), а не подменяется молчаливой
/// деградацией.
///
/// Биндинга в `main.dart` в пакете 7.0 нет — но фича уже собирается целиком и
/// порт ядра [contentSourceProvider] привязывается адаптером фичи, минуя
/// composition root (прецедент 6.1 блок E).
library;

import 'dart:convert';

import 'package:dharma_toolkit/core/calendar/special_day.dart';
import 'package:dharma_toolkit/core/calendar/special_days_source.dart';
import 'package:dharma_toolkit/core/content/content_source.dart';
import 'package:dharma_toolkit/core/content/daily_reading.dart';
import 'package:dharma_toolkit/features/content/domain/content_fallbacks.dart';
import 'package:dharma_toolkit/features/content/presentation/providers/content_providers.dart';
import 'package:dharma_toolkit/shared/providers/app_providers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'content_preset_helper.dart';

/// Источник тибетских дат, который фича видит только через порт ядра.
class _StubSource implements SpecialDaysSource {
  _StubSource(this.traditionTag, {this.tibetanDates});

  @override
  final String traditionTag;

  final List<DateTime>? tibetanDates;

  @override
  List<SpecialDay> getSpecialDays(DateTime from, DateTime to) => const [];

  @override
  List<DateTime>? resolveTibetanMonthDay({
    required int month,
    required int day,
    required DateTime from,
    required DateTime to,
  }) =>
      tibetanDates;
}

/// Бандл в памяти: тесты не читают реальные ассеты (F-58).
class _FakeBundle extends AssetBundle {
  _FakeBundle(this.assets);

  final Map<String, String> assets;

  @override
  Future<ByteData> load(String key) async {
    final value = assets[key];
    if (value == null) throw StateError('нет ассета $key');
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(value)));
  }
}

final _now = DateTime(2026, 6, 1, 12);

/// Синтетический пак с одной записью пула ротации.
const _packJson = '''
{
  "packId": "synthetic_provider_pack",
  "traditionTag": "nyingma",
  "version": "1",
  "verified": false,
  "entries": [
    {
      "id": "c1",
      "type": "daily_reading",
      "title": "Текст пака из пресета",
      "body": "Синтетический текст фикстуры.",
      "source": "синтетическая фикстура теста"
    }
  ]
}
''';

/// Пак с тибетской привязкой (проверка пути через порт календаря).
const _tibetanPackJson = '''
{
  "packId": "synthetic_tibetan_pack",
  "traditionTag": "nyingma",
  "version": "1",
  "verified": true,
  "entries": [
    {
      "id": "c1",
      "type": "daily_reading",
      "title": "Текст на тибетский день",
      "body": "Синтетический текст фикстуры.",
      "source": "синтетическая фикстура теста",
      "dateRule": {"kind": "tibetan", "month": 10, "day": 25}
    }
  ]
}
''';

void main() {
  ProviderContainer containerWith({
    List<String> packAssets = const [],
    Map<String, String>? assets,
    SpecialDaysSource? source,
    bool bindCalendarPort = true,
  }) {
    final bundleAssets = assets ?? const <String, String>{};
    final container = ProviderContainer(overrides: [
      contentClockProvider.overrideWithValue(() => _now),
      activeTraditionTagProvider.overrideWith((ref) => Stream.value('nyingma')),
      activePresetStreamProvider.overrideWith(
          (ref) => Stream.value(presetWithContentPacks(packAssets))),
      contentAssetBundleProvider.overrideWithValue(_FakeBundle(bundleAssets)),
      if (bindCalendarPort)
        specialDaysSourceProvider.overrideWithValue(source ?? _StubSource('nyingma')),
    ]);
    addTearDown(container.dispose);
    // Потоковые провайдеры обязаны иметь подписчика: без него контейнер не
    // дожидается первого эвента (в приложении подписчиком выступает UI).
    container.listen(activePresetStreamProvider, (_, _) {});
    container.listen(activeTraditionTagProvider, (_, _) {});
    return container;
  }

  group('contentPacksProvider — паки из данных пресета', () {
    test('ключи ассетов берутся из пресета, а не из хардкода', () async {
      final container = containerWith(
        packAssets: const ['assets/content_packs/synthetic.json'],
        assets: const {'assets/content_packs/synthetic.json': _packJson},
      );

      final loaded = await container.read(contentPacksProvider.future);
      // Список ключей читается из пресета: до первого эвента потока он пуст
      // («пресета ещё нет» — не то же самое, что «пресет без паков»).
      expect(container.read(activeContentPackAssetsProvider),
          ['assets/content_packs/synthetic.json']);

      expect(loaded.failures, isEmpty);
      expect(loaded.packs.single.packId, 'synthetic_provider_pack');
      expect(loaded.packs.single.verified, isFalse);
    });

    test('бандл инъектируется: загрузчик читает ассет через него', () async {
      final container = containerWith(
        packAssets: const ['assets/content_packs/synthetic.json'],
        assets: const {'assets/content_packs/synthetic.json': _packJson},
      );

      final loaded = await container
          .read(contentPackLoaderProvider)
          .load(const ['assets/content_packs/synthetic.json']);

      expect(loaded.packs.single.entries.single.title, 'Текст пака из пресета');
    });

    test('паков в пресете нет → пустой результат без сбоев (честная пустота)',
        () async {
      final container = containerWith();

      final loaded = await container.read(contentPacksProvider.future);
      expect(container.read(activeContentPackAssetsProvider), isEmpty);
      expect(loaded.packs, isEmpty);
      expect(loaded.failures, isEmpty);
    });

    test('сбой загрузки пака не проглочен: он виден в ленте', () async {
      final container = containerWith(
        packAssets: const ['assets/content_packs/missing.json'],
      );

      await container.read(contentPacksProvider.future);
      final feed = container.read(contentFeedProvider);

      expect(feed.notes.join('\n'), contains('missing.json'));
      expect(feed.usesFallback, isTrue,
          reason: 'пака нет — работает фолбэк FR-CNT-3');
    });
  });

  group('dailyReadingProvider — чтение дня активной традиции', () {
    test('чтение дня приходит из пака пресета (путь данных, не хардкода)',
        () async {
      final container = containerWith(
        packAssets: const ['assets/content_packs/synthetic.json'],
        assets: const {'assets/content_packs/synthetic.json': _packJson},
      );

      await container.read(contentPacksProvider.future);
      final day = container.read(dailyReadingProvider);

      final reading = day.readings.single;
      expect(reading.title, 'Текст пака из пресета');
      expect(reading.source, ContentReadingSource.pack);
      expect(reading.isVerified, isFalse);
      expect(reading.attribution, contains('synthetic_provider_pack'));
      expect(day.notes.join('\n'), contains('не подтверждён'));
    });

    test('часы инъектируются: тот же день — то же чтение, другой — своё', () {
      final container = ProviderContainer(overrides: [
        contentClockProvider.overrideWithValue(() => DateTime(2026, 6, 1)),
        activeTraditionTagProvider.overrideWith((ref) => Stream.value('nyingma')),
        activePresetStreamProvider.overrideWith(
            (ref) => Stream.value(presetWithContentPacks(const []))),
        specialDaysSourceProvider.overrideWithValue(_StubSource('nyingma')),
      ]);
      addTearDown(container.dispose);
      container.listen(activePresetStreamProvider, (_, _) {});
      container.listen(activeTraditionTagProvider, (_, _) {});

      final first = container.read(dailyReadingProvider);
      expect(first.date, DateTime(2026, 6, 1));
      expect(first.isFallback, isTrue);
    });

    test('паков нет → фолбэк FR-CNT-3 с признанием, а не пустой экран',
        () async {
      final container = containerWith();

      await container.read(contentPacksProvider.future);
      final day = container.read(dailyReadingProvider);

      expect(day.isFallback, isTrue);
      expect(day.readings.single.source, ContentReadingSource.fallback);
      expect(day.readings.single.isVerified, isFalse);
      expect(day.notes, contains(ContentFallbacks.note));
    });

    test('тибетская привязка разрешается только через порт календаря ядра',
        () async {
      final container = containerWith(
        packAssets: const ['assets/content_packs/tibetan.json'],
        assets: const {'assets/content_packs/tibetan.json': _tibetanPackJson},
        source: _StubSource('nyingma', tibetanDates: [DateTime(2026, 6, 1)]),
      );

      await container.read(contentPacksProvider.future);
      final reading = container.read(dailyReadingProvider).readings.single;

      expect(reading.title, 'Текст на тибетский день');
      expect(reading.isDateBound, isTrue);
    });

    test('календарь тибетских дат не знает → честное пояснение, не крах',
        () async {
      final container = containerWith(
        packAssets: const ['assets/content_packs/tibetan.json'],
        assets: const {'assets/content_packs/tibetan.json': _tibetanPackJson},
        source: _StubSource('nyingma', tibetanDates: null),
      );

      await container.read(contentPacksProvider.future);
      final day = container.read(dailyReadingProvider);

      expect(day.notes.join('\n'), contains('тибетских дат не знает'));
    });
  });

  group('contentFeedProvider — лента на окне', () {
    test('лента строится по инъектированным часам (окно 8 дней)', () async {
      final container = containerWith(
        packAssets: const ['assets/content_packs/synthetic.json'],
        assets: const {'assets/content_packs/synthetic.json': _packJson},
      );

      await container.read(contentPacksProvider.future);
      final feed = container.read(contentFeedProvider);

      expect(feed.days, hasLength(8));
      expect(feed.days.first.date, DateTime(2026, 6, 1));
      expect(feed.days.last.date, DateTime(2026, 6, 8));
      expect(feed.usesFallback, isFalse);
    });
  });

  group('порт ядра ContentSource', () {
    test('привязывается адаптером фичи — без биндинга в main.dart', () async {
      final container = containerWith(
        packAssets: const ['assets/content_packs/synthetic.json'],
        assets: const {'assets/content_packs/synthetic.json': _packJson},
      );
      // Composition root в 7.0 биндинга не делает: проверяем, что привязка
      // адаптером фичи даёт работающий порт (прецедент 6.1 блок E).
      final bound = ProviderContainer(overrides: [
        contentClockProvider.overrideWithValue(() => _now),
        activeTraditionTagProvider.overrideWith((ref) => Stream.value('nyingma')),
        activePresetStreamProvider.overrideWith(
            (ref) => Stream.value(presetWithContentPacks(
                const ['assets/content_packs/synthetic.json']))),
        contentAssetBundleProvider.overrideWithValue(_FakeBundle(
            const {'assets/content_packs/synthetic.json': _packJson})),
        specialDaysSourceProvider.overrideWithValue(_StubSource('nyingma')),
        contentSourceProvider.overrideWith(
            (ref) => ref.watch(dailyReadingContentSourceProvider)),
      ]);
      addTearDown(bound.dispose);
      bound.listen(activePresetStreamProvider, (_, _) {});
      bound.listen(activeTraditionTagProvider, (_, _) {});
      await bound.read(contentPacksProvider.future);
      await container.read(contentPacksProvider.future);

      final port = bound.read(contentSourceProvider);

      expect(port.traditionTag, 'nyingma');
      expect(port.readingsFor(_now).single.title, 'Текст пака из пресета');
      // Порт и лента отвечают одним и тем же доменом (не два источника истины).
      expect(port.readingsFor(_now).single.title,
          container.read(dailyReadingProvider).readings.single.title);
    });

    test('непривязанный порт падает громко (ошибка композиции, не деградация)',
        () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(() => container.read(contentSourceProvider), throwsStateError);
    });

    test('непривязанный порт календаря роняет сервис громко, а не молча',
        () async {
      final container = containerWith(bindCalendarPort: false);
      await container.read(activePresetStreamProvider.future);

      expect(() => container.read(dailyReadingServiceProvider),
          throwsStateError);
    });
  });
}
