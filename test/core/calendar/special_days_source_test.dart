/// Guard порта «источник особых дней» (D-37, пакет 6.1 блок A).
///
/// Проверяет поведение, а не отрисовку:
///  * **непривязанный порт падает громко** — [StateError], а не молчаливым
///    `null`/пустым списком: молчаливая подмена источника дней — класс
///    дефектов R-11/R-13/R-20;
///  * привязанный порт отдаёт ровно ту реализацию, которой его переопределили
///    (никакого service locator — только оверрайд ProviderScope, D-4/D-22);
///  * «календаря для традиции нет» — легальный `null` (честная деградация 4.1),
///    отличный от «порт не привязан».
///
/// Страж урока 1: обе ветки покрыты, и тест краснеет от подмены поведения
/// (мутация «дефолт возвращает null вместо StateError» — см. коммит блока A).
library;

import 'package:dharma_toolkit/core/calendar/calendar_provider.dart';
import 'package:dharma_toolkit/core/calendar/special_day.dart';
import 'package:dharma_toolkit/core/calendar/special_days_source.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Минимальная реализация контракта: порт обязан отдавать её как есть.
class _StubCalendar implements CalendarProvider {
  _StubCalendar(this.traditionTag);

  @override
  final String traditionTag;

  @override
  List<SpecialDay> getSpecialDays(DateTime from, DateTime to) => const [];
}

void main() {
  group('specialDaysSourceProvider — порт (D-37)', () {
    test('не привязан → StateError с указанием причины, не молчаливый null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(() => container.read(specialDaysSourceProvider),
          throwsA(isA<StateError>()));

      // Сообщение обязано называть владельца привязки (main.dart), иначе
      // диагностика композиции упирается в «что-то не то».
      expect(
        () => container.read(specialDaysSourceProvider),
        throwsA(predicate((e) =>
            e is StateError && e.message.contains('не привязан'))),
      );
    });

    test('привязан → отдаёт переданную реализацию (тег из пресета)', () {
      final source = _StubCalendar('nyingma');
      final container = ProviderContainer(overrides: [
        specialDaysSourceProvider.overrideWithValue(source),
      ]);
      addTearDown(container.dispose);

      expect(container.read(specialDaysSourceProvider), same(source));
      expect(container.read(specialDaysSourceProvider)!.traditionTag, 'nyingma');
    });

    test('календаря для традиции нет → null (деградация, не ошибка)', () {
      final container = ProviderContainer(overrides: [
        specialDaysSourceProvider.overrideWithValue(null),
      ]);
      addTearDown(container.dispose);

      expect(container.read(specialDaysSourceProvider), isNull);
    });
  });
}
