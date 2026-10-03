/// Ported from dorjeduck/tibcal (MIT), Phugpa algorithm after Svante Janson;
/// original license preserved (Copyright (c) 2026 Martin Dudek, MIT License).
/// Source: https://github.com/dorjeduck/tibcal public/tibetan_calendar.py,
/// class `TibetanDate` (строки 149–173).
library;

/// Один тибетский календарный день (Пхугпа).
///
/// Представление следует `TibetanDate` из tibcal: нумерация года — западный
/// год, в который попадает Лосар этого тибетского года; месяц может быть
/// удвоен ([isLeapMonth]), день может быть продублирован ([isLeapDay] —
/// первая копия повтора) или пропущен ([isSkipped] — лунный день целиком
/// внутри одного календарного дня, григорианской даты у него нет) (F-2).
///
/// Рабджунг (60-летний цикл) не хранится в дате — как в источнике, это
/// производное от [year] (см. `yearAttributes`).
class TibetanDate {
  /// Тибетский год (нумерация = западный год Лосара этого года).
  final int year;

  /// Номер месяца (1–12).
  final int month;

  /// Истина, если это вставной (удвоенный) месяц.
  final bool isLeapMonth;

  /// Лунный день (1–30).
  final int day;

  /// Истина, если это первая (вставная) копия продублированного дня.
  final bool isLeapDay;

  /// Истина, если лунный день пропущен (календарного дня нет).
  final bool isSkipped;

  /// Григорианская дата календарного дня; `null` у пропущенного дня.
  final DateTime? gregorian;

  /// Julian Day Number календарного дня, оканчивающего этот лунный день.
  final int julianDay;

  TibetanDate({
    required this.year,
    required this.month,
    required this.isLeapMonth,
    required this.day,
    required this.isLeapDay,
    this.isSkipped = false,
    this.gregorian,
    this.julianDay = 0,
  });

  // §4.1(i): `copyWith` снят — вне собственного теста у него не было
  // потребителей; тест-вектор строит нужную дату напрямую.

  @override
  bool operator ==(Object other) =>
      other is TibetanDate &&
      year == other.year &&
      month == other.month &&
      isLeapMonth == other.isLeapMonth &&
      day == other.day &&
      isLeapDay == other.isLeapDay &&
      isSkipped == other.isSkipped &&
      julianDay == other.julianDay &&
      gregorian == other.gregorian;

  @override
  int get hashCode => Object.hash(
      year, month, isLeapMonth, day, isLeapDay, isSkipped, julianDay,
      gregorian);

  @override
  String toString() => 'TibetanDate($year-$month-$day'
      '${isLeapMonth ? ' leapMonth' : ''}'
      '${isLeapDay ? ' leapDay' : ''}'
      '${isSkipped ? ' skipped' : ''}'
      '${gregorian != null ? ' -> ${gregorian!.toIso8601String()}' : ''})';
}
