/// Чтения одного календарного дня + причины, по которым чего-то нет.
///
/// Остаётся в фиче (в отличие от [ContentReading], переехавшего в ядро):
/// «день целиком с пояснениями» — деталь экрана чтения (SCR-13), а не то, что
/// нужно другим модулям; порт ядра отдаёт только чтения.
library;

import '../../../../core/content/daily_reading.dart';

/// Чтения одного дня + честные пояснения (пустота обязана объяснять себя).
class DailyReadings {
  /// Календарный день (полночь).
  final DateTime date;

  /// Чтения дня: привязанные к дате (в порядке паков), затем выбранное
  /// ротацией; при недоступности контента — единственный фолбэк.
  final List<ContentReading> readings;

  /// Пояснения дня («пак не подтверждён», «правило tibetan неразрешимо»,
  /// «показана собственная формулировка») — пользователь видит состояние,
  /// а не тихую пустоту.
  final List<String> notes;

  const DailyReadings({
    required this.date,
    required this.readings,
    this.notes = const [],
  });

  /// Есть ли что показать.
  bool get isEmpty => readings.isEmpty;

  /// Все чтения дня — фолбэк приложения (контента традиции нет вовсе).
  bool get isFallback =>
      readings.isNotEmpty &&
      readings.every((r) => r.source == ContentReadingSource.fallback);

  @override
  String toString() =>
      'DailyReadings(${date.toIso8601String().substring(0, 10)}, '
      '${readings.length} чтений, notes=${notes.length})';
}
