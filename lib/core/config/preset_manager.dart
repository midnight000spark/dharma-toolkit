import 'dart:convert';

import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../module/app_module.dart';
import '../storage/storage_module.dart';
import 'preset_schema.dart';

/// Preset manager. Manages the user's active tradition.
/// Singleton, registered as AppModule.
class PresetManager implements AppModule {
  @override
  String get id => 'preset_manager';

  @override
  String get name => 'Менеджер пресетов';

  @override
  String get version => '1.0.0';

  final AppDatabase _database;
  final StorageModule _storage;
  PresetSchema? _activePreset;

  PresetManager(this._database, this._storage);

  @override
  Future<void> init() async {
    // Load active preset from storage
    final activePresetId = _storage.getString('active_preset_id');
    if (activePresetId != null) {
      _activePreset = await _loadPresetFromDb(activePresetId);
    }
  }

  @override
  Future<void> dispose() async {
    _activePreset = null;
  }

  /// Apply a preset: save to DB, set as active.
  Future<void> applyPreset(PresetSchema preset) async {
    // Save preset to DB (presets table)
    await _database.into(_database.presets).insertOnConflictUpdate(
          PresetsCompanion.insert(
            id: preset.id,
            name: preset.name,
            version: preset.version,
            tradition: preset.tradition,
            data: jsonEncode(preset.toJson()),
          ),
        );

    // Set as active
    await _storage.setString('active_preset_id', preset.id);
    _activePreset = preset;
  }

  /// Switch preset: clear old, apply new.
  Future<void> switchPreset(PresetSchema newPreset) async {
    // Clean up old tradition data (if isolation by tag exists)
    if (_activePreset != null) {
      await _cleanupOldPreset(_activePreset!);
    }
    await applyPreset(newPreset);
  }

  /// Reset preset: remove active, clear data.
  Future<void> resetPreset() async {
    if (_activePreset != null) {
      await _cleanupOldPreset(_activePreset!);
    }
    await _storage.remove('active_preset_id');
    _activePreset = null;
  }

  /// Get the active preset.
  PresetSchema? get activePreset => _activePreset;

  Future<PresetSchema?> _loadPresetFromDb(String presetId) async {
    final query = _database.select(_database.presets)
      ..where((t) => t.id.equals(presetId));
    final result = await query.getSingleOrNull();
    if (result == null) return null;

    final json = jsonDecode(result.data) as Map<String, dynamic>;
    return PresetSchema.fromJson(json);
  }

  Future<void> _cleanupOldPreset(PresetSchema preset) async {
    // Future: delete data with tag preset.id
    // For now, stub
  }
}
