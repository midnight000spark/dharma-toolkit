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
  ///
  /// Экземпляр владеет собственным [TibetanMonthCache] (B-16, 5b.4):
  /// общая статическая карта порта упразднена, кэш инкапсулирован и
  /// ограничен; корректность от него не зависит (чистая функция).
  /// [monthCache] открывается тестам и composition root (шаринг кэша между
  /// инстансами — по явным причинам, не молча).
  TibetanCalendarProvider({
    required this.traditionTag,
    TibetanMonthCache? monthCache,
  }) : _months = monthCache ?? TibetanMonthCache();

  @override
  final String traditionTag;

  /// Кэш месяцев уровня инстанса (B-16); публичный геттер — чтобы тесты
  /// видели фактическое использование (мутация «кэш не передаётся» — красная).
  TibetanMonthCache get monthCache => _months;

  final TibetanMonthCache _months;

  /// Полнота пака праздников (опция B 5b.3): false — верифицированная
  /// фикс-таблица дючен и прочих дат добавится отдельным пакетом. UI обязан
  /// показывать «дата пока не проверена» вне вычисляемых дней (UX-A-4),
  /// а не «праздников нет».
  static const bool festivalsPackComplete = false;

  /// Лосар тибетского года [tibetanYear] — **первая существующая** григорианская
  /// дата 1/1 года, вычисленная обратным ходом порта [tibetanToGregorian]
  /// (Пхугпа). Год с удвоенным 1-м месяцем (1935, 1954, 2000, 2019, 2065…)
  /// начинается вставным месяцем раньше обычного: Лосар — 1/1 вставного;
  /// в 1935/1954 обычный 1/1 вовсе пропущен, а в 2084 пропущен вставной —
  /// эстафету берёт следующий инстанс. Конвенция «только обычный месяц»
  /// теряла Лосар в этих годах; в проверенном окне F-45 (2023–2027)
  /// удвоенных 1-х месяцев нет и конвенции неразличимы. Дублированная
  /// половина 1/1 (isLeapDay) праздником не считается — отметина стоит на
  /// обычном дне пары. В 1901 и 1977 1/1 не существует ни в одном из
  /// инстансов 1-го месяца (подтверждено прогоном tibcal 01591b5 — не
  /// расход порта) — для таких лет Лосар бросает [StateError], а
  /// [getSpecialDays] молча не находит 1/1 и не отмечает праздник. Вне
  /// проверенного окна дата — корректная математика порта, но не сверялась
  /// вручную (UX-A-4).
  static DateTime losarDate(int tibetanYear) {
    for (final leapMonth in [true, false]) {
      try {
        final g = tibetanToGregorian(TibetanDate(
          year: tibetanYear,
          month: 1,
          isLeapMonth: leapMonth,
          day: 1,
          isLeapDay: false,
        ));
        // Порт отдаёт DateTime.utc — время не значимо, нормализуем к
        // локальной полночи (контракт SpecialDay.date).
        return DateTime(g.year, g.month, g.day);
      } on NoSuchTibetanDayException {
        // Инстанса нет (месяц не удвоен) или 1/1 пропущен — следующий ход.
        continue;
      }
    }
    throw StateError(
        'тибетский год $tibetanYear: ни одна дата 1/1 не существует');
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
      final td = gregorianToTibetan(d, cache: _months);
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
      // Лосар (блок 2, FR-CAL-5): первая существующая дата 1/1 года по
      // [losarDate] — в год с удвоенным 1-м месяцем это 1/1 вставного, а не
      // обычного месяца. Совпадение с round-trip порта (t2g/g2t сверены
      // векторами F-45): среди инстансов 1/1 года ровно один равен losarDate,
      // поэтому заведомо один festival на тибетский год — без явного
      // подавления второго (обычного) 1/1 удвоенного года.
      if (td.month == 1 && td.day == 1 && d == losarDate(td.year)) {
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
