/// Общая тестовая уткантура контракта CalendarProvider (пакет 5b).
///
/// НЕ тестовый сюит (нет `*_test.dart` — не запускается), а хелпер:
/// валидатор контракта + фиктивный провайдер + загрузчики фикстур.
/// Used by contract, uposatha and tibetan provider tests.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dharma_toolkit/features/calendar/domain/calendar_provider.dart';
import 'package:dharma_toolkit/features/calendar/domain/special_day.dart';
import 'package:flutter_test/flutter_test.dart';

/// Фиктивный провайдер: отдаёт заранее заданный список.
class StubCalendarProvider implements CalendarProvider {
  StubCalendarProvider(this.traditionTag, this._days);

  @override
  final String traditionTag;
  final List<SpecialDay> _days;

  @override
  List<SpecialDay> getSpecialDays(DateTime from, DateTime to) =>
      List<SpecialDay>.of(_days);
}

/// Проверка контракта [CalendarProvider] на произвольной реализации.
///
/// Бросает [TestFailure], если реализация нарушает контракт:
///  * traditionTag пустой;
///  * результат не отсортирован по дате;
///  * в результате есть дни вне диапазона;
///  * есть дубли по (date, type).
void expectCalendarContract(
    CalendarProvider provider, DateTime from, DateTime to) {
  expect(provider.traditionTag, isNotEmpty,
      reason: 'traditionTag обязателен (принцип №3: тег из пресета)');
  final days = provider.getSpecialDays(from, to);
  for (var i = 1; i < days.length; i++) {
    expect(days[i - 1].date.isBefore(days[i].date) ||
        days[i - 1].date == days[i].date,
        isTrue,
        reason: 'результат должен быть отсортирован по дате');
  }
  final fromDay = DateTime(from.year, from.month, from.day);
  final toDay = DateTime(to.year, to.month, to.day);
  for (final d in days) {
    final day = DateTime(d.date.year, d.date.month, d.date.day);
    expect(!day.isBefore(fromDay) && !day.isAfter(toDay), isTrue,
        reason: '${d.date} вне диапазона $fromDay..$toDay');
  }
  final pairs = days.map((d) => (d.date, d.type)).toSet();
  expect(pairs.length, days.length,
      reason: 'дубли по (date, type) недопустимы');
}

/// Событие фазы из фикстуры astronomia (см. scripts/gen_uposatha_vectors.mjs).
class MoonVector {
  const MoonVector(this.type, this.utcDate);
  final String type; // new|first|full|last
  final DateTime utcDate;
}

/// Тест-векторы лунных фаз 2024–2026 (эталон astronomia, F-49).
List<MoonVector> loadMoonVectors() {
  final raw =
      jsonDecode(File('test/fixtures/moon_phase_vectors.json').readAsStringSync())
          as Map<String, dynamic>;
  return [
    for (final e in raw['events'] as List)
      MoonVector(
        e['type'] as String,
        DateTime.parse('${e['utcDate']}T00:00:00'),
      ),
  ];
}

/// Лосар из фикстуры tibcal (F-45): тибетский год (западный год Лосара) и
/// григорианская дата 1/1.
class LosarVector {
  const LosarVector(this.tibetanYear, this.gregorian);
  final int tibetanYear;
  final DateTime gregorian; // полночь локальная, дата из вектора
}

/// Лосары 2023–2027 из test/fixtures/tibcal_vectors.json (F-45; сверены с
/// публичными датами в 5a).
List<LosarVector> loadLosarVectors() {
  final raw =
      jsonDecode(File('test/fixtures/tibcal_vectors.json').readAsStringSync())
          as Map<String, dynamic>;
  return [
    for (final e in raw['losar'] as List)
      LosarVector(
        (e as Map<String, dynamic>)['tibetanYear'] as int,
        DateTime.parse('${e['gregorian']}T00:00:00'),
      ),
  ];
}
