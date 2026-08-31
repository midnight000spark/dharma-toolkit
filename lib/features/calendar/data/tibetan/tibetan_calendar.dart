/// Ported from dorjeduck/tibcal (MIT), Phugpa algorithm after Svante Janson;
/// original license preserved (Copyright (c) 2026 Martin Dudek, MIT License).
///
/// Источник: https://github.com/dorjeduck/tibcal
///  * public/tibetan_calendar.py — алгоритм (Янсон, arXiv:1401.6285, Пхугпа
///    эпохи E806);
///  * public/convert.py L45–79 — именование годов (рабджунг/животное/элемент).
///
/// Портируется только tibcal (I-2): GPL-реализации (lscalendars/tibcalendar,
/// F-20) не читались при написании этого файла. Tsurphu-ветка источника
/// (tibetan_calendar.py L86–101) не портирована — вне MVP-скоупа (D-23).
///
/// Вся арифметика — точные дроби [Rational] поверх BigInt (D-18, I-1):
/// `double` в формулах запрещён, цена ошибки — сдвиг пропущенного/двойного
/// дня (F-2).
library;

import 'package:dharma_toolkit/features/calendar/data/tibetan/rational.dart';
import 'package:dharma_toolkit/features/calendar/data/tibetan/tibetan_date.dart';

/// Исключение: запрошенного тибетского календарного дня не существует
/// (пропущенный лунный день) или он не найден при обратном ходе.
///
/// Соответствует `ValueError("skipped ... / not found")` в
/// tibetan_calendar.py L323–337.
class NoSuchTibetanDayException implements Exception {
  /// Человекочитаемое описание несуществующего дня.
  final String message;

  NoSuchTibetanDayException(this.message);

  @override
  String toString() => 'NoSuchTibetanDayException: $message';
}

// --- Константы Пхугпа (tibetan_calendar.py L43–80, Янсон §3–5) --------------

/// Набор точных рациональных констант и правил вставных месяцев одной
/// традиции (аналог `_Constants`, tibetan_calendar.py L43–60).
class _PhugpaConstants {
  final int year0; // epoch Gregorian year (Y0)
  final int month0; // epoch month number (M0, всегда 3 — Remark 3)
  final int betaStar; // intercalation phase constant (beta*)
  final Rational m1; // средняя длительность лунного месяца (дней)
  final Rational m2; // средняя длительность лунного дня (= m1 / 30)
  final Rational m0; // средняя дата, эпохальная константа (JDN)
  final Rational s1; // среднее солнечное движение за месяц (доля круга)
  final Rational s2; // (= s1 / 30)
  final Rational s0; // эпохальная константа среднего солнца
  final Rational a1; // лунная аномалия за месяц
  final Rational a2; // лунная аномалия за лунный день
  final Rational a0; // эпохальная константа лунной аномалии
  final Set<int> leapIx; // индексы интеркаляции, помечающие вставной месяц
  final int roundOffset; // +17 для Пхугпа (Янсон 5.10)

  _PhugpaConstants({
    required this.year0,
    required this.month0,
    required this.betaStar,
    required this.m1,
    required this.m2,
    required this.m0,
    required this.s1,
    required this.s2,
    required this.s0,
    required this.a1,
    required this.a2,
    required this.a0,
    required this.leapIx,
    required this.roundOffset,
  });
}

/// Пхугпа, эпоха E806 (Y0 = 806, M0 = 3). Константы дословно из
/// tibetan_calendar.py L65–80 (Янсон §3–5; правило вставок (5.8)/(5.10)).
final _phugpa = _PhugpaConstants(
  year0: 806,
  month0: 3,
  betaStar: 61,
  m1: Rational.div(167025, 5656),
  m2: Rational.div(167025, 5656) / Rational.fromInt(30),
  m0: Rational.fromInt(2015501) + Rational.div(4783, 5656),
  s1: Rational.div(65, 804),
  s2: Rational.div(65, 804) / Rational.fromInt(30),
  s0: Rational.div(743, 804),
  a1: Rational.div(253, 3528),
  a2: Rational.div(1, 28),
  a0: Rational.div(475, 3528),
  leapIx: const {48, 49},
  roundOffset: 17,
);

