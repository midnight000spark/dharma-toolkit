/// Тесты TibetanCalendarProvider (FR-CAL-3, пакет 5b блок 3).
///
/// Поведенческие проверки (урок 4): диапазон дат на входе — список
/// SpecialDay на выходе; снимки якорей лежат внутри проверенного окна
/// порта F-45 (2024, 2026 целиком; Лосары 2023–2027) или подтверждены
/// прогоном tibcal 01591b5 (2027) — порт не самообслуживается.
library;

import 'package:dharma_toolkit/features/calendar/data/tibetan/tibetan_calendar_provider.dart';
import 'package:dharma_toolkit/features/calendar/domain/special_day.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';

List<String> _summary(List<SpecialDay> days) => days
    .map((d) => '${d.date.year}-${d.date.month}-${d.date.day} ${d.type.name}')
    .toList();

void main() {
  final provider = TibetanCalendarProvider(traditionTag: 'nyingma');

  group('дни 10/25 (FR-CAL-3)', () {
    test('сентябрь 2026: 25-й — 6.09, 10-й — 21.09 (окно векторов F-45)', () {
      final sep = provider.getSpecialDays(
          DateTime(2026, 9, 1), DateTime(2026, 9, 30));
      // Снимок результата: сентябрь 2026 входит в 731 g2t-вектор 2026 года,
      // т.е. эти два дня — ground truth tibcal (F-45), а не вывод порта.
      expect(_summary(sep), [
        '2026-9-6 tibetan25',
        '2026-9-21 tibetan10',
      ]);
    });

    test('в месяце ровно по одному 10-му и 25-му (окно 2026)', () {
      // Для месяцев без аномалий — по одному дню каждого типа.
      final days = provider
          .getSpecialDays(DateTime(2026, 9, 1), DateTime(2026, 12, 31));
      expect(
          days.where((d) => d.type == SpecialDayType.tibetan10).length, 4);
      expect(
          days.where((d) => d.type == SpecialDayType.tibetan25).length, 4);
    });

    test('имена и описания — канонические, русский язык', () {
      final sep = provider.getSpecialDays(
          DateTime(2026, 9, 1), DateTime(2026, 9, 30));
      final t10 = sep.firstWhere((d) => d.type == SpecialDayType.tibetan10);
      expect(t10.name, '10-й день тибетского месяца');
      expect(t10.description, contains('Пхугпа'));
      final t25 = sep.firstWhere((d) => d.type == SpecialDayType.tibetan25);
      expect(t25.name, '25-й день тибетского месяца');
    });
  });

  group('Лосар (FR-CAL-5, фикстура F-45)', () {
    final losars = loadLosarVectors();

    test('фикстура на месте: 5 Лосаров 2023–2027', () {
      expect(losars.map((l) => l.tibetanYear),
          [2023, 2024, 2025, 2026, 2027]);
    });

    test('losarDate(y) == григорианская дата из фикстуры tibcal', () {
      // 2.3: сверка вычисления порта с фикстурой F-45 (публичные даты).
      final expected = {
        2023: DateTime(2023, 2, 21),
        2024: DateTime(2024, 2, 10),
        2025: DateTime(2025, 2, 28),
        2026: DateTime(2026, 2, 18),
        2027: DateTime(2027, 2, 7),
      };
      for (final e in expected.entries) {
        expect(TibetanCalendarProvider.losarDate(e.key), e.value,
            reason: 'Лосар ${e.key}');
      }
      // Перекрёстно: те же даты отдает фикстура.
      for (final l in losars) {
        expect(TibetanCalendarProvider.losarDate(l.tibetanYear), l.gregorian,
            reason: 'Лосар ${l.tibetanYear} vs фикстура');
      }
    });

    test('getSpecialDays помечает Лосар festival-днём', () {
      final l2026 = losars.firstWhere((l) => l.tibetanYear == 2026);
      final days = provider.getSpecialDays(
          DateTime(2026, 2, 15), DateTime(2026, 2, 21));
      final losar =
          days.where((d) => d.type == SpecialDayType.festival).toList();
      expect(losar, hasLength(1));
      expect(losar.single.date, DateTime(2026, 2, 18));
      expect(losar.single.name, 'Лосар — тибетский Новый год');
    });

    test('в сентябре 2026 Лосара нет (не каждый месяц — праздник)', () {
      final sep = provider.getSpecialDays(
          DateTime(2026, 9, 1), DateTime(2026, 9, 30));
      expect(sep.where((d) => d.type == SpecialDayType.festival), isEmpty);
    });
  });

  group('контракт реализации', () {
    test('traditionTag из конструктора, не литерал внутри', () {
      expect(TibetanCalendarProvider(traditionTag: 'custom_tag').traditionTag,
          'custom_tag');
    });

    test('from > to — ArgumentError (контракт, не пустой список)', () {
      expect(
          () => provider.getSpecialDays(
              DateTime(2026, 5, 5), DateTime(2026, 5, 4)),
          throwsArgumentError);
    });

    test('чистота: повторный вызов даёт равный результат', () {
      final a = provider.getSpecialDays(
          DateTime(2026, 1, 1), DateTime(2026, 3, 31));
      final b = provider.getSpecialDays(
          DateTime(2026, 1, 1), DateTime(2026, 3, 31));
      expect(a, b);
    });

    test('пустой короткий диапазон — пустой список, не null', () {
      // 2026-09-01..02: ни 10-го, ни 25-го (лунные дни 4–5).
      final empty = provider.getSpecialDays(
          DateTime(2026, 9, 1), DateTime(2026, 9, 2));
      expect(empty, isEmpty);
    });
  });
}
