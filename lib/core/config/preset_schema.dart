/// Schema for JSON preset files.
///
/// Validated when loading from assets. Describes which modules
/// to activate for a specific tradition.
class PresetSchema {
  final String id;
  final String name;
  final String version;
  final List<String> modules;
  final String? description;

  PresetSchema({
    required this.id,
    required this.name,
    required this.version,
    required this.modules,
    this.description,
  });

  factory PresetSchema.fromJson(Map<String, dynamic> json) {
    return PresetSchema(
      id: json['id'] as String,
      name: json['name'] as String,
      version: json['version'] as String,
      modules: (json['modules'] as List).cast<String>(),
      description: json['description'] as String?,
    );
  }
}