// Julian Day Number пролептического григорианского 0001-01-01 минус 1
// (jdn − _jdnGregorianOffset == порядковый номер дня, как date.toordinal()).
// Проверено: Gregorian 2000-01-01 == JDN 2451545 == ordinal 730120
// (tibetan_calendar.py L30–33).
const int _jdnGregorianOffset = 1721425;

// --- Табличные поправки (tibetan_calendar.py L103–133, Янсон §4) ------------

// Таблица лунной поправки, базовые значения для аргументов 0..7.
// Период 28, антисимметрия относительно 14: tab(14−i)=tab(i), tab(14+i)=−tab(i).
const List<int> _moonTabBase = [0, 5, 10, 15, 19, 22, 24, 25];

// Таблица солнечной поправки, базовые значения для аргументов 0..3.
// Период 12, антисимметрия относительно 6.
const List<int> _sunTabBase = [0, 6, 10, 11];

/// Целочисленное лунное табличное значение при аргументе `i` (mod 28).
/// Порт `_moon_tab` (tibetan_calendar.py L112–121).
int _moonTab(int i) {
  final k = _floorMod(i, 28);
  if (k <= 7) return _moonTabBase[k];
  if (k <= 14) return _moonTabBase[14 - k];
  if (k <= 21) return -_moonTabBase[k - 14];
  return -_moonTabBase[28 - k];
}

/// Целочисленное солнечное табличное значение при аргументе `i` (mod 12).
/// Порт `_sun_tab` (tibetan_calendar.py L124–133).
int _sunTab(int i) {
  final k = _floorMod(i, 12);
  if (k <= 3) return _sunTabBase[k];
  if (k <= 6) return _sunTabBase[6 - k];
  if (k <= 9) return -_sunTabBase[k - 6];
  return -_sunTabBase[12 - k];
}

/// Линейная интерполяция табличной поправки в дробной точке `arg`
/// (порт `_interp`, tibetan_calendar.py L136–142).
Rational _interp(Rational arg, int Function(int) table) {
  final lo = arg.floor().toInt();
  final frac = arg - Rational.fromInt(lo);
  final a = Rational.fromInt(table(lo));
  final b = Rational.fromInt(table(lo + 1));
  return a + (b - a) * frac;
}

// --- Астрономия дня (tibetan_calendar.py L185–197) ---------------------------

/// JDN календарного дня, оканчивающего лунный день `d` истинного месяца `n`
/// (Янсон §5: floor от `true_date`; порт `_true_jdn`).
int _trueJdn(int d, int n) {
  final c = _phugpa;
  final rn = Rational.fromInt(n);
  final rd = Rational.fromInt(d);

  final meanDate = c.m1 * rn + c.m2 * rd + c.m0;
  final meanSun = c.s1 * rn + c.s2 * rd + c.s0;
  final anomalyMoon = c.a1 * rn + c.a2 * rd + c.a0;
  final anomalySun = meanSun - Rational.div(1, 4);

  // (anomaly % 1) * период — floor-мод, знак остатка неотрицательный
  // (дублирует Fraction % 1 источника, L193–194).
  final moonEqu =
      _interp(anomalyMoon.fractionalPart() * Rational.fromInt(28), _moonTab);
  final sunEqu =
      _interp(anomalySun.fractionalPart() * Rational.fromInt(12), _sunTab);

  final trueDate = meanDate +
      moonEqu / Rational.fromInt(60) -
      sunEqu / Rational.fromInt(60);
  return trueDate.floor().toInt();
}

// --- Месяцы и их экземпляры (tibetan_calendar.py L200–242) ------------------

