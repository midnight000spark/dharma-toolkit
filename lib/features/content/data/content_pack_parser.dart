/// Разбор и валидация JSON контент-пака по схеме v1 (FR-CNT-1/2/4).
///
/// Разделение слоёв: этот файл **не читает ассеты** (это делает загрузчик,
/// `content_pack_loader.dart`) и **не зависит от Flutter** — чистая функция
/// «декодированный JSON → модель» (прецедент `EventPackParser`, D-35). Так
/// валидацию схемы можно проверять без платформы, а сломанный пак обрабатывать
/// единообразно (ассет не найден, битый JSON и невалидная схема — все три сбоя
/// живут в одном месте отчёта).
///
/// Сообщение об ошибке называет **путь проблемного поля** (`entries[2].title`),
/// а не отдаёт голый `TypeError` из недр декодирования: невалидный пак обязан
/// диагностироваться по имени поля (как в `PresetValidationException` и
/// `EventPackFormatException`).
///
/// Неизвестные поля объекта молча игнорируются: расширение пака не должно
/// ломать старую сборку.
library;

import '../domain/content_pack.dart';

/// Пак невалиден: названо поле (или путь вида `entries[2].dateRule.day`).
class ContentPackFormatException implements Exception {
  /// Путь проблемного поля.
  final String field;

  /// Почему поле не принято.
  final String reason;

  const ContentPackFormatException(this.field, this.reason);

  @override
  String toString() => 'Контент-пак невалиден: поле "$field" — $reason';
}

/// Разборщик схемы контент-пака v1. Состояния не хранит: статические функции.
abstract final class ContentPackParser {
  /// Разобрать декодированный JSON пака.
  ///
  /// Бросает [ContentPackFormatException] с путём поля при первом нарушении
  /// схемы: отсутствующее/нестроковое/пустое обязательное поле, неизвестный
  /// `dateRule.kind`, дата вне допустимых границ, дубль `entries[].id`.
  static ContentPack parse(Map<String, dynamic> json) {
    final packId = _requiredNonEmptyString(json, 'packId');
    final traditionTag = _requiredNonEmptyString(json, 'traditionTag');
    final version = _requiredNonEmptyString(json, 'version');

    final verified = json['verified'];
    if (verified == null) {
      throw const ContentPackFormatException(
          'verified', 'обязательное поле отсутствует');
    }
    if (verified is! bool) {
      throw ContentPackFormatException(
          'verified', 'ожидался bool, получен ${verified.runtimeType}');
    }

    final entriesRaw = json['entries'];
    if (entriesRaw == null) {
      throw const ContentPackFormatException(
          'entries', 'обязательное поле отсутствует');
    }
    if (entriesRaw is! List) {
      throw const ContentPackFormatException(
          'entries', 'ожидался список записей');
    }

    final entries = <ContentEntry>[];
    final seenIds = <String>{};
    for (var i = 0; i < entriesRaw.length; i++) {
      final raw = entriesRaw[i];
      if (raw is! Map) {
        throw ContentPackFormatException(
            'entries[$i]', 'ожидался объект записи');
      }
      final entry =
          _parseEntry(Map<String, dynamic>.from(raw), path: 'entries[$i]');
      if (!seenIds.add(entry.id)) {
        throw ContentPackFormatException(
          'entries[$i].id',
          'дубль идентификатора "${entry.id}": id — ключ записи, '
              'дубликат делает атрибуцию неоднозначной',
        );
      }
      entries.add(entry);
    }

    return ContentPack(
      packId: packId,
      traditionTag: traditionTag,
      version: version,
      verified: verified,
      entries: entries,
    );
  }

  static ContentEntry _parseEntry(Map<String, dynamic> json,
      {required String path}) {
    return ContentEntry(
      id: _requiredNonEmptyString(json, 'id', path: path),
      type: _requiredNonEmptyString(json, 'type', path: path),
      title: _requiredNonEmptyString(json, 'title', path: path),
      body: _requiredNonEmptyString(json, 'body', path: path),
      source: _requiredNonEmptyString(json, 'source', path: path),
      dateRule: _parseOptionalDateRule(json, '$path.dateRule'),
    );
  }

  /// `dateRule` опционален (в отличие от пака событий): текст без привязки к
  /// дате — легальная запись пула ротации. Но если поле **есть**, оно обязано
  /// быть валидным объектом правила: присутствующий, но пустой `dateRule` — это
  /// незаданный вопрос, а не «нет правила» (иначе опечатка в ключе тихо
  /// выключила бы привязку).
  static ContentDateRule? _parseOptionalDateRule(
      Map<String, dynamic> json, String path) {
    final raw = json['dateRule'];
    if (raw == null) {
      return null;
    }
    if (raw is! Map) {
      throw ContentPackFormatException(path, 'ожидался объект правила даты');
    }
    return _parseDateRule(Map<String, dynamic>.from(raw), path: path);
  }

  static ContentDateRule _parseDateRule(Map<String, dynamic> json,
      {required String path}) {
    final kindRaw = json['kind'];
    if (kindRaw == null) {
      throw ContentPackFormatException(
          '$path.kind', 'обязательное поле отсутствует');
    }
    if (kindRaw is! String) {
      throw ContentPackFormatException(
          '$path.kind', 'ожидалась строка, получен ${kindRaw.runtimeType}');
    }

    switch (kindRaw) {
      case 'tibetan':
        return TibetanContentDateRule(
          month: _intInRange(json, '$path.month', 1, 12),
          day: _intInRange(json, '$path.day', 1, 30),
        );
      case 'gregorian_yearly':
        final month = _intInRange(json, '$path.month', 1, 12);
        // Длина месяца проверяется по високосному году-образцу (2024):
        // 29 февраля — легальная ежегодная дата, 30 февраля — нет.
        final maxDay = DateTime(2024, month + 1, 0).day;
        return GregorianYearlyContentDateRule(
          month: month,
          day: _intInRange(json, '$path.day', 1, maxDay),
        );
      default:
        throw ContentPackFormatException(
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
      throw ContentPackFormatException(name, 'обязательное поле отсутствует');
    }
    if (value is! String) {
      throw ContentPackFormatException(
          name, 'ожидалась строка, получен ${value.runtimeType}');
    }
    if (value.trim().isEmpty) {
      throw ContentPackFormatException(name, 'пустая строка недопустима');
    }
    return value;
  }

  /// Целое число в границах [min]..[max] включительно.
  static int _intInRange(
      Map<String, dynamic> json, String path, int min, int max) {
    final field = path.contains('.') ? path.split('.').last : path;
    final value = json[field];
    if (value == null) {
      throw ContentPackFormatException(path, 'обязательное поле отсутствует');
    }
    if (value is! int) {
      throw ContentPackFormatException(
          path, 'ожидалось целое число, получен ${value.runtimeType}');
    }
    if (value < min || value > max) {
      throw ContentPackFormatException(
          path, 'значение $value вне диапазона $min..$max');
    }
    return value;
  }
}
