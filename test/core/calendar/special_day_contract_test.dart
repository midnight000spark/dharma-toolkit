/// W13: контракт [SpecialDay.date] — календарный день, а не момент времени.
///
/// День обязан быть **UTC-полночью** (`DateTime.isUtc`, `hour == 0`):
/// локальная полночь в зонах с переходом часов в 00:00 (Santiago, Havana,
/// Tehran и др.) не существует — Dart разворачивает её в 01:00, и день
/// начинает зависеть от зоны устройства: `==`, ключи дедупликации и границы
/// окон расходятся. Тест полярно проверяем в любой зоне прогона: наивная
/// локальная полночь краснеет на `isUtc`/`hour` (мутант «вернуть наивную
/// полночь» — красный).
library;

import 'package:dharma_toolkit/core/calendar/special_day.dart';
import 'package:dharma_toolkit/features/calendar/data/tibetan/tibetan_calendar_provider.dart';
import 'package:dharma_toolkit/features/calendar/data/uposatha/uposatha_calendar_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void _expectUtcCalendarDay(SpecialDay d) {
  expect(d.date.isUtc, isTrue,
      reason: '${d.name} (${d.date.toIso8601String()}): SpecialDay.date — '
          'UTC-полночь календарного дня (W13)');
  expect(d.date.hour, 0, reason: '${d.name}: час обязан быть 0 в любой зоне');
  expect(d.date.minute, 0);
  expect(d.date, DateTime.utc(d.date.year, d.date.month, d.date.day));
}

void main() {
  group('W13: SpecialDay.date — UTC-полночь', () {
    test('тибетский провайдер: все дни года — UTC-полночь', () {
      final provider = TibetanCalendarProvider(traditionTag: 'nyingma');
      final days = provider.getSpecialDays(
          DateTime(2026, 1, 1), DateTime(2026, 12, 31));
      expect(days, isNotEmpty);
      days.forEach(_expectUtcCalendarDay);
    });

    test('упосатха: все дни года — UTC-полночь', () {
      final provider = UposathaCalendarProvider(traditionTag: 'theravada');
      final days = provider.getSpecialDays(
          DateTime(2026, 1, 1), DateTime(2026, 12, 31));
      expect(days, isNotEmpty);
      days.forEach(_expectUtcCalendarDay);
    });

    test('день не зависит от зоны входа: локальный и UTC-запрос дают те же дни',
        () {
      final provider = TibetanCalendarProvider(traditionTag: 'nyingma');
      String key(SpecialDay d) =>
          '${d.date.year}-${d.date.month}-${d.date.day}|${d.type}|${d.name}';
      final local = provider
          .getSpecialDays(DateTime(2026, 2, 1), DateTime(2026, 2, 28))
          .map(key)
          .toList();
      final utc = provider
          .getSpecialDays(DateTime.utc(2026, 2, 1), DateTime.utc(2026, 2, 28))
          .map(key)
          .toList();
      expect(local, utc);
      expect(local, isNotEmpty);
    });
  });
}
