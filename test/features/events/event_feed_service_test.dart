/// Лента событий: слияние, атрибуция, окно и честные отказы (блок C пакета 6.1).
///
/// Проверяется доменное поведение, а не отрисовка: слияние календаря и паков,
/// сортировка, совпадение дня у двух источников, границы окна и — отдельно —
/// что «нечего показать»/«не могу вычислить» не превращается в тихую пустоту
/// (SCR-12), но и не роняет ленту исключением.
library;

import 'package:dharma_toolkit/core/calendar/special_day.dart';
import 'package:dharma_toolkit/core/calendar/special_days_source.dart';
import 'package:dharma_toolkit/features/events/data/event_pack_loader.dart';
import 'package:dharma_toolkit/features/events/domain/event_feed.dart';
import 'package:dharma_toolkit/features/events/domain/event_feed_service.dart';
import 'package:dharma_toolkit/features/events/domain/event_pack.dart';
import 'package:dharma_toolkit/features/events/domain/feed_entry.dart';
import 'package:flutter_test/flutter_test.dart';

/// Источник-заглушка: отдаёт заданные дни и/или заданный ответ по правилу
/// `tibetan` (в том числе «не умею» — null).
class _StubSource implements SpecialDaysSource {
  _StubSource(
    this.traditionTag, {
    this.days = const [],
    this.tibetanDates,
  });

  @override
  final String traditionTag;

  final List<SpecialDay> days;
  final List<DateTime>? tibetanDates;

  /// Сколько раз спросили про правило tibetan (страх от «спросили и забыли»).
  int tibetanCalls = 0;

  @override
  List<SpecialDay> getSpecialDays(DateTime from, DateTime to) => days;

  @override
  List<DateTime>? resolveTibetanMonthDay({
    required int month,
    required int day,
    required DateTime from,
    required DateTime to,
  }) {
    tibetanCalls++;
    return tibetanDates;
  }
}

EventPack packOf({
  String packId = 'p',
  String traditionTag = 'nyingma',
  bool verified = true,
  required List<EventPackEntry> entries,
}) =>
    EventPack(
      packId: packId,
      traditionTag: traditionTag,
      version: '1',
      verified: verified,
      entries: entries,
    );

EventPackEntry entryOf({
  String id = 'e1',
  String name = 'Синтетическое событие',
  EventDateRule? rule,
  String source = 'синтетическая фикстура теста',
}) =>
    EventPackEntry(
      id: id,
      type: 'festival',
      name: name,
      source: source,
      dateRule: rule ?? const TibetanDateRule(month: 1, day: 1),
    );

final _today = DateTime(2026, 6, 1);

