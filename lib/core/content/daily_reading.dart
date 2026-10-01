/// Контрактные типы чтения дня (D-37-аналог, блок C пакета 7.0).
///
/// **Почему тип лежит в ядре, а не в фиче.** Чтение дня — то, что видят и
/// дашборд, и экран «Чтение дня» (SCR-7/SCR-13), а они живут вне `features/content`;
/// прямой импорт feature→feature запрещён конституцией (принцип №1, guard-тест
/// R-10), а объявить тип дважды — второй источник истины (класс B-4/R-20).
/// Единственное легальное направление — общий контракт в ядре. Это ровно тот
/// ход, который D-37 сделал для календаря (`SpecialDay` переехал в
/// `lib/core/calendar/`), и он повторён здесь для контента: в ядре — **только
/// значение**, реализации и логика остаются в `features/content`.
///
/// Ядро остаётся чистым: эти типы не зависят ни от Flutter, ни от фич.
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
  String toString() =>
      'ContentReading(${date.toIso8601String().substring(0, 10)} '
      '${source.name} "$title" ← $attribution)';
}

/// Чтения одного календарного дня + честные пояснения (пустота обязана
/// объяснять себя).
///
/// Живёт в ядре рядом с [ContentReading], потому что является значением порта
/// `ContentSource`: порт обязан отдавать потребителю (дашборд SCR-7, экран
/// SCR-13) не только тексты, но и **пользовательские пояснения** ([notes],
/// C8г) — проекция «только список чтений» молча теряла их (W22, блок
/// warning-3c). Один тип на порт и ленту фичи — не два источника истины
/// (класс B-4/R-20).
class DailyReadings {
  /// Календарный день (полночь).
  final DateTime date;

  /// Чтения дня: привязанные к дате (в порядке паков), затем выбранное
  /// ротацией; при недоступности контента — единственный фолбэк.
  final List<ContentReading> readings;

  /// Пояснения дня («пак не подтверждён», «правило tibetan неразрешимо»,
  /// «показана собственная формулировка», сбой пака) — пользователь видит
  /// состояние, а не тихую пустоту. Без внутренних путей и id (C8г).
  final List<String> notes;

  /// Техническая диагностика дня: пути ассетов, пути полей, сырые причины
  /// (C8б). В UI не показывается; пустой список — нечего диагностировать.
  final List<String> debugNotes;

  const DailyReadings({
    required this.date,
    required this.readings,
    this.notes = const [],
    this.debugNotes = const [],
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
