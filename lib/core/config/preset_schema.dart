/// Schema for JSON preset files v1. Describes configuration for a tradition.
///
/// Validated when loading from assets. Contains module configurations,
/// preset practices, event packs, and content packs.
class PresetSchema {
  /// Unique identifier (snake_case, e.g. 'nyingma', 'theravada')
  final String id;

  /// Human-readable name (e.g. "Ньингма", "Тхеравада")
  final String name;

  /// Semantic version
  final String version;

  /// Which modules to activate
  final List<String> modules;

  /// Parent tradition: 'theravada', 'mahayana', 'vajrayana', 'bon'
  final String tradition;

  /// Module configurations (key = module id, value = parameters)
  final Map<String, Map<String, dynamic>> moduleConfigs;

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
    required this.moduleConfigs,
    required this.practices,
    required this.eventPacks,
    required this.contentPacks,
    this.description,
  });

  factory PresetSchema.fromJson(Map<String, dynamic> json) {
    return PresetSchema(
      id: json['id'] as String,
      name: json['name'] as String,
      version: json['version'] as String,
      modules: (json['modules'] as List).cast<String>(),
      tradition: json['tradition'] as String,
      moduleConfigs: (json['moduleConfigs'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, v as Map<String, dynamic>),
      ),
      practices: (json['practices'] as List)
          .map((e) => PresetPractice.fromJson(e as Map<String, dynamic>))
          .toList(),
      eventPacks: (json['eventPacks'] as List).cast<String>(),
      contentPacks: (json['contentPacks'] as List).cast<String>(),
      description: json['description'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'version': version,
      'modules': modules,
      'tradition': tradition,
      'moduleConfigs': moduleConfigs,
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
    return PresetPractice(
      id: json['id'] as String,
      name: json['name'] as String,
      type: json['type'] as String,
      target: json['target'] as int?,
      unit: json['unit'] as String?,
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
