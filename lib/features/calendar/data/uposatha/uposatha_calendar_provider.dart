/// Календарь упосатх — Тхеравада (FR-CAL-2, пакет 5b блок 2).
///
/// Четыре дня обета на лунный месяц: новолуние, первая четверть, полнолуние,
/// последняя четверть. День упосатхи = календарный день (UTC), полдень
/// которого ближе всех к точному моменту фазы (окно ±0.03 доли фазы,
/// ~±0.9 дня); внутри перекрывающегося окна выбирается ближайший день, так
/// что каждое событие фазы даёт ровно одну упосатху.
///
/// Конвенция дня — UTC (F-49): национальные календари (Тайland/Шри-Ланка)
/// могут сдвигать день на ±1 из-за таймзоны и вставных месяцев — допуск
/// тест-векторов это учитывает. Тхеравадский календарь в MVP показывает
/// астрономические упосатхи, а не государственные праздничные паки.
library;

import '../../domain/calendar_provider.dart';
import '../../domain/special_day.dart';
import 'moon_phase.dart';

class UposathaCalendarProvider implements CalendarProvider {
  /// [traditionTag] — тег активного пресета (`preset.id`, принцип №3/B-4);
  /// не захардкоживается здесь.
  UposathaCalendarProvider({required this.traditionTag});

  @override
  final String traditionTag;

  /// Окно распознавания фазы, в долях фазы. Суточный ход фазы ≈ 1/29.53 ≈
  /// 0.034, поэтому окно 0.03 покрывает ±~0.9 суток; перекрытие окон
  /// соседних дней снимается выбором минимума в серии (см. _uposathaDays).
  static const double _window = 0.03;

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
    final span = b.difference(a).inDays + 1; // a, b уже нормализованы к полночи
    // Для каждого целевой фазы сканируем дни окна и из непрерывной серии
    // дней-кандидатов берём ближайший к моменту фазы.
    for (final (target, label) in _targets) {
      DateTime? runStart;
      var best = 0.0;
      var bestDate = DateTime(1970);
      void flushRun() {
        if (runStart != null) {
          result.add(SpecialDay(
            date: bestDate,
            type: SpecialDayType.uposatha,
            name: 'Упосатха ($label)',
            description: 'День обета: $label (момент фазы ближайший '
                'к этому дню, UTC)',
          ));
          runStart = null;
        }
      }

      for (var i = 0; i < span; i++) {
        final d = DateTime(a.year, a.month, a.day + i);
        final phase = moonPhase(DateTime.utc(d.year, d.month, d.day, 12));
        final dist = (phase - target + 0.5) % 1.0 - 0.5; // знаковое, [-0.5;0.5)
        final abs = dist.abs();
        if (abs <= _window) {
          if (runStart == null || abs < best) {
            runStart ??= d;
            best = abs;
            bestDate = d;
          }
        } else {
          flushRun();
        }
      }
      flushRun();
    }
    return result;
  }
}
