/// Лента контента: окно, дедупликация пояснений, честный фолбэк (блок B, 7.0).
///
/// Проверяется доменное поведение ленты, а не отрисовка (урок 5): границы окна,
/// присутствие дня с чтением и дня с фолбэком, отсутствие дублей в пояснениях и
/// то, что чужие/битые паки не прячутся молча. «Сегодня» приходит аргументом —
/// часы не подделываются, результат детерминирован.
library;

import 'package:dharma_toolkit/features/content/data/content_pack_loader.dart';
import 'package:dharma_toolkit/features/content/domain/content_fallbacks.dart';
import 'package:dharma_toolkit/features/content/domain/content_feed.dart';
import 'package:dharma_toolkit/features/content/domain/content_feed_service.dart';
import 'package:dharma_toolkit/features/content/domain/content_pack.dart';
import 'package:dharma_toolkit/features/content/domain/content_reading.dart';
import 'package:flutter_test/flutter_test.dart';

ContentEntry entryOf({
  String id = 'c1',
  String title = 'Синтетическое чтение',
  String body = 'Синтетический текст фикстуры.',
  String source = 'синтетическая фикстура теста',
  ContentDateRule? rule,
}) =>
    ContentEntry(
      id: id,
      type: 'daily_reading',
      title: title,
      body: body,
      source: source,
      dateRule: rule,
    );

ContentPack packOf({
  String packId = 'p',
  String traditionTag = 'nyingma',
  bool verified = true,
  required List<ContentEntry> entries,
}) =>
    ContentPack(
      packId: packId,
      traditionTag: traditionTag,
      version: '1',
      verified: verified,
      entries: entries,
    );

List<ContentEntry> poolOf(int size, {String prefix = 'пула'}) => [
      for (var i = 0; i < size; i++)
        entryOf(id: 'pool$i', title: 'Чтение $prefix $i', body: 'Текст $i.'),
    ];

final _today = DateTime(2026, 6, 1);

ContentFeedService serviceOf({
  String traditionTag = 'nyingma',
  List<ContentPack>? packs,
  List<ContentPackFailure> failures = const [],
}) =>
    ContentFeedService(
      traditionTag: traditionTag,
      packs: packs ?? [packOf(entries: poolOf(3))],
      packFailures: failures,
    );

