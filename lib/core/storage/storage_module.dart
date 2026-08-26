import 'package:shared_preferences/shared_preferences.dart';

import '../module/app_module.dart';

/// Module for storing simple key-value settings.
///
/// Used for UI preferences, selected tradition, etc.
/// Wraps [SharedPreferences] and provides type-safe access methods.
class StorageModule implements AppModule {
  @override
  String get id => 'storage';

  @override
  String get name => 'Хранилище настроек';

  @override
  String get version => '1.0.0';

  SharedPreferences? _prefs;

  @override
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  @override
  Future<void> dispose() async {
    _prefs = null;
  }

  // === Public API ===

  /// Stores a string value.
  Future<void> setString(String key, String value) async {
    _ensureInitialized();
    await _prefs!.setString(key, value);
  }

  /// Retrieves a string value, or null if not found.
  String? getString(String key) {
    _ensureInitialized();
    return _prefs!.getString(key);
  }

  /// Stores a boolean value.
  Future<void> setBool(String key, bool value) async {
    _ensureInitialized();
    await _prefs!.setBool(key, value);
  }

  /// Retrieves a boolean value, or null if not found.
  bool? getBool(String key) {
    _ensureInitialized();
    return _prefs!.getBool(key);
  }

  /// Stores an integer value.
  Future<void> setInt(String key, int value) async {
    _ensureInitialized();
    await _prefs!.setInt(key, value);
  }

  /// Retrieves an integer value, or null if not found.
  int? getInt(String key) {
    _ensureInitialized();
    return _prefs!.getInt(key);
  }

  /// Removes a value by key.
  Future<void> remove(String key) async {
    _ensureInitialized();
    await _prefs!.remove(key);
  }

  void _ensureInitialized() {
    if (_prefs == null) {
      throw StateError('StorageModule not initialized');
    }
  }
}
