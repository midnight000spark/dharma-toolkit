/// Тесты UposathaCalendarProvider (FR-CAL-2, пакет 5b блок 2).
///
/// Сверка с эталоном: 149 событий фаз astronomia (Meeus ch.49 точные
/// моменты, F-49; генератор scripts/gen_uposatha_vectors.mjs). Допуск ±1
/// день — конвенция UTC-дня против национальных календарей.
library;

import 'package:dharma_toolkit/features/calendar/data/uposatha/moon_phase.dart';
import 'package:dharma_toolkit/features/calendar/data/uposatha/uposatha_calendar_provider.dart';
import 'package:dharma_toolkit/features/calendar/domain/special_day.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';

/// Подпись фазы в имениSpecialDay <-> тип события фикстуры.
const _labelByType = {
  'new': 'новолуние',
  'first': 'первая четверть',
  'full': 'полнолуние',
  'last': 'последняя четверть',
};

int _dayDiff(DateTime a, DateTime b) =>
    DateTime(a.year, a.month, a.day).difference(DateTime(b.year, b.month, b.day)).inDays;

void main() {
  final vectors = loadMoonVectors();
  final provider = UposathaCalendarProvider(traditionTag: 'theravada_default');

  group('moonPhase — здравые смыслы (низкоточный метод, I-2)', () {
    test('значения в диапазоне [0,1)', () {
      for (var i = 0; i < 400; i++) {
        final p = moonPhase(DateTime.utc(2025, 1, 1).add(Duration(hours: 6 * i)));
        expect(p, inInclusiveRange(0.0, 1.0 - 1e-12));
      }
    });

    test('фаза монотонно растёт между новолуниями (переход через 0 один)', () {
      // Новолуния 2025-05-27 и 2025-06-25 (18:02 UTC, фикстура). Окно
      // 28.05..26.06 захватывает ровно один сброс 0.99->0.0x.
      final start = DateTime.utc(2025, 5, 28);
      var wraps = 0;
      double? prev;
      for (var i = 0; i <= 29; i++) {
        final p = moonPhase(start.add(Duration(days: i)));
        if (prev != null && p < prev) wraps++;
        prev = p;
      }
      expect(wraps, 1);
    });

    test('точные моменты известных событий: полнолуние 2025-07-10 ~0.5', () {
      // Полнолуние 2025-07-10 20:37 UTC — полдень предыдущего дня обязан
      // быть в окне полной фазы, т.к. день события — 10 июля (UTC).
      final p = moonPhase(DateTime.utc(2025, 7, 10, 12));
      expect((p - 0.5).abs() < 0.03, isTrue, reason: 'phase=$p');
    });

    test('новолуние 2024-02-09 22:59 UTC (солнечное затмение) ~0.0', () {
      final p = moonPhase(DateTime.utc(2024, 2, 9, 12));
      expect(p > 0.97 || p < 0.03, isTrue, reason: 'phase=$p');
    });
  });

  group('UposathaCalendarProvider vs фикстура astronomia (149 событий)', () {
    test('фикстура на месте и регулярна', () {
      expect(vectors.length, 149);
      expect(vectors.first.utcDate.isBefore(vectors.last.utcDate), isTrue);
    });

    test('каждое событие фикстуры: ровно одна упосатха того же подтипа в ±1 день', () {
      final all = provider.getSpecialDays(
          DateTime(2024, 1, 1), DateTime(2026, 12, 31));
      final uposathas =
          all.where((d) => d.type == SpecialDayType.uposatha).toList();
      // Биекция: событий ровно столько, сколько векторов, и каждый вектор
      // покрыт единственным днём нужного подтипа в допуске ±1.
      expect(uposathas.length, vectors.length,
          reason: 'число упосатх должно совпасть с числом событий фаз');
      final used = <SpecialDay>{};
      final mismatches = <String>[];
      for (final v in vectors) {
        final label = _labelByType[v.type]!;
        final hits = uposathas
            .where((d) =>
                d.name.contains(label) &&
                _dayDiff(d.date, v.utcDate).abs() <= 1 &&
                !used.contains(d))
            .toList();
        if (hits.length != 1) {
          mismatches.add('${v.utcDate} ${v.type}: hits=${hits.length}');
        } else {
          used.add(hits.single);
        }
      }
      expect(mismatches, isEmpty,
          reason: 'расхождения >±1 дня с эталоном: $mismatches');
    });

    test('нет упосатх вне четырёх подтипов и дублей в одном дне', () {
      final all = provider.getSpecialDays(
          DateTime(2024, 1, 1), DateTime(2026, 12, 31));
      final days = all.map((d) => d.date).toList();
      days.sort();
      for (var i = 1; i < days.length; i++) {
        expect(days[i], isNot(days[i - 1]),
            reason: 'в один календарный день не должно попадать два события');
      }
    });

    test('контракт CalendarProvider: месяц, год, пустой диапазон', () {
      expectCalendarContract(
          provider, DateTime(2026, 9, 1), DateTime(2026, 9, 30));
      expectCalendarContract(
          provider, DateTime(2025, 1, 1), DateTime(2025, 12, 31));
      expectCalendarContract(
          provider, DateTime(2026, 1, 1), DateTime(2026, 1, 2));
    });

    test('September 2026: даты упосатх зафиксированы снапшотом', () {
      final sep = provider
          .getSpecialDays(DateTime(2026, 9, 1), DateTime(2026, 9, 30))
          .map((d) => '${d.date.month}-${d.date.day} ${d.name}')
          .toList();
      // Снимок результата (эталонная проверка при ревью): пересчёт не должен
      // меняться молча. Дни сверены с фикстурой astronomia: последняя
      // четверть 04.09 07h, новолуние 11.09 03h, первая четверть 18.09 20h,
      // полнолуние 26.09 16h (UTC).
      expect(sep, [
        '9-4 Упосатха (последняя четверть)',
        '9-11 Упосатха (новолуние)',
        '9-18 Упосатха (первая четверть)',
        '9-26 Упосатха (полнолуние)',
      ]);
    });

    test('чистота: повторный вызов даёт равный результат', () {
      final a = provider.getSpecialDays(DateTime(2026, 1, 1), DateTime(2026, 3, 31));
      final b = provider.getSpecialDays(DateTime(2026, 1, 1), DateTime(2026, 3, 31));
      expect(a, b);
    });

    test('from > to — ArgumentError (контракт, не пустой список)', () {
      expect(
          () => provider.getSpecialDays(DateTime(2026, 5, 5), DateTime(2026, 5, 4)),
          throwsArgumentError);
    });

    test('traditionTag из конструктора, не литерал внутри', () {
      expect(UposathaCalendarProvider(traditionTag: 'custom_tag').traditionTag,
          'custom_tag');
    });
  });
}
