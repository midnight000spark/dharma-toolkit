/// Доменная модель записи ленты событий (FR-EVT-1, D-35, блок C пакета 6.1).
///
/// Одна запись = один день + один факт о нём + **атрибуция**: откуда факт взялся
/// (календарь традиции или пак событий) и подтверждён ли он. Атрибуция — часть
/// доменной модели, а не украшение UI: без неё «непроверенная дата» и
/// «вычисленный день» выглядят одинаково (UX-A-4).
library;

import '../../../core/calendar/special_day.dart';

/// Источник записи ленты.
enum FeedEntrySource {
  /// Особый день календаря активной традиции (FR-CAL-1…5) — вычислен движком.
  calendar,

  /// Запись пака событий (D-35) — данные, объявленные пресетом.
  pack,
}

/// Запись ленты: день, название и атрибуция источника.
class FeedEntry {
  /// Григорианская дата (полночь локального календарного дня).
  final DateTime date;

  /// Отображаемое имя («Упосатха (полнолуние)», «Лосар — тибетский Новый год»).
  final String title;

  /// Пояснение; может быть пустым.
  final String description;

  /// Каким путём факт попал в ленту.
  final FeedEntrySource source;

  /// Человекочитаемая атрибуция для UI: тег традиции у календарных записей,
  /// `packId` + происхождение даты (`source` записи пака) у паков.
  final String attribution;

  /// Подтверждённость даты.
  ///
  /// Календарные записи — `true`: их считает движок, сверенный векторами
  /// (F-45, 5a/5b). Паки несут честный флаг `verified` из данных (D-35);
  /// непроверенная дата обязана быть помечена и в UI (UX-A-4/I-3), иначе
  /// выдумка неотличима от эталона.
  final bool isVerified;

  /// Идентификатор пака (только для [FeedEntrySource.pack]).
  final String? packId;

  /// Идентификатор записи пака (только для [FeedEntrySource.pack]).
  final String? packEntryId;

  /// Тип особого дня календаря (только для [FeedEntrySource.calendar]).
  final SpecialDayType? specialDayType;

  const FeedEntry({
    required this.date,
    required this.title,
    required this.source,
    required this.attribution,
    required this.isVerified,
    this.description = '',
    this.packId,
    this.packEntryId,
    this.specialDayType,
  });

  @override
  String toString() =>
      'FeedEntry(${date.toIso8601String().substring(0, 10)} '
      '${source.name} "$title" ← $attribution)';
}
