import 'dart:convert';

import 'package:flutter/services.dart';

import '../module/app_module.dart';
import 'preset_schema.dart';

/// Традиция из дерева школ (tree.json, D-11 — плоский список).
class TraditionInfo {
  final String id;
  final String name;

  /// Идентификаторы пресетов, относящихся к традиции.
  final List<String> presetIds;

  const TraditionInfo({
    required this.id,
    required this.name,
    required this.presetIds,
  });
}

/// Module for loading JSON presets from assets.
///
/// Composition of assets:
/// - `presets/index.json` — манифест доступных пресетов;
/// - `presets/tree.json` — дерево школ (D-11);
/// - `presets/<id>.json` — сами пресеты из манифеста.
///
/// Каждый файл в `presets/` обязан иметь читателя: мёртвых ассетов
/// быть не должно (урок аудита B-4).
class ConfigModule implements AppModule {
  @override
  String get id => 'config';

  @override
  String get name => 'Конфигурация';

  @override
  String get version => '1.0.0';

  final Map<String, PresetSchema> _presets = {};
  List<TraditionInfo> _tree = const [];

  static const String _manifestAsset = 'presets/index.json';
  static const String _treeAsset = 'presets/tree.json';

  @override
  Future<void> init() async {
    // 1. Манифест — единственный источник списка доступных пресетов.
    final manifest =
        await _loadJson(_manifestAsset) as Map<String, dynamic>;
    final presetIds = (manifest['presets'] as List).cast<String>();

    // 2. Сами пресеты из манифеста.
    for (final id in presetIds) {
      final json = await _loadJson('presets/$id.json');
      final preset = PresetSchema.fromJson(json as Map<String, dynamic>);
      _presets[preset.id] = preset;
    }

    // 3. Дерево школ для экрана выбора традиции.
    final treeJson = await _loadJson(_treeAsset) as Map<String, dynamic>;
    _tree = (treeJson['traditions'] as List)
        .cast<Map<String, dynamic>>()
        .map(
          (t) => TraditionInfo(
            id: t['id'] as String,
            name: t['name'] as String,
            presetIds: (t['presets'] as List).cast<String>(),
          ),
        )
        .toList();
  }

  @override
  Future<void> dispose() async {
    _presets.clear();
    _tree = const [];
  }

  Future<Object?> _loadJson(String assetKey) async {
    try {
      final jsonString = await rootBundle.loadString(assetKey);
      return jsonDecode(jsonString);
    } catch (e) {
      throw StateError('Failed to load asset $assetKey: $e');
    }
  }

  /// Returns a preset by id, or null if not found.
  PresetSchema? getPreset(String id) => _presets[id];

  /// All loaded presets.
  Iterable<PresetSchema> get allPresets => _presets.values;

  /// Идентификаторы пресетов, реально доступных в сборке.
  Set<String> get availablePresetIds => _presets.keys.toSet();

  /// Дерево традиций (D-11). Экран выбора показывает его целиком,
  /// помечая недоступное как «скоро».
  List<TraditionInfo> get tree => _tree;
}