/// Экземпляры истинных месяцев для пары `(год, месяц)` тибетского календаря:
/// `(n, isLeap)`, где `n` — счётчик истинных месяцев от эпохи.
///
/// Обычный месяц даёт один экземпляр; удвоенный по правилу интеркаляции —
/// сначала вставной `(n, true)`, затем обычный `(n + 1, false)`
/// (порт `_month_instances`, L200–213).
List<(int, bool)> _monthInstances(int year, int month) {
  final c = _phugpa;
  final mStar = 12 * (year - c.year0) + month - c.month0;
  final ix = _floorMod(2 * mStar + c.betaStar, 65);
  final isLeap = c.leapIx.contains(ix);
  // Python `//` — floor-деление; эквивалент для положительного делителя.
  var n = _floorDiv(67 * mStar + c.betaStar + c.roundOffset, 65);
  if (isLeap) n -= 1;
  if (isLeap) {
    return [(n, true), (n + 1, false)];
  }
  return [(n, false)];
}

/// Кэш [_buildMonth]: чистая функция, переиспользуется окном g2t в ±1 год.
final Map<(int, int, int, bool), List<TibetanDate>> _monthCache = {};

/// Все лунные дни 1–30 месяца `(year, month)` с разрешением пропусков и
/// дублирований (порт `_build_month`, L216–242).
List<TibetanDate> _buildMonth(int year, int month, int n, bool isLeap) {
  final key = (year, month, n, isLeap);
  final cached = _monthCache[key];
  if (cached != null) return cached;

  // JDN календарного дня, оканчивающего каждый лунный день 0..30
  // (0 = конец предыдущего месяца).
  final jdn = List<int>.generate(31, (d) => _trueJdn(d, n));

  final days = <TibetanDate>[];
  for (var d = 1; d <= 30; d++) {
    final prev = jdn[d - 1];
    final cur = jdn[d];
    if (cur == prev) {
      // Лунный день целиком внутри одного календарного дня — пропущен,
      // календарной даты нет.
      days.add(TibetanDate(
          year: year,
          month: month,
          isLeapMonth: isLeap,
          day: d,
          isLeapDay: false,
          isSkipped: true,
          julianDay: cur));
      continue;
    }
    if (cur - prev >= 2) {
      // Дублирование: лишний календарный день несёт этот номер первым
      // (вставной день), затем обычный.
      final leapJdn = prev + 1;
      days.add(TibetanDate(
          year: year,
          month: month,
          isLeapMonth: isLeap,
          day: d,
          isLeapDay: true,
          gregorian: _dateFromOrdinal(leapJdn - _jdnGregorianOffset),
          julianDay: leapJdn));
    }
    days.add(TibetanDate(
        year: year,
        month: month,
        isLeapMonth: isLeap,
        day: d,
        isLeapDay: false,
        gregorian: _dateFromOrdinal(cur - _jdnGregorianOffset),
        julianDay: cur));
  }
  _monthCache[key] = days;
  return days;
}

// --- Публичные конверсии (tibetan_calendar.py L279–337) ----------------------

/// Григорианская дата -> тибетский календарный день (Пхугпа).
///
/// Порт `gregorian_to_tibetan` (L279–303): перебирает месяцы трёхлетнего
/// окна и возвращает первый непровпущенный день с совпавшим JDN.
/// Пропущенных лунных дней в результате не бывает (у них нет календарного
/// дня); бросает [StateError], если день не найден (в источнике —
/// «should not occur»).
TibetanDate gregorianToTibetan(DateTime g) {
  final target = _ordinalFromDate(g.year, g.month, g.day) +
      _jdnGregorianOffset;
  for (final y in [g.year - 1, g.year, g.year + 1]) {
    for (var m = 1; m <= 12; m++) {
      for (final (n, isLeap) in _monthInstances(y, m)) {
        for (final td in _buildMonth(y, m, n, isLeap)) {
          if (td.julianDay == target && !td.isSkipped) {
            return td;
          }
        }
      }
    }
  }
  throw StateError(
      'no Tibetan calendar day maps to ${g.year}-${g.month}-${g.day}');
}