void main() {
  group('ContentFeedService — окно', () {
    test('окно: сегодня + 7 включительно, дни идут подряд без пропусков', () {
      final feed = serviceOf().build(today: _today);

      expect(feed.days, hasLength(8), reason: 'сегодня и семь дней вперёд');
      expect(feed.days.first.date, _today);
      expect(feed.days.last.date, DateTime(2026, 6, 8));
      for (var i = 1; i < feed.days.length; i++) {
        expect(
          feed.days[i].date.difference(feed.days[i - 1].date).inDays,
          1,
          reason: 'день ${i + 1} окна обязан быть следующим календарным днём',
        );
      }
    });

    test('день за границей окна (today + 8) в ленту не попадает', () {
      final feed = serviceOf().build(today: _today);

      expect(feed.on(DateTime(2026, 6, 8)), isNotNull);
      expect(feed.on(DateTime(2026, 6, 9)), isNull);
      expect(feed.on(DateTime(2026, 5, 31)), isNull,
          reason: 'вчерашний день в окно не входит');
    });

    test('окно параметризуемо: UI/планировщик задают своё', () {
      final feed = serviceOf().build(today: _today, window: const Duration(days: 2));

      expect(feed.days, hasLength(3));
      expect(feed.days.last.date, DateTime(2026, 6, 3));
    });

    test('on(day) отдаёт чтения дня, время аргумента не значимо', () {
      final feed = serviceOf().build(today: _today);

      final day = feed.on(DateTime(2026, 6, 3, 23, 59));
      expect(day, isNotNull);
      expect(day!.readings, isNotEmpty);
      expect(day.date, DateTime(2026, 6, 3));
    });

    test('allReadings собирает чтения всех дней', () {
      final feed = serviceOf().build(today: _today);

      expect(feed.allReadings, hasLength(8), reason: 'по одному чтению в день');
      expect(feed.isEmpty, isFalse);
    });

    test('привязанное к дате чтение попадает именно в свой день окна', () {
      final feed = serviceOf(packs: [
        packOf(entries: [
          entryOf(
            id: 'bound',
            title: 'Чтение на третье июня',
            rule: const GregorianYearlyContentDateRule(month: 6, day: 3),
          ),
          ...poolOf(2),
        ]),
      ]).build(today: _today);

      final day = feed.on(DateTime(2026, 6, 3))!;
      expect(day.readings.first.title, 'Чтение на третье июня');
      expect(day.readings.first.isDateBound, isTrue);

      final other = feed.on(DateTime(2026, 6, 4))!;
      expect(other.readings.any((r) => r.isDateBound), isFalse);
    });
  });

  group('ContentFeedService — честные пояснения', () {
    test('сбой загрузки пака попадает в notes ленты', () {
      final feed = serviceOf(failures: const [
        ContentPackFailure('assets/content_packs/broken.json', 'битый JSON'),
      ]).build(today: _today);

      expect(
        feed.notes.any((n) =>
            n.contains('assets/content_packs/broken.json') &&
            n.contains('битый JSON')),
        isTrue,
        reason: 'пользователь обязан узнать, что пак не прочитан, а не видеть '
            'тихую пустоту',
      );
    });

    test('повторяющаяся причина звучит один раз, а не восемь', () {
      final feed = serviceOf(packs: [
        packOf(verified: false, entries: poolOf(2)),
      ]).build(today: _today);

      final aboutPack =
          feed.notes.where((n) => n.contains('не подтверждён')).toList();
      expect(aboutPack, hasLength(1));
    });

    test('пак чужой традиции назван причиной пропуска', () {
      final feed = serviceOf(packs: [
        packOf(packId: 'foreign', traditionTag: 'theravada', entries: poolOf(2)),
      ]).build(today: _today);

      expect(feed.notes.any((n) => n.contains('изоляция данных')), isTrue);
    });

    test('пустой вход — честное «контента пока нет», а не ошибка', () {
      final feed = serviceOf(packs: const []).build(today: _today);

      expect(feed.isEmpty, isFalse, reason: 'фолбэк FR-CNT-3 даёт текст');
      expect(feed.usesFallback, isTrue);
      expect(feed.notes, contains(ContentFallbacks.note));
      expect(feed.days.every((d) => d.readings.length == 1), isTrue);
      expect(feed.days.every((d) => d.isFallback), isTrue);
    });

    test('usesFallback молчит, когда контент традиции есть', () {
      final feed = serviceOf().build(today: _today);

      expect(feed.usesFallback, isFalse);
      expect(feed.allReadings.every((r) => r.source == ContentReadingSource.pack),
          isTrue);
    });

    test('ContentFeed.empty — пустая лента без пояснений', () {
      expect(ContentFeed.empty.isEmpty, isTrue);
      expect(ContentFeed.empty.hasNotes, isFalse);
      expect(ContentFeed.empty.usesFallback, isFalse);
    });
  });

  group('ContentFeedService — пул и ротация на окне', () {
    test('два пака: пул объединяется, обе записи встречаются за неделю', () {
      final feed = serviceOf(packs: [
        packOf(packId: 'a', entries: [entryOf(id: 'a1', title: 'Текст A')]),
        packOf(packId: 'b', entries: [entryOf(id: 'b1', title: 'Текст B')]),
      ]).build(today: _today);

      final titles = feed.allReadings.map((r) => r.title).toSet();
      expect(titles, {'Текст A', 'Текст B'});
      expect(
        feed.allReadings.map((r) => r.packId).toSet(),
        {'a', 'b'},
        reason: 'атрибуция обязана указывать на конкретный пак',
      );
    });

    test('каждое чтение несёт атрибуцию и признак подтверждённости', () {
      final feed = serviceOf(packs: [
        packOf(verified: false, entries: poolOf(2)),
      ]).build(today: _today);

      for (final reading in feed.allReadings) {
        expect(reading.attribution, contains('синтетическая фикстура теста'));
        expect(reading.isVerified, isFalse);
      }
    });
  });
}
