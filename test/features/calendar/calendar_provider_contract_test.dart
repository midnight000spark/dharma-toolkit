/// Контрактный тест абстракции CalendarProvider (FR-CAL-1, блок 1 пакета 5b).
///
/// Проверка урока 1: валидатор контракта сам тестится на «сломанных»
/// фиктивных реализациях — тест, который не мог упасть, ничего не
/// доказывает. Моки ручные (mocktail в стек не включён, AGENT v2.5).
library;

import 'package:dharma_toolkit/features/calendar/domain/special_day.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';

final _d1 = DateTime(2026, 9, 1);
final _d2 = DateTime(2026, 9, 2);
final _d3 = DateTime(2026, 9, 3);

void main() {
  group('CalendarProvider контракт (FR-CAL-1)', () {
    test('корректная реализация проходит контракт', () {
      final provider = StubCalendarProvider('nyingma', [
        SpecialDay(date: _d1, type: SpecialDayType.tibetan10, name: '10-й день'),
        SpecialDay(date: _d3, type: SpecialDayType.festival, name: 'Праздник'),
      ]);
      expectCalendarContract(provider, _d1, _d3);
      expect(provider.getSpecialDays(_d1, _d3).length, 2);
    });

    test('пустой диапазон допустим — пустой список, не null', () {
      final provider = StubCalendarProvider('theravada_default', const []);
      expect(provider.getSpecialDays(_d1, _d3), isEmpty);
    });

    test('валидатор ловит неотсортированный вывод (страж урока 1)', () {
      final broken = StubCalendarProvider('nyingma', [_d3, _d1]
          .map((d) =>
              SpecialDay(date: d, type: SpecialDayType.tibetan25, name: 'x'))
          .toList());
      expect(() => expectCalendarContract(broken, _d1, _d3),
          throwsA(isA<TestFailure>()));
    });

    test('валидатор ловит день вне диапазона', () {
      final broken = StubCalendarProvider('nyingma', [
        SpecialDay(date: DateTime(2026, 10, 9),
            type: SpecialDayType.tibetan10, name: 'вне окна'),
      ]);
      expect(() => expectCalendarContract(broken, _d1, _d3),
          throwsA(isA<TestFailure>()));
    });

    test('валидатор ловит дубль по (date, type)', () {
      final broken = StubCalendarProvider('nyingma', [
        SpecialDay(date: _d2, type: SpecialDayType.festival, name: 'а'),
        SpecialDay(date: _d2, type: SpecialDayType.festival, name: 'б'),
      ]);
      expect(() => expectCalendarContract(broken, _d1, _d3),
          throwsA(isA<TestFailure>()));
    });

    test('валидатор ловит пустой traditionTag', () {
      final broken = StubCalendarProvider('', const []);
      expect(() => expectCalendarContract(broken, _d1, _d3),
          throwsA(isA<TestFailure>()));
    });

    test('один день двух разных типов — не дубль, контракт соблюдён', () {
      final ok = StubCalendarProvider('nyingma', [
        SpecialDay(date: _d2, type: SpecialDayType.tibetan10, name: '10-й'),
        SpecialDay(date: _d2, type: SpecialDayType.festival, name: 'праздник'),
      ]);
      expectCalendarContract(ok, _d1, _d3);
    });
  });

  group('SpecialDay — доменная модель', () {
    test('равенство по всем полям', () {
      final a = SpecialDay(
          date: _d1, type: SpecialDayType.uposatha, name: 'Упосатха');
      final b = SpecialDay(
          date: _d1, type: SpecialDayType.uposatha, name: 'Упосатха');
      final c = SpecialDay(
          date: _d1,
          type: SpecialDayType.uposatha,
          name: 'Упосатха',
          description: 'убывающая');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c)); // описание — часть сущности
      expect(
          a,
          isNot(SpecialDay(
              date: _d2, type: SpecialDayType.uposatha, name: 'Упосатха')));
    });
  });
}
