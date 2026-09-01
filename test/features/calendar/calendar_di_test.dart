/// DI-регистрация тибетского календаря (5b.3 блок 5, D-22).
///
/// Тесты ломаются, если регистрацию отвернут в service locator или если
/// провайдер начнёт сам выбирать тег/школу (нарушение принципа №3).
library;

import 'package:dharma_toolkit/features/calendar/data/tibetan/tibetan_calendar_provider.dart';
import 'package:dharma_toolkit/features/calendar/domain/calendar_provider.dart';
import 'package:dharma_toolkit/features/calendar/domain/special_day.dart';
import 'package:dharma_toolkit/features/calendar/presentation/providers/calendar_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('провайдер конструирует TibetanCalendarProvider по тегу из ключа', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final cal =
        container.read(tibetanCalendarProviderProvider('nyingma'));
    expect(cal, isA<TibetanCalendarProvider>());
    expect(cal, isA<CalendarProvider>());
    // Тег приходит КЛЮЧОМ (preset.id снаружи), а не литералом внутри —
    // другой ключ даёт другой тег (B-4/принцип №3).
    expect(cal.traditionTag, 'nyingma');
    expect(
        container
            .read(tibetanCalendarProviderProvider('kagyu_custom'))
            .traditionTag,
        'kagyu_custom');
  });

  test('стабильность: одинаковый ключ — один и тот же экземпляр', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(tibetanCalendarProviderProvider('nyingma')),
        same(container.read(tibetanCalendarProviderProvider('nyingma'))));
  });

  test('провайдер отдаёт рабочие особые дни (сквозной дым-тест DI)', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final days = container
        .read(tibetanCalendarProviderProvider('nyingma'))
        .getSpecialDays(DateTime(2026, 9, 1), DateTime(2026, 9, 30));
    // Якорь окна векторов F-45 (см. tibetan_calendar_provider_test).
    expect(
        days
            .where((d) => d.type == SpecialDayType.tibetan25)
            .map((d) => d.date)
            .toList(),
        [DateTime(2026, 9, 6)]);
  });
}
