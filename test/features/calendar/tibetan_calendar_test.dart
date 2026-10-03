/// Векторные тесты порта Пхугпа против ground-truth tibcal (F-18/F-43).
///
/// Фикстуры генерируются scripts/gen_tibcal_vectors.py из tibcal (MIT);
/// расхождение НАШЕГО кода с tibcal — баг порта (I-7), устраняется правкой
/// порта, а не подгонкой констант.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:dharma_toolkit/features/calendar/data/tibetan/tibetan_calendar.dart';
import 'package:dharma_toolkit/features/calendar/data/tibetan/tibetan_date.dart';

Map<String, dynamic> loadVectors() {
  final raw = File('test/fixtures/tibcal_vectors.json').readAsStringSync();
  return jsonDecode(raw) as Map<String, dynamic>;
}

final vectors = loadVectors();

( int y, int m, int d ) parseIso(String iso) {
  final parts = iso.split('-');
  return (
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
}

TibetanDate tibFromJson(Map<String, dynamic> t) => TibetanDate(
      year: t['year'] as int,
      month: t['month'] as int,
      isLeapMonth: t['leapMonth'] as bool,
      day: t['day'] as int,
      isLeapDay: t['leapDay'] as bool,
    );

Map<String, dynamic> tibToJson(TibetanDate td) => {
      'year': td.year,
      'month': td.month,
      'leapMonth': td.isLeapMonth,
      'day': td.day,
      'leapDay': td.isLeapDay,
    };

String isoOf(DateTime g) =>
    '${g.year.toString().padLeft(4, '0')}-'
    '${g.month.toString().padLeft(2, '0')}-'
    '${g.day.toString().padLeft(2, '0')}';

void main() {
  // Общий кэш на файл (B-16): глобальной карты порта больше нет, тесты 5a
  // используют штатный механизм — инстанс TibetanMonthCache. Кэш чист по
  // построению (мемоизация), равенство «plain vs cached» покрыто отдельным
  // тестом в tibetan_month_cache_test.dart — расхождений с фикстурой F-45
  // это не вносит.
  final sharedCache = TibetanMonthCache(limit: 400);
  group('gregorianToTibetan: полный поток против tibcal', () {
    test('все g2t-векторы совпадают (1457 дней: 2024–2026 + особые окна)', () {
      final list = vectors['g2t'] as List<dynamic>;
      expect(list, isNotEmpty);
      final mismatches = <String>[];
      for (final e in list) {
        final m = e as Map<String, dynamic>;
        final (y, mo, d) = parseIso(m['gregorian'] as String);
        final got = tibToJson(gregorianToTibetan(DateTime.utc(y, mo, d), cache: sharedCache));
        final exp = m['tibetan'] as Map<String, dynamic>;
        // Сравнение по 5 полям представления (ISO/ординал покрыты t2g-ходом).
        if (got['year'] != exp['year'] ||
            got['month'] != exp['month'] ||
            got['leapMonth'] != exp['leapMonth'] ||
            got['day'] != exp['day'] ||
            got['leapDay'] != exp['leapDay']) {
          mismatches.add('${m['gregorian']}: tibcal=$exp port=$got');
          if (mismatches.length > 10) break;
        }
      }
      expect(mismatches, isEmpty,
          reason: 'расхождений: ${mismatches.length}');
    });

    test('результирующий день никогда не пропущен, григорианская дата '
        'совпадает со входом', () {
      final list = vectors['g2t'] as List<dynamic>;
      for (final e in list) {
        final m = e as Map<String, dynamic>;
        final (y, mo, d) = parseIso(m['gregorian'] as String);
        final td = gregorianToTibetan(DateTime.utc(y, mo, d), cache: sharedCache);
        expect(td.isSkipped, isFalse, reason: m['gregorian'] as String);
        expect(td.gregorian, isNotNull);
        expect(isoOf(td.gregorian!), m['gregorian'],
            reason: 'обратная привязка дня');
      }
    });
  });

  group('tibetanToGregorian: обратный ход', () {
    test('round-trip каждой полученной тибетской даты совпадает', () {
      final list = vectors['t2g'] as List<dynamic>;
      expect(list.length, (vectors['g2t'] as List<dynamic>).length,
          reason: 'каждый g2t-день обязан дать ровно один уникальный t2g');
      final mismatches = <String>[];
      for (final e in list) {
        final m = e as Map<String, dynamic>;
        final got = tibetanToGregorian(tibFromJson(
            m['tibetan'] as Map<String, dynamic>), cache: sharedCache);
        if (isoOf(got) != m['gregorian']) {
          mismatches.add('${m['tibetan']}: tibcal=${m['gregorian']} '
              'port=${isoOf(got)}');
          if (mismatches.length > 10) break;
        }
      }
      expect(mismatches, isEmpty);
    });

    test('Лосары 2023–2027: t2g(год, 1, 1) и обратный g2t', () {
      final list = vectors['losar'] as List<dynamic>;
      expect(list.length, 5);
      for (final e in list) {
        final m = e as Map<String, dynamic>;
        final y = m['tibetanYear'] as int;
        final got = tibetanToGregorian(TibetanDate(
            year: y, month: 1, isLeapMonth: false, day: 1, isLeapDay: false), cache: sharedCache);
        expect(isoOf(got), m['gregorian'], reason: 'Лосар $y');
        final back = gregorianToTibetan(got, cache: sharedCache);
        expect(tibToJson(back), m['g2tBack'], reason: 'Лосар $y обратно');
      }
    });
  });

  group('аномалии: пропущенные и двойные дни (F-2)', () {
    test('пропущенный лунный день -> NoSuchTibetanDayException', () {
      final list = vectors['skipped_days'] as List<dynamic>;
      expect(list.length, greaterThanOrEqualTo(3));
      for (final e in list) {
        final m = e as Map<String, dynamic>;
        final y = m['year'] as int;
        final mo = m['month'] as int;
        final lm = m['leapMonth'] as bool;
        for (final missing in (m['missingDays'] as List<dynamic>).cast<int>()) {
          expect(
            () => tibetanToGregorian(TibetanDate(
                year: y,
                month: mo,
                isLeapMonth: lm,
                day: missing,
                isLeapDay: false), cache: sharedCache),
            throwsA(isA<NoSuchTibetanDayException>().having(
                (o) => o.toString(), 'сообщение о пропуске', contains('not found'))),
            reason: 'пропущенный день $y-$mo-$missing (lm=$lm)',
          );
        }
        // Якоря потока: дни до и после разрыва существуют и граничат пропуск.
        final bp =
            parseIso((m['before'] as Map<String, dynamic>)['gregorian'] as String);
        final bt = gregorianToTibetan(DateTime.utc(bp.$1, bp.$2, bp.$3), cache: sharedCache);
        expect(bt.day, (m['before'] as Map<String, dynamic>)['day']);
        final ap =
            parseIso((m['after'] as Map<String, dynamic>)['gregorian'] as String);
        final at = gregorianToTibetan(DateTime.utc(ap.$1, ap.$2, ap.$3), cache: sharedCache);
        expect(at.day, (m['after'] as Map<String, dynamic>)['day']);
      }
    });

    test('двойной день: leapDay=true/false дают две разные даты', () {
      final list = vectors['doubled_days'] as List<dynamic>;
      expect(list.length, greaterThanOrEqualTo(3));
      for (final e in list) {
        final m = e as Map<String, dynamic>;
        final base = TibetanDate(
            year: m['year'] as int,
            month: m['month'] as int,
            isLeapMonth: m['leapMonth'] as bool,
            day: m['day'] as int,
            isLeapDay: false);
        final regular = tibetanToGregorian(base, cache: sharedCache);
        final leap = tibetanToGregorian(
            TibetanDate(
                year: m['year'] as int,
                month: m['month'] as int,
                isLeapMonth: m['leapMonth'] as bool,
                day: m['day'] as int,
                isLeapDay: true),
            cache: sharedCache);
        expect(isoOf(leap), m['leapDate'], reason: 'вставной день');
        expect(isoOf(regular), m['regularDate'], reason: 'обычный день');
        expect(leap.isBefore(regular), isTrue,
            reason: 'вставной день идёт первым');
      }
    });
  });

  group('§4.1(iii): покрытие векторов (2025, удвоенный месяц/день)', () {
    final g2t = vectors['g2t'] as List<dynamic>;

    test('2025 присутствует целиком (365 дней)', () {
      final days2025 = g2t
          .map((e) => (e as Map<String, dynamic>)['gregorian'] as String)
          .where((s) => s.startsWith('2025-'))
          .length;
      expect(days2025, 365,
          reason: '2025 выпадал из набора целиком (находка §4.1(iii))');
    });

    test('удвоенный 1-й месяц: инстанс 1/1 с leapMonth=true в потоке', () {
      final doubledMonth = g2t.where((e) {
        final t = (e as Map<String, dynamic>)['tibetan'] as Map<String, dynamic>;
        return t['month'] == 1 && t['day'] == 1 && t['leapMonth'] == true;
      }).toList();
      expect(doubledMonth, isNotEmpty,
          reason: 'ветка «вставной 1/1» обязана опираться на фикстуру, '
              'а не на рукописный комментарий');
      expect(
          doubledMonth
              .map((e) => (e as Map<String, dynamic>)['gregorian'] as String),
          contains('2019-02-05'));
    });

    test('удвоенный день 1/1 (C6): 2036 и 2037 в doubled_days', () {
      final doubled = (vectors['doubled_days'] as List)
          .cast<Map<String, dynamic>>()
          .where((e) => e['month'] == 1 && e['day'] == 1)
          .map((e) => e['year'] as int)
          .toSet();
      expect(doubled, containsAll({2036, 2037}),
          reason: 'конвенция C6 обязана опираться на векторы, а не на '
              'комментарий: обе половины удвоенного 1/1');
    });

    test('losar_instances: все существующие инстансы 1/1 особых лет', () {
      final instances =
          (vectors['losar_instances'] as List).cast<Map<String, dynamic>>();
      expect(
          instances.any((e) =>
              e['tibetanYear'] == 1935 &&
              e['isLeapMonth'] == true &&
              e['gregorian'] == '1935-02-04'),
          isTrue,
          reason: '1935: обычный 1/1 пропущен — существует только вставной');
      expect(
          instances.any((e) =>
              e['tibetanYear'] == 2019 &&
              e['isLeapMonth'] == false &&
              e['gregorian'] == '2019-03-07'),
          isTrue,
          reason: '2019: удвоенный месяц — оба инстанса в фикстуре');
      for (final y in [2036, 2037]) {
        final halves = instances
            .where((e) => e['tibetanYear'] == y)
            .map((e) => e['isLeapDay'])
            .toSet();
        expect(halves, {true, false}, reason: 'обе половины дня $y');
      }
    });
  });

  group('yearAttributes', () {
    test('постоянны в пределах тибетского года', () {
      final byYear = <int, Set<String>>{};
      for (final e in (vectors['g2t'] as List<dynamic>)) {
        final m = e as Map<String, dynamic>;
        final td = tibFromJson(m['tibetan'] as Map<String, dynamic>);
        final a = yearAttributes(td.year);
        (byYear[td.year] ??= <String>{})
            .add('${a.fullName}|${a.rabjungCycle}|${a.royalYear}');
      }
      expect(byYear.values.every((s) => s.length == 1), isTrue,
          reason: 'внутри года атрибуты не должны меняться');
    });

    test('якоря источника: 2020 Iron-Rat, 2024 Wood-Dragon, '
        '2026 Fire Male Horse (convert.py L42–43)', () {
      expect(yearAttributes(2020).fullName, 'Iron Male Rat');
      expect(yearAttributes(2024).fullName, 'Wood Male Dragon');
      expect(yearAttributes(2026).fullName, 'Fire Male Horse');
      expect(yearAttributes(2026).rabjungCycle, 17);
      expect(yearAttributes(2026).royalYear, 2153);
      expect(yearAttributes(2026).span, '2026/27');
      expect(yearAttributes(2023).fullName, 'Water Female Hare');
    });
  });

  group('W30: кэш дня сетки (путь ленты «день × запись пака»)', () {
    test('повторная конверсия дня — попадание в кэш, тот же инстанс', () {
      final cache = TibetanMonthCache();
      final day = DateTime.utc(2026, 6, 15);
      final first = gregorianToTibetan(day, cache: cache);
      final afterFirst = cache.dayComputations;
      final second = gregorianToTibetan(day, cache: cache);

      expect(second, first);
      expect(identical(second, first), isTrue,
          reason: 'день неизменяем: кэш обязан вернуть тот же TibetanDate');
      expect(cache.dayComputations, afterFirst,
          reason: 'повторный резолв того же дня не пересчитывает день (W30)');
    });

    test('50 резолвов одного дня = 1 конверсия (N+1 ленты схлопнут)', () {
      final cache = TibetanMonthCache();
      final day = DateTime.utc(2026, 6, 15);
      for (var i = 0; i < 50; i++) {
        expect(gregorianToTibetan(day, cache: cache).day, greaterThan(0));
      }
      expect(cache.dayComputations, 1,
          reason: 'лента резолвит день на каждую tibetan-запись пака — '
              'день обязан считаться один раз');
    });

    test('разные дни считаются независимо', () {
      final cache = TibetanMonthCache();
      for (var i = 0; i < 5; i++) {
        gregorianToTibetan(DateTime.utc(2026, 6, 1 + i), cache: cache);
      }
      expect(cache.dayComputations, 5);
      expect(cache.length, greaterThan(0),
          reason: 'месячный кэш продолжает наполняться');
    });

    test('limit=0 (no-store): день пересчитывается, кэш не держит', () {
      final cache = TibetanMonthCache(limit: 0);
      final day = DateTime.utc(2026, 6, 15);
      gregorianToTibetan(day, cache: cache);
      gregorianToTibetan(day, cache: cache);
      expect(cache.dayComputations, 2);
      expect(cache.length, 0);
    });

    test('день из кэша равен конверсии без кэша (чистота)', () {
      final cache = TibetanMonthCache();
      final day = DateTime.utc(2026, 6, 15);
      final cached = gregorianToTibetan(day, cache: cache);
      final direct = gregorianToTibetan(day);
      expect(cached.year, direct.year);
      expect(cached.month, direct.month);
      expect(cached.day, direct.day);
      expect(cached.isLeapDay, direct.isLeapDay);
    });
  });
}
