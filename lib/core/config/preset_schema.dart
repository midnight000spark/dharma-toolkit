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
/// (сродни B-4 и R-14). Выбор календаря идёт по **тегу пресета** (`id`; реестр
/// в `features/calendar/presentation/providers/calendar_providers.dart`), а не
/// по `tradition`: внутри одного направления школы могут иметь разные движки
/// (W4/S6, п. 11.3). Изоляция данных — по тегу пресета (`id`, принцип №3).
/// Параметры модулей вернутся вместе с первыми живыми потребителями
/// (бэклог v1.1). Неизвестные поля в JSON (легаси-строки `moduleConfigs`,
/// сохранённые в таблице presets до 5b.4) молча игнорируются при разборе —
/// обратной совместимости это не ломает.
class PresetSchema {
  /// Единственная поддерживаемая версия схемы пресета (W5).
  ///
  /// Версия обязательна, и поддерживаемость **проверяется**: пресет чужой
  /// версии может нести несовместимый состав полей, а молчаливое «прочитали
  /// часть» исказило бы материализацию практик. Расширение набора —
  /// осознанная правка в одном месте.
  static const String supportedVersion = '1.0.0';

  /// Unique identifier (snake_case, e.g. 'nyingma', 'theravada')
  final String id;

  /// Human-readable name (e.g. "Ньингма", "Тхеравада")
  final String name;

  /// Semantic version
  final String version;

  /// Which modules to activate
  final List<String> modules;

  /// Parent tradition family (see tree.json): stable machine key for the
  /// **taxonomy** — grouping and filters of the school tree. Does **not**
  /// drive calendar-engine selection (D-32, W4/S6): the selection/matching
  /// key is the preset tag (`id`). Never hardcoded in code.
  final String tradition;

  /// Preset practices from this tradition
  final List<PresetPractice> practices;

  /// Event packs (asset keys). Convention (W4/S6): the pack's own
  /// `traditionTag` is marked with the **preset tag** — `id`, not `tradition`.
  final List<String> eventPacks;

  /// Content packs (asset keys). Same marking convention as event packs:
  /// `traditionTag` inside the pack = preset tag (`id`), not `tradition`.
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
    final seenPracticeIds = <String>{};
    for (var i = 0; i < practicesRaw.length; i++) {
      final entry = practicesRaw[i];
      if (entry is! Map) {
        throw PresetValidationException(
            'practices[$i]', 'ожидался объект практики');
      }
      final PresetPractice practice;
      try {
        practice =
            PresetPractice.fromJson(Map<String, dynamic>.from(entry));
      } on PresetValidationException catch (e) {
        throw PresetValidationException('practices[$i].${e.field}', e.reason);
      }
      // W9: дубль id — не «две одинаковые практики», а неоднозначный
      // пресет: материализация одного и того же presetPracticeId вела бы
      // к молчаливой перезаписи. Отказ с путём поля, а не дедуп.
      if (!seenPracticeIds.add(practice.id)) {
        throw PresetValidationException(
            'practices[$i].id', 'идентификатор "${practice.id}" повторяется');
      }
      practices.add(practice);
    }

    final description = json['description'];
    if (description != null && description is! String) {
      throw const PresetValidationException(
          'description', 'ожидалась строка или null');
    }

    final version = reqString('version');
    if (version != supportedVersion) {
      throw PresetValidationException(
        'version',
        'версия "$version" не поддерживается '
        '(поддерживается: "$supportedVersion")',
      );
    }

    return PresetSchema(
      id: reqString('id'),
      name: reqString('name'),
      version: version,
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
  /// Типы практик, допустимые в схемах пресетов (W9).
  ///
  /// `counter` — единственный работающий тип MVP; `timer` задокументирован
  /// схемой как будущий (FR-TRK-7, бэклог v1.1) и не должен краснеть в
  /// заранее написанных пресетах. Набор — надмножество доменного
  /// `PracticeTypes.available` (форма создания предлагает только работающие
  /// типы); ядро не импортирует features (принцип №1), поэтому перечень
  /// живёт здесь — при расширении домена синхронизировать.
  static const List<String> supportedTypes = <String>['counter', 'timer'];

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
    // B-24: цель ≤ 0 — не «просто ноль прогресса», а бессмысленный пресет
    // («Цель: −5» доезжала до экрана). Граница домена проверяется здесь,
    // а не клампится в UI (урок 3).
    if (target is int && target <= 0) {
      throw PresetValidationException(
        'target',
        'цель должна быть больше нуля, получено $target',
      );
    }
    final unit = json['unit'];
    if (unit != null && unit is! String) {
      throw const PresetValidationException(
          'unit', 'ожидалась строка или null');
    }

    // W9: чужой тип материализовал бы практику без обработчика; отказ по
    // пути поля на слое разбора, а не молчаливое принятие.
    final type = reqString('type');
    if (!supportedTypes.contains(type)) {
      throw PresetValidationException(
        'type',
        'тип "$type" не поддерживается '
        '(поддерживаются: ${supportedTypes.join(', ')})',
      );
    }

    return PresetPractice(
      id: reqString('id'),
      name: reqString('name'),
      type: type,
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