/// Тибетская дата -> григорианская (Пхугпа).
///
/// Порт `tibetan_to_gregorian` (L306–337). Используются только year, month,
/// day, isLeapMonth, isLeapDay. Пропущенный лунный день, а также
/// несуществующая комбинация (например, leapDay=true на nonduplicated дне)
/// бросают [NoSuchTibetanDayException]. Двойной день: `isLeapDay` false/true
/// различаются и дают две разные григорианские даты (F-2).
DateTime tibetanToGregorian(TibetanDate t) {
  if (t.isSkipped) {
    throw NoSuchTibetanDayException(
        'skipped Tibetan day ${t.year}-${t.month}-${t.day} has no Gregorian '
        'date');
  }
  for (final (n, isLeap) in _monthInstances(t.year, t.month)) {
    if (isLeap != t.isLeapMonth) continue;
    for (final td in _buildMonth(t.year, t.month, n, isLeap)) {
      if (td.day == t.day &&
          td.isLeapDay == t.isLeapDay &&
          td.gregorian != null) {
        return td.gregorian!;
      }
    }
  }
  throw NoSuchTibetanDayException(
      'Tibetan date ${t.year}-${t.month}-${t.day} '
      '(leapMonth=${t.isLeapMonth}, leapDay=${t.isLeapDay}) not found');
}

// --- Именование годов (convert.py L34–79) -----------------------------------

// Массивы и эпохи — дословно convert.py L45–53; это константы самой системы
// счисления, не свободные параметры (проверенные якоря в источнике:
// 2020 = Iron-Rat, 2024 = Wood-Dragon, 2026 = Fire-Horse).
const List<String> _animalsList = [
  'Rat', 'Ox', 'Tiger', 'Hare', 'Dragon', 'Snake',
  'Horse', 'Sheep', 'Monkey', 'Bird', 'Dog', 'Pig'
];
const List<String> _elementsList = ['Wood', 'Fire', 'Earth', 'Iron', 'Water'];
const int _rabjungEpoch = 1027; // Григорианский год 1-го года 1-го рабджунга (Fire-Hare).
const int _animalEpoch = 2020; // Iron-Rat: фаза 12-летия животных.
const int _elementEpoch = 2024; // Wood-Dragon: фаза 5-элементного (×2) цикла.
const int _royalOffset = 127; // Тибетский царский год (Bod rGyal lo) = год + 127.

/// Атрибуты тибетского года: элемент/животное/пол, рабджунг, царский год.
class YearAttributes {
  /// Тибетский год (западный год Лосара).
  final int tibetanYear;

  /// Wood / Fire / Earth / Iron / Water.
  final String element;

  /// Rat … Pig.
  final String animal;

  /// male / female (первый год пары элементов — male).
  final String gender;

  /// Номер рабджунга (60-летнего цикла), 1-based.
  final int rabjungCycle;

  /// Царский год (Bod rGyal lo).
  final int royalYear;

  /// Диапазон западных лет, которые покрывает год Лосар-до-Лосара ("2026/27").
  final String span;

  /// Полное имя ("Fire Male Horse").
  final String fullName;

  YearAttributes({
    required this.tibetanYear,
    required this.element,
    required this.animal,
    required this.gender,
    required this.rabjungCycle,
    required this.royalYear,
    required this.span,
    required this.fullName,
  });

  @override
  bool operator ==(Object other) =>
      other is YearAttributes &&
      tibetanYear == other.tibetanYear &&
      fullName == other.fullName &&
      rabjungCycle == other.rabjungCycle &&
      royalYear == other.royalYear;

  @override
  int get hashCode =>
      Object.hash(tibetanYear, fullName, rabjungCycle, royalYear);

  @override
  String toString() =>
      'YearAttributes($span $fullName, rabjung $rabjungCycle, royal $royalYear)';
}

