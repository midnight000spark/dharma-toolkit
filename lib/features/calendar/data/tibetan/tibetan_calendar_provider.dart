/// Календарь тибетской традиции (Пхугпа) — Ньингма и другие школы, живущие
/// по тибетскому календарю (FR-CAL-3, пакет 5b блок 3).
///
/// Построен поверх порта tibcal 5a (MIT, Янсон arXiv:1401.6285; D-18 —
/// арифметика Rational/BigInt, `double` в расчётном пути запрещён I-1).
/// Реализация ничего не считает сама: обходит григорианские дни диапазона,
/// конвертирует каждый порта-функцией [gregorianToTibetan] и размечает
/// особые дни. Порт сверен с tibcal на 731 векторе (F-45) — даты особых
/// дней внутри проверенного окна наследуют эту точность.
///
/// Пакет праздников (блок 3, опция B): кроме вычисляемых 10/25 и Лосара
/// традиции знает и другие праздничные дни (дючены и т.п.). Их верифицированный
/// источник в 5b.3 недоступен — Tier-0 клоны (tibcal, date-tibetan) паков
/// праздников не содержат, а опция A пакета веб-инструменты запрещает, —
/// поэтому они вынесены в отдельный пакет. Флаг [festivalsPackComplete]
/// сообщает UI честный статус «данные о праздниках ещё не проверены»,
/// а не «праздников нет» (UX-A-4).
library;

import '../../domain/calendar_provider.dart';
import '../../domain/special_day.dart';
import 'tibetan_calendar.dart';
import 'tibetan_date.dart';

class TibetanCalendarProvider implements CalendarProvider {
  /// [traditionTag] — тег активного пресета (`preset.id`, принцип №3/B-4):
  /// приходит из конструктора, как у `UposathaCalendarProvider`; литералом
  /// внутри класса не захардкоживается (скелет пакета 5b.3 с `'nyingma'`
  /// заменён параметром — контракт 5b.1 прямо требует тег из пресета).
  TibetanCalendarProvider({required this.traditionTag});

  @override
  final String traditionTag;

  /// Полнота пака праздников (опция B 5b.3): false — верифицированная
  /// фикс-таблица дючен и прочих дат добавится отдельным пакетом. UI обязан
  /// показывать «дата пока не проверена» вне вычисляемых дней (UX-A-4),
  /// а не «праздников нет».
  static const bool festivalsPackComplete = false;

  /// Лосар тибетского года [tibetanYear] — григорианская дата 1/1 обычного
  /// (не вставного) первого месяца, вычисленная прямым ходом порта
  /// [tibetanToGregorian] (Пхугпа; не путать с удвоенным месяцем: вставной
  /// 1-й месяц Лосаром не является). Фикстура F-45 (Лосары 2023–2027,
  /// сверенные с публичными датами) — эталон точности; вне проверенного
  /// окна дата остаётся корректной математикой порта, но не сверялась
  /// вручную (UX-A-4).
  static DateTime losarDate(int tibetanYear) {
    // Порт отдаёт DateTime.utc — время не значимо, нормализуем к локальной
    // полночи (контракт SpecialDay.date).
    final g = tibetanToGregorian(TibetanDate(
      year: tibetanYear,
      month: 1,
      isLeapMonth: false,
      day: 1,
      isLeapDay: false,
    ));
    return DateTime(g.year, g.month, g.day);
  }

  @override
  List<SpecialDay> getSpecialDays(DateTime from, DateTime to) {
    final a = DateTime(from.year, from.month, from.day);
    final b = DateTime(to.year, to.month, to.day);
    if (a.isAfter(b)) {
      throw ArgumentError.value(
          '$from > $to', 'диапазон', 'начало не может быть позже конца');
    }
    final result = <SpecialDay>[];
    // Шаг по календарным дням через DateTime(y, m, d + 1): нормализация
    // переносов месяца/года врантайме, счётчик whole-days не используется
    // (урок B-17: difference().inDays уязвим к DST).
    for (var d = a; !d.isAfter(b);
        d = DateTime(d.year, d.month, d.day + 1)) {
      final td = gregorianToTibetan(d);
      // Дни 10/25 (FR-CAL-3): подсветка по номеру лунного дня. Двойной день
      // (isLeapDay) — обе половины несут номер, обе размечаются; пропущенный
      // лунный день не имеет григорианской даты и в цикл не попадает —
      // фантомная подсветка структурно невозможна (блок 4, F-2).
      if (td.day == 10) {
        result.add(SpecialDay(
          date: d,
          type: SpecialDayType.tibetan10,
          name: '10-й день тибетского месяца',
          description: 'Полусамоцветный день (лунный день 10), календарь Пхугпа',
        ));
      } else if (td.day == 25) {
        result.add(SpecialDay(
          date: d,
          type: SpecialDayType.tibetan25,
          name: '25-й день тибетского месяца',
          description: 'Полусамоцветный день (лунный день 25), календарь Пхугпа',
        ));
      }
      // Лосар (блок 2, FR-CAL-5): 1/1 обычного месяца. Совпадение с
      // [losarDate] обеспечивается round-trip-consistency порта
      // (t2g/g2t сверены векторами F-45).
      if (td.month == 1 &&
          td.day == 1 &&
          !td.isLeapMonth &&
          !td.isLeapDay) {
        result.add(SpecialDay(
          date: d,
          type: SpecialDayType.festival,
          name: 'Лосар — тибетский Новый год',
          description:
              '1-й день 1-го месяца тибетского года ${td.year} (календарь Пхугпа)',
        ));
      }
    }
    // Отсортирован по построению: цикл идёт по возрастанию дат.
    return result;
  }
}
