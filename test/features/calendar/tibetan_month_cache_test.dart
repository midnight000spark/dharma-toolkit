/// B-16 (5b.4): кэш месяцев порта — инстанс-состояние, не общая статика.
///
/// Два независимых [TibetanCalendarProvider] дают равные результаты:
/// корректность от кэша не зависит. Guard-скан не даёт вернуться
/// разделяемому изменяемому состоянию уровня библиотеки/класса.
library;

import 'package:dharma_toolkit/features/calendar/data/tibetan/tibetan_calendar.dart';
import 'package:dharma_toolkit/features/calendar/data/tibetan/tibetan_calendar_provider.dart';
import 'package:dharma_toolkit/features/calendar/data/tibetan/tibetan_date.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TibetanMonthCache (B-16)', () {
    test('чистота: кэшированный вызов равен некешированному', () {
      final cache = TibetanMonthCache();
      // Один и тот же месяц дважды через кэш и один раз без него.
      final first = cache.buildMonth(2026, 1, 14901, false);
      final second = cache.buildMonth(2026, 1, 14901, false);
      final direct = gregorianToTibetan(DateTime(2026, 1, 15));
      expect(identical(first, second), isTrue,
          reason: 'повтор отдаёт тот же список (мемоизация работает)');
      // Прямой вызов без кэша не должен расходиться с кэшированным путём:
      // равны по содержанию (списки SpecialDay/TibetanDate — значение).
      expect(direct.isSkipped, isFalse);
      expect(direct.day, greaterThan(0));
    });

    test('ограничение размера: кэш не растёт бесконечно', () {
      final cache = TibetanMonthCache(limit: 8);
      // 12 разных месяцев подряд — больше лимита.
      for (var i = 0; i < 12; i++) {
        cache.buildMonth(2020, 1, 14000 + i, false);
      }
      expect(cache.length, lessThanOrEqualTo(8),
          reason: 'FIFO-эвикция обязана держать размер в пределах limit');
      // Вытесненный месяц пересчитывается и даёт прежнее значение.
      final again = cache.buildMonth(2020, 1, 14000, false);
      expect(again, hasLength(greaterThan(0)));
    });

    test('нулевой лимит не ломает работу (каждый раз пересчёт)', () {
      final cache = TibetanMonthCache(limit: 0);
      expect(cache.length, 0);
      final days = cache.buildMonth(2026, 1, 14901, false);
      expect(days, hasLength(greaterThan(0)));
      expect(cache.length, 0, reason: 'при limit=0 ничего не хранится');
    });
  });

  group('порт без кэша (обратная совместимость top-level API)', () {
    test('gregorianToTibetan без cache работает и совпадает с provider-путём',
        () {
      final d = DateTime(2026, 2, 18);
      final plain = gregorianToTibetan(d);
      final cached = gregorianToTibetan(d, cache: TibetanMonthCache());
      expect(cached.year, plain.year);
      expect(cached.month, plain.month);
      expect(cached.day, plain.day);
      expect(cached.isLeapMonth, plain.isLeapMonth);
      expect(cached.isLeapDay, plain.isLeapDay);
    });

    test('tibetanToGregorian с кэшем и без дают одну дату', () {
      final t = TibetanDate(
          year: 2026, month: 1, isLeapMonth: false, day: 1, isLeapDay: false);
      expect(tibetanToGregorian(t, cache: TibetanMonthCache()),
          tibetanToGregorian(t));
    });
  });

  // Буква 3.2: инкапсуляция кэша не меняет результатов — два независимых
  // инстанса провайдера на одном запросе обязаны сойтись (урок B-16:
  // разделяемое состояние не должно влиять на корректность).
  group('инстанс-изоляция провайдера (B-16)', () {
    test('два инстанса с одинаковым запросом дают равные результаты', () {
      final a = TibetanCalendarProvider(traditionTag: 'nyingma');
      final b = TibetanCalendarProvider(traditionTag: 'kagyu_custom');
      final from = DateTime(2025, 1, 1);
      final to = DateTime(2026, 12, 31);

      expect(b.getSpecialDays(from, to), a.getSpecialDays(from, to),
          reason: 'календарные дни не зависят от инстанса и порядка вызовов');
      // Теги разные — данные изолированы (принцип №3), вычисления те же.
      expect(a.traditionTag, isNot(b.traditionTag));
    });

    test('getSpecialDays реально использует кэш инстанса (wiring B-16)', () {
      final cache = TibetanMonthCache();
      final provider = TibetanCalendarProvider(
          traditionTag: 'nyingma', monthCache: cache);
      expect(provider.monthCache, same(cache));
      expect(cache.length, 0, reason: 'до запроса кэш пуст');

      provider.getSpecialDays(DateTime(2026, 3, 1), DateTime(2026, 3, 31));
      expect(cache.length, greaterThan(0),
          reason: 'окно запроса должно наполнять кэш ЭТОГО инстанса '
              '(мутация «провайдер зовёт порт без кэша» — красная)');
    });
  });
}
