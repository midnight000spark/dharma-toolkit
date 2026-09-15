/// Адаптер источника особых дней над календарём (D-37, блок C пакета 6.1).
///
/// Проверяется то, что не проверить на уровне чистого домена: поиск дня
/// тибетского месяца в григорианском окне идёт **по движку календаря**, а
/// календарь, тибетских дат не знающий, честно отказывает (`null`), а не
/// возвращает пустоту (разные состояния — SCR-12).
///
/// Эталонная дата — Лосар 2026 (2026-02-18) из векторов tibcal F-45: значение
/// берётся из фикстуры независимо от движка, поэтому тест ловит не только
/// «адаптер зовёт сам себя», но и расхождение с эталоном.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dharma_toolkit/core/calendar/special_day.dart';
import 'package:dharma_toolkit/features/calendar/data/calendar_special_days_source.dart';
import 'package:dharma_toolkit/features/calendar/data/tibetan/tibetan_calendar_provider.dart';
import 'package:dharma_toolkit/features/calendar/data/uposatha/uposatha_calendar_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// Лосар 2026 по векторам tibcal (F-45) — независимый эталон.
DateTime losar2026FromVectors() {
  final raw = jsonDecode(
      File('test/fixtures/tibcal_vectors.json').readAsStringSync()) as Map;
  for (final e in raw['losar'] as List) {
    final map = e as Map<String, dynamic>;
    if (map['tibetanYear'] == 2026) {
      return DateTime.parse('${map['gregorian']}T00:00:00');
    }
  }
  throw StateError('вектор Лосара 2026 не найден в фикстуре');
}

void main() {
  final losar = losar2026FromVectors();

  group('CalendarSpecialDaysSource — тибетский календарь', () {
    late CalendarSpecialDaysSource source;

    setUp(() {
      source = CalendarSpecialDaysSource(
        TibetanCalendarProvider(traditionTag: 'nyingma'),
      );
    });

    test('тег традиции — из провайдера, не литерал адаптера', () {
      expect(source.traditionTag, 'nyingma');
    });

    test('день 1/1 тибетского месяца — Лосар из векторов F-45', () {
      final dates = source.resolveTibetanMonthDay(
        month: 1,
        day: 1,
        from: DateTime(2026, 2, 1),
        to: DateTime(2026, 3, 15),
      );

      expect(dates, isNotNull);
      expect(dates, contains(losar));
    });

    test('окно без этой даты → пустой список, не null (разные состояния)', () {
      final dates = source.resolveTibetanMonthDay(
        month: 1,
        day: 1,
        from: DateTime(2026, 6, 1),
        to: DateTime(2026, 6, 30),
      );

      expect(dates, isNotNull);
      expect(dates, isEmpty);
    });

    test('день 10 первого тибетского месяца — ровно одна дата рядом с Лосаром',
        () {
      final dates = source.resolveTibetanMonthDay(
        month: 1,
        day: 10,
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 12, 31),
      );

      expect(dates, isNotNull);
      expect(dates, hasLength(1), reason: '1-й месяц 2026 не удвоен');
      final d = dates!.single;
      expect(d.isAfter(losar), isTrue);
      expect(d.difference(losar).inDays, lessThanOrEqualTo(11),
          reason: '10-й день месяца — в пределах пары недель от 1/1');
    });

    test('резолв по всем месяцам совпадает с разметкой tibetan10 провайдера',
        () {
      final provider = TibetanCalendarProvider(traditionTag: 'nyingma');
      final adapter = CalendarSpecialDaysSource(provider);
      final from = DateTime(2026, 1, 1);
      final to = DateTime(2026, 12, 31);

      // Независимая сверка: адаптер не «зовёт сам себя», а обязан совпасть с
      // уже проверенным выходом провайдера (FR-CAL-3).
      final byProvider = provider
          .getSpecialDays(from, to)
          .where((d) => d.type == SpecialDayType.tibetan10)
          .map((d) => d.date)
          .toSet();
      final byAdapter = <DateTime>{};
      for (var month = 1; month <= 12; month++) {
        byAdapter.addAll(
            adapter.resolveTibetanMonthDay(
                month: month, day: 10, from: from, to: to) ??
                const []);
      }

      expect(byProvider, isNotEmpty);
      expect(byAdapter, byProvider);
    });

    test('from > to — ArgumentError (контракт, не пустой список)', () {
      expect(
        () => source.resolveTibetanMonthDay(
          month: 1,
          day: 1,
          from: DateTime(2026, 6, 2),
          to: DateTime(2026, 6, 1),
        ),
        throwsArgumentError,
      );
    });

    test('особые дни делегируются провайдеру без изменений', () {
      final provider = TibetanCalendarProvider(traditionTag: 'nyingma');
      final adapter = CalendarSpecialDaysSource(provider);
      final from = DateTime(2026, 2, 1);
      final to = DateTime(2026, 2, 28);

      expect(
        adapter.getSpecialDays(from, to).map((d) => '${d.date}|${d.type}'),
        provider.getSpecialDays(from, to).map((d) => '${d.date}|${d.type}'),
      );
    });
  });

  group('CalendarSpecialDaysSource — календарь без тибетских дат', () {
    test('упосатха честно отказывает (null), не пустотой', () {
      final source = CalendarSpecialDaysSource(
        UposathaCalendarProvider(traditionTag: 'theravada_default'),
      );

      expect(
        source.resolveTibetanMonthDay(
          month: 1,
          day: 1,
          from: DateTime(2026, 1, 1),
          to: DateTime(2026, 12, 31),
        ),
        isNull,
      );
    });

    test('особые дни упосатх делегируются как есть', () {
      final provider =
          UposathaCalendarProvider(traditionTag: 'theravada_default');
      final source = CalendarSpecialDaysSource(provider);
      final from = DateTime(2026, 1, 1);
      final to = DateTime(2026, 1, 31);

      final days = source.getSpecialDays(from, to);
      expect(days, isNotEmpty);
      expect(days.every((d) => d.type == SpecialDayType.uposatha), isTrue);
      expect(days, provider.getSpecialDays(from, to));
    });
  });

  group('CalendarSpecialDaysSource — источник активного пресета', () {
    test('адаптер наследует тег и отдаёт дни через порт (порт ≠ контракт)',
        () {
      final provider = TibetanCalendarProvider(traditionTag: 'nyingma');
      final adapter = CalendarSpecialDaysSource(provider);

      expect(adapter.traditionTag, provider.traditionTag);
      expect(
        adapter.getSpecialDays(DateTime(2026, 2, 1), DateTime(2026, 2, 28)),
        isNotEmpty,
      );
    });
  });
}