void main() {
  group('EventFeedService — слияние и атрибуция', () {
    test('пусто: нет календаря и нет паков → пустая лента, не исключение', () {
      final feed = EventFeedService(
        traditionTag: 'nyingma',
        source: null,
        packs: const [],
      ).build(today: _today);

      expect(feed.isEmpty, isTrue);
      expect(feed.entries, isEmpty);
      // Пустота объяснима: пользователь видит причину, а не «всё тихо».
      expect(feed.notes, isNotEmpty);
      expect(feed.notes.single, contains('Календаря'));
    });

    test('упосатха календаря и праздник пака в один день — обе записи, '
        'разные источники', () {
      final day = DateTime(2026, 6, 5);
      final source = _StubSource('theravada_default', days: [
        SpecialDay(
            date: day, type: SpecialDayType.uposatha, name: 'Упосатха'),
      ]);
      final pack = packOf(
        traditionTag: 'theravada_default',
        entries: [
          entryOf(
            id: 'synthetic_festival',
            name: 'Синтетический праздник',
            rule: const GregorianYearlyDateRule(month: 6, day: 5),
          ),
        ],
      );

      final feed = EventFeedService(
        traditionTag: 'theravada_default',
        source: source,
        packs: [pack],
      ).build(today: _today);

      expect(feed.entries, hasLength(2));
      final onDay = feed.on(day);
      expect(onDay, hasLength(2));
      expect(onDay.map((e) => e.source).toSet(),
          {FeedEntrySource.calendar, FeedEntrySource.pack});
      expect(onDay.first.attribution, contains('theravada_default'));
      expect(onDay.last.attribution, contains('пак «p»'));
      expect(onDay.last.attribution, contains('синтетическая фикстура теста'));
    });

    test('записи разных источников одного дня не схлопываются и не теряются',
        () {
      final day = DateTime(2026, 6, 5);
      final source = _StubSource('nyingma', days: [
        SpecialDay(
            date: day, type: SpecialDayType.festival, name: 'Одноимённый день'),
      ]);
      final pack = packOf(entries: [
        entryOf(name: 'Одноимённый день',
            rule: const GregorianYearlyDateRule(month: 6, day: 5)),
      ]);

      final feed = EventFeedService(
        traditionTag: 'nyingma',
        source: source,
        packs: [pack],
      ).build(today: _today);

      expect(feed.on(day), hasLength(2),
          reason: 'схлопывание потеряло бы атрибуцию источника');
    });
  });

  group('EventFeedService — правила дат', () {
    test('gregorian_yearly: дата в окне попадает, вне окна — нет', () {
      final pack = packOf(entries: [
        entryOf(
            id: 'in',
            name: 'В окне',
            rule: const GregorianYearlyDateRule(month: 6, day: 20)),
        entryOf(
            id: 'out',
            name: 'Вне окна',
            rule: const GregorianYearlyDateRule(month: 8, day: 1)),
      ]);
      final feed = EventFeedService(
        traditionTag: 'nyingma',
        source: _StubSource('nyingma'),
        packs: [pack],
      ).build(today: _today);

      expect(feed.entries.map((e) => e.title), ['В окне']);
    });

    test('gregorian_yearly на стыке года: оба года просматриваются', () {
      final pack = packOf(entries: [
        entryOf(
            id: 'newyear',
            name: 'Новогодняя дата',
            rule: const GregorianYearlyDateRule(month: 1, day: 3)),
      ]);
      final feed = EventFeedService(
        traditionTag: 'nyingma',
        source: _StubSource('nyingma'),
        packs: [pack],
      ).build(today: DateTime(2026, 12, 20));

      expect(feed.entries.single.date, DateTime(2027, 1, 3));
    });

    test('tibetan: дата берётся у порта, а не выдумывается', () {
      final resolved = DateTime(2026, 6, 9);
      final source = _StubSource('nyingma', tibetanDates: [resolved]);
      final pack = packOf(entries: [
        entryOf(rule: const TibetanDateRule(month: 4, day: 15)),
      ]);

      final feed = EventFeedService(
        traditionTag: 'nyingma',
        source: source,
        packs: [pack],
      ).build(today: _today);

      expect(source.tibetanCalls, 1);
      expect(feed.entries.single.date, resolved);
      expect(feed.entries.single.isVerified, isTrue);
    });

    test('tibetan вне окна отбрасывается (порт может вернуть шире)', () {
      final source = _StubSource('nyingma',
          tibetanDates: [DateTime(2026, 9, 1), DateTime(2026, 6, 3)]);
      final pack = packOf(entries: [entryOf()]);

      final feed = EventFeedService(
        traditionTag: 'nyingma',
        source: source,
        packs: [pack],
      ).build(today: _today);

      expect(feed.entries.single.date, DateTime(2026, 6, 3));
    });

    test('календарь не знает тибетских дат → пропуск с пояснением, не пустота',
        () {
      final source = _StubSource('theravada_default', tibetanDates: null);
      final pack = packOf(
        traditionTag: 'theravada_default',
        entries: [entryOf(name: 'Тибетское событие')],
      );

      final feed = EventFeedService(
        traditionTag: 'theravada_default',
        source: source,
        packs: [pack],
      ).build(today: _today);

      expect(feed.entries, isEmpty);
      expect(feed.notes.join('\n'), contains('тибетских дат не знает'));
      expect(feed.notes.join('\n'), contains('Тибетское событие'));
    });

    test('правило tibetan без календаря в сборке → пояснение с именем события',
        () {
      final pack = packOf(entries: [entryOf(name: 'Тибетское событие')]);
      final feed = EventFeedService(
        traditionTag: 'nyingma',
        source: null,
        packs: [pack],
      ).build(today: _today);

      expect(feed.entries, isEmpty);
      expect(feed.notes.join('\n'), contains('Тибетское событие'));
      expect(feed.notes.join('\n'), contains('календаря традиции'));
    });
  });

  group('EventFeedService — изоляция и честность пака', () {
    test('пак чужой традиции пропущен с пояснением (изоляция данных)', () {
      final source = _StubSource('nyingma');
      final pack = packOf(
        packId: 'foreign',
        traditionTag: 'theravada_default',
        entries: [
          entryOf(rule: const GregorianYearlyDateRule(month: 6, day: 10)),
        ],
      );
      final feed = EventFeedService(
        traditionTag: 'nyingma',
        source: source,
        packs: [pack],
      ).build(today: _today);

      expect(feed.entries, isEmpty);
      expect(feed.notes.join('\n'), contains('изоляция данных'));
    });

    test('verified=false доезжает до записи и даёт честное пояснение', () {
      final pack = packOf(verified: false, entries: [
        entryOf(rule: const GregorianYearlyDateRule(month: 6, day: 10)),
      ]);
      final feed = EventFeedService(
        traditionTag: 'nyingma',
        source: _StubSource('nyingma'),
        packs: [pack],
      ).build(today: _today);

      expect(feed.entries.single.isVerified, isFalse);
      expect(feed.notes.join('\n'), contains('не подтверждён'));
    });

    test('непроверенный пак без записей — нет записей, нет исключения', () {
      final feed = EventFeedService(
        traditionTag: 'nyingma',
        source: _StubSource('nyingma'),
        packs: [packOf(verified: false, entries: const [])],
      ).build(today: _today);

      expect(feed.isEmpty, isTrue);
      expect(feed.hasNotes, isTrue);
    });

    test('сбои загрузки паков видны в пояснениях', () {
      final feed = EventFeedService(
        traditionTag: 'nyingma',
        source: _StubSource('nyingma'),
        packs: const [],
        packFailures: const [
          EventPackFailure('assets/events/x.json', 'битый JSON'),
        ],
      ).build(today: _today);

      expect(feed.notes.single, contains('assets/events/x.json'));
      expect(feed.notes.single, contains('битый JSON'));
    });
  });

  group('EventFeedService — окно и сортировка', () {
    test('окно по умолчанию: сегодня и today+30 включительно, today+31 нет',
        () {
      EventFeed build(Duration window) => EventFeedService(
            traditionTag: 'theravada_default',
            source: _StubSource('theravada_default', days: [
              SpecialDay(
                  date: _today,
                  type: SpecialDayType.uposatha,
                  name: 'Сегодня'),
              SpecialDay(
                  date: DateTime(2026, 7, 1),
                  type: SpecialDayType.uposatha,
                  name: 'Ровно +30'),
              SpecialDay(
                  date: DateTime(2026, 7, 2),
                  type: SpecialDayType.uposatha,
                  name: 'Плюс 31'),
            ]),
            packs: const [],
          ).build(today: _today, window: window);

      final feed = build(EventFeedService.defaultWindow);
      expect(feed.entries.map((e) => e.title), ['Сегодня', 'Ровно +30']);
    });

    test('окно параметризуемо (планировщик задаёт своё)', () {
      final feed = EventFeedService(
        traditionTag: 'theravada_default',
        source: _StubSource('theravada_default', days: [
          SpecialDay(
              date: DateTime(2026, 7, 2),
              type: SpecialDayType.uposatha,
              name: 'Плюс 31'),
        ]),
        packs: const [],
      ).build(today: _today, window: const Duration(days: 40));

      expect(feed.entries.single.title, 'Плюс 31');
    });

    test('сортировка: по дате, затем календарь→пак, затем название', () {
      final source = _StubSource('nyingma', days: [
        SpecialDay(
            date: DateTime(2026, 6, 3),
            type: SpecialDayType.festival,
            name: 'Я'),
        SpecialDay(
            date: DateTime(2026, 6, 1),
            type: SpecialDayType.festival,
            name: 'А'),
      ]);
      final pack = packOf(entries: [
        entryOf(
            id: 'p1',
            name: 'Б',
            rule: const GregorianYearlyDateRule(month: 6, day: 1)),
        entryOf(
            id: 'p2',
            name: 'А',
            rule: const GregorianYearlyDateRule(month: 6, day: 1)),
      ]);
      final feed = EventFeedService(
        traditionTag: 'nyingma',
        source: source,
        packs: [pack],
      ).build(today: _today);

      expect(feed.entries.map((e) => '${e.date.day}:${e.title}'), [
        '1:А', // календарь 1 июня
        '1:А', // пак, название «А» — второй после календарной записи
        '1:Б',
        '3:Я',
      ]);
      expect(feed.entries.map((e) => e.source), [
        FeedEntrySource.calendar,
        FeedEntrySource.pack,
        FeedEntrySource.pack,
        FeedEntrySource.calendar,
      ]);
    });
  });
}
