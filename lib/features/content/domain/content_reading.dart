/// Доменная модель чтения дня (FR-CNT-1/3/4, блок B пакета 7.0).
///
/// Одно чтение = дата + текст + **атрибуция**: откуда текст взялся и
/// подтверждён ли он. Атрибуция — часть доменной модели, а не украшение UI
/// (UX-A-4): без неё «текст из проверенного пака» и «собственная формулировка
/// приложения» выглядят одинаково, а для контента это ещё и правовой вопрос —
/// пользователь обязан видеть происхождение текста (FR-CNT-4).
library;

/// Откуда взялось чтение.
enum ContentReadingSource {
  /// Текст из контент-пака (данные, объявленные пресетом) — FR-CNT-2.
  pack,

  /// Собственная краткая формулировка приложения — фолбэк FR-CNT-3, когда
  /// контент-пака для традиции нет вовсе.
  fallback,
}

/// Чтение дня: текст с датой и атрибуцией.
class ContentReading {
  /// Календарный день (полночь локального дня).
  final DateTime date;

  /// Заголовок чтения.
  final String title;

  /// Текст, который видит пользователь.
  final String body;

  /// Человекочитаемая атрибуция: `packId` + происхождение текста для паков,
  /// прямое признание фолбэка для собственной формулировки.
  final String attribution;

  /// Подтверждён ли текст первоисточником/эталоном.
  ///
  /// Для пака — честный флаг `verified` из данных (D-35). Для фолбэка —
  /// **`false`**: собственная формулировка не является проверенным текстом
  /// традиции, и выдавать её за таковой значило бы врать пользователю. Два
  /// независимых сигнала честности ([source] и [isVerified]) видит UI.
  final bool isVerified;

  /// Каким путём чтение попало в день.
  final ContentReadingSource source;

  /// Привязано ли чтение к дню правилом пака (`dateRule`), а не выбрано
  /// ротацией. Привязанные чтения идут первыми: они — «то самое» чтение дня,
  /// ротация — альтернатива для кнопки «Другое чтение» (SCR-13).
  final bool isDateBound;

  /// Идентификатор пака (только для [ContentReadingSource.pack]).
  final String? packId;

  /// Идентификатор записи пака (только для [ContentReadingSource.pack]).
  final String? entryId;

  const ContentReading({
    required this.date,
    required this.title,
    required this.body,
    required this.attribution,
    required this.isVerified,
    required this.source,
    this.isDateBound = false,
    this.packId,
    this.entryId,
  });

  @override
  String toString() => 'ContentReading(${date.toIso8601String().substring(0, 10)} '
      '${source.name} "$title" ← $attribution)';
}

/// Чтения одного дня + причины, по которым чего-то нет (честная пустота).
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
  String toString() => 'DailyReadings(${date.toIso8601String().substring(0, 10)}, '
      '${readings.length} чтений, notes=${notes.length})';
}
