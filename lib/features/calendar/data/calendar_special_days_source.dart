/// Источник особых дней для фичи календаря: адаптер над [CalendarProvider]
/// (D-37, пакет 6.1 блок C).
///
/// Фича календаря — единственное место, где известна связь «традиция →
/// движок»; ядро и события видят только порт [SpecialDaysSource]. Адаптер
/// добавляет к контракту календаря то, что нужно правилу `tibetan` пака
/// событий (D-35): поиск дней тибетского месяца M/D в григорианском окне.
/// Делается это тем же способом, что и в самом провайдере — обходом окна с
/// прямым вычислением тибетской даты дня ([gregorianToTibetan]); отдельный
/// «обратный» индекс не вводится, чтобы не появился второй источник истины
/// о соответствии календарей.
library;

import '../../../core/calendar/calendar_provider.dart';
import '../../../core/calendar/special_day.dart';
import '../../../core/calendar/special_days_source.dart';
import 'tibetan/tibetan_calendar.dart';
import 'tibetan/tibetan_calendar_provider.dart';

/// Источник особых дней поверх активного [CalendarProvider].
class CalendarSpecialDaysSource implements SpecialDaysSource {
  CalendarSpecialDaysSource(this._calendar);

  final CalendarProvider _calendar;

  @override
  String get traditionTag => _calendar.traditionTag;

  @override
  List<SpecialDay> getSpecialDays(DateTime from, DateTime to) =>
      _calendar.getSpecialDays(from, to);

  @override
  List<DateTime>? resolveTibetanMonthDay({
    required int month,
    required int day,
    required DateTime from,
    required DateTime to,
  }) {
    final calendar = _calendar;
    // Тибетские даты умеет только тибетский движок; лунный календарь упосатх
    // и будущие календари других традиций на такое правило отвечают отказом
    // (null), а не выдуманной датой (UX-A-4).
    if (calendar is! TibetanCalendarProvider) return null;

    final a = DateTime(from.year, from.month, from.day);
    final b = DateTime(to.year, to.month, to.day);
    if (a.isAfter(b)) {
      throw ArgumentError.value(
          '$from > $to', 'диапазон', 'начало не может быть позже конца');
    }

    final result = <DateTime>[];
    // Шаг по календарным дням через DateTime(y, m, d + 1): нормализация
    // переносов месяца/года врантайме (урок B-17: difference().inDays
    // уязвим к DST).
    for (var d = a; !d.isAfter(b);
        d = DateTime(d.year, d.month, d.day + 1)) {
      final td = gregorianToTibetan(d, cache: calendar.monthCache);
      // Пропущенный тибетский день не имеет григорианской даты и в цикл не
      // попадает — фантомных срабатываний не бывает (F-2). Двойной день
      // несёт номер на обеих половинах: обе даты возвращаются (см. контракт
      // порта).
      if (td.month == month && td.day == day) {
        result.add(d);
      }
    }
    return result;
  }
}
