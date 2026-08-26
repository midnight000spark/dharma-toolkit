import 'dart:convert';

import 'package:flutter/services.dart';

import '../module/app_module.dart';
import 'preset_schema.dart';

/// Module for loading JSON presets from assets.
///
/// Presets describe which modules to activate for a specific tradition.
/// In MVP, loads only sample.json. Future versions will scan the directory
/// or load from a list.
class ConfigModule implements AppModule {
  @override
  String get id => 'config';

  @override
  String get name => 'Конфигурация';

  @override
  String get version => '1.0.0';

  final Map<String, PresetSchema> _presets = {};

  @override
  Future<void> init() async {
    // In MVP, load only sample.json.
    // Future versions will scan directory or load from list.
    await _loadPreset('sample.json');
  }

  @override
  Future<void> dispose() async {
    _presets.clear();
  }

  Future<void> _loadPreset(String filename) async {
    try {
      final jsonString = await rootBundle.loadString('presets/$filename');
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      final preset = PresetSchema.fromJson(json);
      _presets[preset.id] = preset;
    } catch (e) {
      throw StateError('Failed to load preset $filename: $e');
    }
  }

  /// Returns a preset by id, or null if not found.
  PresetSchema? getPreset(String id) => _presets[id];

  /// All loaded presets.
  Iterable<PresetSchema> get allPresets => _presets.values;
}
