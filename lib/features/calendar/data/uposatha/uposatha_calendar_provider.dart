/// Календарь упосатх — Тхеравада (FR-CAL-2, пакет 5b блок 2).
///
/// Четыре дня обета на лунный месяц: новолуние, первая четверть, полнолуние,
/// последняя четверть. День упосатхи = календарный день (UTC), полдень
/// которого ближе всех к точному моменту фазы; иначе: календарный день, в
/// который произошло пересечение целевой фазы. Событие определяется
/// **бисекцией по знаковому расстоянию фазы до цели** в расширенном на ±2 дня
/// окне (C5), поэтому результат не зависит от границ запроса: годовой прогон
/// равен склейке помесячных (раньше падинг окна ±0.03 обрезал серию
/// кандидатов на границах и терял дни — «2026-11-30» и др.).
///
/// Конвенция дня — UTC (F-49): национальные календари (Тайланд/Шри-Ланка)
/// могут сдвигать день на ±1 из-за таймзоны и вставных месяцев — допуск
/// тест-векторов это учитывает. Тхеравадский календарь в MVP показывает
/// астрономические упосатхи, а не государственные праздничные паки.
library;

import '../../../../core/calendar/calendar_provider.dart';
import '../../../../core/calendar/special_day.dart';
import 'moon_phase.dart';

class UposathaCalendarProvider implements CalendarProvider {
  /// [traditionTag] — тег активного пресета (`preset.id`, принцип №3/B-4);
  /// не захардкоживается здесь.
  UposathaCalendarProvider({required this.traditionTag});

  @override
  final String traditionTag;

  static const List<(double, String)> _targets = [
    (0.0, 'новолуние'),
    (0.25, 'первая четверть'),
    (0.5, 'полнолуние'),
    (0.75, 'последняя четверть'),
  ];

  @override
  List<SpecialDay> getSpecialDays(DateTime from, DateTime to) {
    final a = DateTime(from.year, from.month, from.day);
    final b = DateTime(to.year, to.month, to.day);
    if (a.isAfter(b)) {
      throw ArgumentError.value(
          '$from > $to', 'диапазон', 'начало не может быть позже конца');
    }
    final days = _uposathaDays(a, b);
    days.sort((x, y) => x.date.compareTo(y.date));
    return days;
  }

  List<SpecialDay> _uposathaDays(DateTime a, DateTime b) {
    final result = <SpecialDay>[];
    for (final (target, label) in _targets) {
      result.addAll(_daysForTarget(a, b, target, label));
    }
    return result;
  }

  /// Упосатхи фазы [target] для диапазона [a, b]: по одной на каждое
  /// пересечение цели в расширенном окне [a−2, b+2] (C5).
  ///
  /// Расширение нужно потому, что ближайший день пересечения может лежать
  /// внутри запрошенного диапазона, тогда как само пересечение — у его
  /// границы; фильтр `[a, b]` оставляет ровно дни запроса. Ход — календарной
  /// арифметикой `DateTime(y, m, d + 1)`, а не счётчиком дней: DST-таймзона
  /// spring-forward урезала бы окно на час (B-17).
  List<SpecialDay> _daysForTarget(
      DateTime a, DateTime b, double target, String label) {
    final days = <SpecialDay>[];
    DateTime? prevNoon;
    double? prevDist;

    DateTime shift(DateTime d, int n) =>
        DateTime(d.year, d.month, d.day + n);

    for (var d = shift(a, -2); !d.isAfter(shift(b, 2)); d = shift(d, 1)) {
      final noon = DateTime.utc(d.year, d.month, d.day, 12);
      final dist = _signedDistance(noon, target);
      // Ход фазы положителен: пересечение цели — переход − → +.
      // Разрыв +0.5 → −0.5 (анти-цель) даёт обратный знак и не ловится.
      if (prevDist != null && prevDist < 0 && dist >= 0) {
        final crossing = _bisectCrossing(prevNoon!, noon, target);
        final day = DateTime(
            crossing.year, crossing.month, crossing.day); // день (UTC) события
        if (!day.isBefore(a) && !day.isAfter(b)) {
          days.add(SpecialDay(
            date: day,
            type: SpecialDayType.uposatha,
            name: 'Упосатха ($label)',
            description: 'День обета: $label (момент фазы ближайший '
                'к этому дню, UTC)',
          ));
        }
      }
      prevNoon = noon;
      prevDist = dist;
    }
    return days;
  }

  /// Знаковое расстояние фазы до цели, в долях фазы `[-0.5, 0.5)`:
  /// около цели локально монотонно растёт через ноль (C5).
  static double _signedDistance(DateTime moment, double target) =>
      (moonPhase(moment) - target + 0.5) % 1.0 - 0.5;

  /// Момент пересечения цели между полуднями [lo] (dist < 0) и [hi]
  /// (dist ≥ 0); бисекция по знаковому расстоянию до секунды.
  static DateTime _bisectCrossing(DateTime lo, DateTime hi, double target) {
    var l = lo.millisecondsSinceEpoch;
    var h = hi.millisecondsSinceEpoch;
    while (h - l > 1000) {
      final mid = l + (h - l) ~/ 2;
      final dist = _signedDistance(
          DateTime.fromMillisecondsSinceEpoch(mid, isUtc: true), target);
      if (dist < 0) {
        l = mid;
      } else {
        h = mid;
      }
    }
    return DateTime.fromMillisecondsSinceEpoch(h, isUtc: true);
  }
}
