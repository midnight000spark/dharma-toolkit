/// Разбор и валидация JSON-пака событий по схеме v1 (D-35, FR-EVT-1).
///
/// Разделение слоёв: этот файл **не читает ассеты** (это делает загрузчик,
/// `event_pack_loader.dart`) и **не зависит от Flutter** — чистая функция
/// «декодированный JSON → модель». Так валидацию схемы можно проверять без
/// платформы, а сломанный пак обрабатывать единообразно (ассет не найден,
/// битый JSON и невалидная схема — все три сбоя живут в одном месте отчёта).
///
/// Сообщение об ошибке называет **путь проблемного поля** (`entries[2].name`),
/// а не отдаёт голый `TypeError` из недр декодирования: невалидный пак обязан
/// диагностироваться по имени поля (тот же приём, что в `PresetValidationException`).
///
/// Неизвестные поля объекта молча игнорируются (как в схеме пресетов):
/// расширение пака не должно ломать старую сборку.
library;

import '../domain/event_pack.dart';

/// Пак невалиден: названо поле (или путь вида `entries[2].dateRule.day`).
class EventPackFormatException implements Exception {
  /// Путь проблемного поля.
  final String field;

  /// Почему поле не принято.
  final String reason;

  const EventPackFormatException(this.field, this.reason);

  @override
  String toString() => 'Пак событий невалиден: поле "$field" — $reason';
}

/// Разборщик схемы пака v1. Состояния не хранит: чистые статические функции.
abstract final class EventPackParser {
  /// Разобрать декодированный JSON пака.
  ///
  /// Бросает [EventPackFormatException] с путём поля при первом нарушении
  /// схемы: отсутствующее/нестроковое/пустое обязательное поле, неизвестный
  /// `dateRule.kind`, дата вне допустимых границ, дубль `entries[].id`.
  static EventPack parse(Map<String, dynamic> json) {
    final packId = _requiredNonEmptyString(json, 'packId');
    final traditionTag = _requiredNonEmptyString(json, 'traditionTag');
    final version = _requiredNonEmptyString(json, 'version');

    final verified = json['verified'];
    if (verified == null) {
      throw const EventPackFormatException(
          'verified', 'обязательное поле отсутствует');
    }
    if (verified is! bool) {
      throw EventPackFormatException(
          'verified', 'ожидался bool, получен ${verified.runtimeType}');
    }

    final entriesRaw = json['entries'];
    if (entriesRaw == null) {
      throw const EventPackFormatException(
          'entries', 'обязательное поле отсутствует');
    }
    if (entriesRaw is! List) {
      throw const EventPackFormatException(
          'entries', 'ожидался список записей');
    }

    final entries = <EventPackEntry>[];
    final seenIds = <String>{};
    for (var i = 0; i < entriesRaw.length; i++) {
      final raw = entriesRaw[i];
      if (raw is! Map) {
        throw EventPackFormatException(
            'entries[$i]', 'ожидался объект записи');
      }
      final entry =
          _parseEntry(Map<String, dynamic>.from(raw), path: 'entries[$i]');
      if (!seenIds.add(entry.id)) {
        throw EventPackFormatException(
          'entries[$i].id',
          'дубль идентификатора "${entry.id}": id — ключ записи, '
              'дубликат делает атрибуцию неоднозначной',
        );
      }
      entries.add(entry);
    }

    return EventPack(
      packId: packId,
      traditionTag: traditionTag,
      version: version,
      verified: verified,
      entries: entries,
    );
  }

  static EventPackEntry _parseEntry(Map<String, dynamic> json,
      {required String path}) {
    final dateRuleRaw = json['dateRule'];
    if (dateRuleRaw == null) {
      throw EventPackFormatException(
          '$path.dateRule', 'обязательное поле отсутствует');
    }
    if (dateRuleRaw is! Map) {
      throw EventPackFormatException(
          '$path.dateRule', 'ожидался объект правила даты');
    }
    return EventPackEntry(
      id: _requiredNonEmptyString(json, 'id', path: path),
      type: _requiredNonEmptyString(json, 'type', path: path),
      name: _requiredNonEmptyString(json, 'name', path: path),
      source: _requiredNonEmptyString(json, 'source', path: path),
      dateRule: _parseDateRule(
          Map<String, dynamic>.from(dateRuleRaw), path: '$path.dateRule'),
    );
  }

  static EventDateRule _parseDateRule(Map<String, dynamic> json,
      {required String path}) {
    final kindRaw = json['kind'];
    if (kindRaw == null) {
      throw EventPackFormatException(
          '$path.kind', 'обязательное поле отсутствует');
    }
    if (kindRaw is! String) {
      throw EventPackFormatException(
          '$path.kind', 'ожидалась строка, получен ${kindRaw.runtimeType}');
    }

    switch (kindRaw) {
      case 'tibetan':
        return TibetanDateRule(
          month: _intInRange(json, '$path.month', 1, 12),
          day: _intInRange(json, '$path.day', 1, 30),
        );
      case 'gregorian_yearly':
        final month = _intInRange(json, '$path.month', 1, 12);
        // Длина месяца проверяется по високосному году-образцу (2024):
        // 29 февраля — легальная ежегодная дата, 30 февраля — нет.
        final maxDay = DateTime(2024, month + 1, 0).day;
        return GregorianYearlyDateRule(
          month: month,
          day: _intInRange(json, '$path.day', 1, maxDay),
        );
      default:
        throw EventPackFormatException(
          '$path.kind',
          'неизвестный вид правила "$kindRaw" (v1: tibetan | gregorian_yearly)',
        );
    }
  }

  /// Обязательная непустая строка; [path] задаёт префикс имени поля.
  static String _requiredNonEmptyString(
      Map<String, dynamic> json, String field,
      {String path = ''}) {
    final name = path.isEmpty ? field : '$path.$field';
    final value = json[field];
    if (value == null) {
      throw EventPackFormatException(name, 'обязательное поле отсутствует');
    }
    if (value is! String) {
      throw EventPackFormatException(
          name, 'ожидалась строка, получен ${value.runtimeType}');
    }
    if (value.trim().isEmpty) {
      throw EventPackFormatException(name, 'пустая строка недопустима');
    }
    return value;
  }

  /// Целое число в границах [min]..[max] включительно.
  static int _intInRange(
      Map<String, dynamic> json, String path, int min, int max) {
    final field = path.contains('.') ? path.split('.').last : path;
    final value = json[field];
    if (value == null) {
      throw EventPackFormatException(path, 'обязательное поле отсутствует');
    }
    if (value is! int) {
      throw EventPackFormatException(
          path, 'ожидалось целое число, получен ${value.runtimeType}');
    }
    if (value < min || value > max) {
      throw EventPackFormatException(
          path, 'значение $value вне диапазона $min..$max');
    }
    return value;
  }
}