/// Тибетское имя года для тибетского года `tibetanYear`
/// (порт `year_name`, convert.py L56–79).
///
/// От нумерации годов источника (`TibetanDate.year`) — тот же западный год
/// Лосара. Tradition-independent (convert.py L143).
YearAttributes yearAttributes(int tibetanYear) {
  final animal = _animalsList[_floorMod(tibetanYear - _animalEpoch, 12)];
  final element =
      _elementsList[_floorMod(tibetanYear - _elementEpoch, 10) ~/ 2];
  final gender =
      _floorMod(tibetanYear - _elementEpoch, 2) == 0 ? 'male' : 'female';
  final rabjungCycle =
      _floorDiv(tibetanYear - _rabjungEpoch, 60) + 1;
  final span =
      '$tibetanYear/${((tibetanYear + 1) % 100).toString().padLeft(2, '0')}';
  final capitalized =
      gender[0].toUpperCase() + gender.substring(1);
  final fullName = '$element $capitalized $animal';
  return YearAttributes(
    tibetanYear: tibetanYear,
    element: element,
    animal: animal,
    gender: gender,
    rabjungCycle: rabjungCycle,
    royalYear: tibetanYear + _royalOffset,
    span: span,
    fullName: fullName,
  );
}

// --- Вспомогательная целочисленная семантика Python --------------------------

/// Floor-остаток для положительного делителя (Python `%`).
int _floorMod(int a, int b) => a % b; // Dart % уже даёт 0 <= r < b при b > 0.

/// Floor-деление для положительного делителя (Python `//`).
int _floorDiv(int a, int b) => (a - _floorMod(a, b)) ~/ b;

// --- Григорианский ordinal (эквивалент Python date.toordinal) ----------------

/// Порядковый номер дня пролептического григорианского календаря
/// (0001-01-01 == 1, Python `date.toordinal`). Алгоритм — days_from_civil
/// Ховарда Хиннанта; сверен с источником на 2000-01-01 -> 730120 (L32).
int _ordinalFromDate(int y, int m, int d) =>
    _daysFromCivil(y, m, d) + 719163;

/// Обратный ход: ordinal -> UTC-дата (порт `date.fromordinal`).
DateTime _dateFromOrdinal(int ordinal) {
  final (y, m, d) = _civilFromDays(ordinal - 719163);
  return DateTime.utc(y, m, d);
}

int _daysFromCivil(int y, int m, int d) {
  final yy = m <= 2 ? y - 1 : y;
  final era = _floorDiv(yy, 400);
  final yoe = yy - era * 400; // [0, 399]
  final mp = (m + (m > 2 ? -3 : 9)); // [0, 11]
  final doy = _floorDiv(153 * mp + 2, 5) + d - 1; // [0, 365]
  final doe = yoe * 365 + _floorDiv(yoe, 4) - _floorDiv(yoe, 100) + doy;
  // [0, 146096]; сдвиг эпохи: 1970-01-01
  return era * 146097 + doe - 719468;
}

(int, int, int) _civilFromDays(int z0) {
  final z = z0 + 719468;
  final era = _floorDiv(z, 146097);
  final doe = z - era * 146097; // [0, 146096]
  final yoe = _floorDiv(
      doe - _floorDiv(doe, 1460) + _floorDiv(doe, 36524) -
          _floorDiv(doe, 146096),
      365); // [0, 399]
  final y = yoe + era * 400;
  final doy =
      doe - (365 * yoe + _floorDiv(yoe, 4) - _floorDiv(yoe, 100)); // [0, 365]
  final mp = _floorDiv(5 * doy + 2, 153); // [0, 11]
  final d = doy - _floorDiv(153 * mp + 2, 5) + 1; // [1, 31]
  final m = mp + (mp < 10 ? 3 : -9); // [1, 12]
  return (y + (m <= 2 ? 1 : 0), m, d);
}
