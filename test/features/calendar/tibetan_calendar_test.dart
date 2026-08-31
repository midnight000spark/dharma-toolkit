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
  group('gregorianToTibetan: полный поток против tibcal', () {
    test('все g2t-векторы совпадают (731 день 2024 и 2026)', () {
      final list = vectors['g2t'] as List<dynamic>;
      expect(list, isNotEmpty);
      final mismatches = <String>[];
      for (final e in list) {
        final m = e as Map<String, dynamic>;
        final (y, mo, d) = parseIso(m['gregorian'] as String);
        final got = tibToJson(gregorianToTibetan(DateTime.utc(y, mo, d)));
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
        final td = gregorianToTibetan(DateTime.utc(y, mo, d));
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
            m['tibetan'] as Map<String, dynamic>));
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
            year: y, month: 1, isLeapMonth: false, day: 1, isLeapDay: false));
        expect(isoOf(got), m['gregorian'], reason: 'Лосар $y');
        final back = gregorianToTibetan(got);
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
                isLeapDay: false)),
            throwsA(isA<NoSuchTibetanDayException>().having(
                (o) => o.toString(), 'сообщение о пропуске', contains('not found'))),
            reason: 'пропущенный день $y-$mo-$missing (lm=$lm)',
          );
        }
        // Якоря потока: дни до и после разрыва существуют и граничат пропуск.
        final bp =
            parseIso((m['before'] as Map<String, dynamic>)['gregorian'] as String);
        final bt = gregorianToTibetan(DateTime.utc(bp.$1, bp.$2, bp.$3));
        expect(bt.day, (m['before'] as Map<String, dynamic>)['day']);
        final ap =
            parseIso((m['after'] as Map<String, dynamic>)['gregorian'] as String);
        final at = gregorianToTibetan(DateTime.utc(ap.$1, ap.$2, ap.$3));
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
        final regular = tibetanToGregorian(base);
        final leap = tibetanToGregorian(base.copyWith(isLeapDay: true));
        expect(isoOf(leap), m['leapDate'], reason: 'вставной день');
        expect(isoOf(regular), m['regularDate'], reason: 'обычный день');
        expect(leap.isBefore(regular), isTrue,
            reason: 'вставной день идёт первым');
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
}
