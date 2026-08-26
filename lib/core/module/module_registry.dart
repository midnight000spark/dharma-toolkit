import 'app_module.dart';

/// Application module registry. Singleton at runtime.
///
/// Stores all registered [AppModule] instances and manages their lifecycle.
/// Modules must be registered before [initAll] is called.
class ModuleRegistry {
  ModuleRegistry._();
  static final ModuleRegistry instance = ModuleRegistry._();

  final Map<String, AppModule> _modules = {};
  bool _initialized = false;

  /// Registers a module. Must be called before [initAll].
  ///
  /// Throws [StateError] if registry is already initialized.
  /// Throws [ArgumentError] if module with same id already registered.
  void register(AppModule module) {
    if (_initialized) {
      throw StateError('Cannot register module after registry is initialized');
    }
    if (_modules.containsKey(module.id)) {
      throw ArgumentError('Module with id "${module.id}" already registered');
    }
    _modules[module.id] = module;
  }

  /// Returns module by id, or null if not found.
  AppModule? get(String id) => _modules[id];

  /// Initializes all modules in registration order.
  ///
  /// Safe to call multiple times — subsequent calls are no-ops.
  Future<void> initAll() async {
    if (_initialized) return;
    for (final module in _modules.values) {
      await module.init();
    }
    _initialized = true;
  }

  /// Disposes all modules in reverse registration order.
  ///
  /// Clears the registry and resets initialization state.
  Future<void> disposeAll() async {
    for (final module in _modules.values.toList().reversed) {
      await module.dispose();
    }
    _modules.clear();
    _initialized = false;
  }

  /// All registered modules (for testing and debugging).
  Iterable<AppModule> get all => _modules.values;
}
