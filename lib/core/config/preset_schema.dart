/// Preset невалиден (6.3): валидная ошибка с именем проблемного поля вместо
/// голого TypeError из недр декодирования JSON.
class PresetValidationException implements Exception {
  /// Имя поля (или путь вида `practices[0].id`), на котором споткнулась
  /// валидация.
  final String field;
  final String reason;

  const PresetValidationException(this.field, this.reason);

  @override
  String toString() => 'Пресет невалиден: поле "$field" — $reason';
}

/// Schema for JSON preset files v1. Describes configuration for a tradition.
///
/// Validated when loading from assets. Contains preset practices, event packs,
/// and content packs.
///
/// **moduleConfigs исключён из схемы (R-20, пакет 5b.4, решение D-32).**
/// Поля `calendar.type/school/highlightDays/uposatha` и `tracker.isolationTag`
/// не читались нигде в `lib/` — мёртвая конфигурация, второй источник истины
/// (сродни B-4 и R-14). Выбор календаря идёт по `tradition` активного пресета
/// (реестр в `features/calendar/presentation/providers/calendar_providers.dart`),
/// изоляция данных — по `id` (принцип №3). Параметры модулей вернутся вместе
/// с первыми живыми потребителями (бэклог v1.1). Неизвестные поля в JSON
/// (легаси-строки `moduleConfigs`, сохранённые в таблице presets до 5b.4)
/// молча игнорируются при разборе — обратной совместимости это не ломает.
class PresetSchema {
  /// Unique identifier (snake_case, e.g. 'nyingma', 'theravada')
  final String id;

  /// Human-readable name (e.g. "Ньингма", "Тхеравада")
  final String name;

  /// Semantic version
  final String version;

  /// Which modules to activate
  final List<String> modules;

  /// Parent tradition family (see tree.json): stable machine key from preset
  /// data. Drives calendar-implementation selection (D-32); never hardcoded
  /// in code.
  final String tradition;

  /// Preset practices from this tradition
  final List<PresetPractice> practices;

  /// Event packs (references to JSON packs)
  final List<String> eventPacks;

  /// Content packs (references to JSON packs)
  final List<String> contentPacks;

  /// Optional description
  final String? description;

  PresetSchema({
    required this.id,
    required this.name,
    required this.version,
    required this.modules,
    required this.tradition,
    required this.practices,
    required this.eventPacks,
    required this.contentPacks,
    this.description,
  });

  factory PresetSchema.fromJson(Map<String, dynamic> json) {
    String reqString(String field) {
      final value = json[field];
      if (value is String) return value;
      throw PresetValidationException(
        field,
        value == null
            ? 'обязательное поле отсутствует'
            : 'ожидалась строка, получен ${value.runtimeType}',
      );
    }

    List<String> reqStringList(String field) {
      final value = json[field];
      if (value == null) {
        throw PresetValidationException(field, 'обязательное поле отсутствует');
      }
      if (value is! List) {
        throw PresetValidationException(field, 'ожидался список строк');
      }
      for (final item in value) {
        if (item is! String) {
          throw PresetValidationException(field, 'элементы списка — строки');
        }
      }
      return List<String>.from(value);
    }

    final practicesRaw = json['practices'];
    if (practicesRaw == null) {
      throw const PresetValidationException(
          'practices', 'обязательное поле отсутствует');
    }
    if (practicesRaw is! List) {
      throw const PresetValidationException(
          'practices', 'ожидался список практик');
    }
    final practices = <PresetPractice>[];
    for (var i = 0; i < practicesRaw.length; i++) {
      final entry = practicesRaw[i];
      if (entry is! Map) {
        throw PresetValidationException(
            'practices[$i]', 'ожидался объект практики');
      }
      try {
        practices.add(
            PresetPractice.fromJson(Map<String, dynamic>.from(entry)));
      } on PresetValidationException catch (e) {
        throw PresetValidationException('practices[$i].${e.field}', e.reason);
      }
    }

    final description = json['description'];
    if (description != null && description is! String) {
      throw const PresetValidationException(
          'description', 'ожидалась строка или null');
    }

    return PresetSchema(
      id: reqString('id'),
      name: reqString('name'),
      version: reqString('version'),
      modules: reqStringList('modules'),
      tradition: reqString('tradition'),
      practices: practices,
      eventPacks: reqStringList('eventPacks'),
      contentPacks: reqStringList('contentPacks'),
      description: description as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'version': version,
      'modules': modules,
      'tradition': tradition,
      'practices': practices.map((p) => p.toJson()).toList(),
      'eventPacks': eventPacks,
      'contentPacks': contentPacks,
      'description': description,
    };
  }
}

/// Preset practice from a tradition preset.
class PresetPractice {
  /// Unique identifier (e.g. 'prostrations', 'vajrasattva')
  final String id;

  /// Human-readable name (e.g. "Простирания", "Мантра Ваджрасаттвы")
  final String name;

  /// Practice type: 'counter' or 'timer' (for future)
  final String type;

  /// Target count (e.g. 100000)
  final int? target;

  /// Unit of measurement: "повторений", "минут"
  final String? unit;

  PresetPractice({
    required this.id,
    required this.name,
    required this.type,
    this.target,
    this.unit,
  });

  factory PresetPractice.fromJson(Map<String, dynamic> json) {
    String reqString(String field) {
      final value = json[field];
      if (value is String) return value;
      throw PresetValidationException(
        field,
        value == null
            ? 'обязательное поле отсутствует'
            : 'ожидалась строка, получен ${value.runtimeType}',
      );
    }

    final target = json['target'];
    if (target != null && target is! int) {
      throw const PresetValidationException(
          'target', 'ожидалось целое число или null');
    }
    final unit = json['unit'];
    if (unit != null && unit is! String) {
      throw const PresetValidationException(
          'unit', 'ожидалась строка или null');
    }

    return PresetPractice(
      id: reqString('id'),
      name: reqString('name'),
      type: reqString('type'),
      target: target as int?,
      unit: unit as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'target': target,
      'unit': unit,
    };
  }
}
