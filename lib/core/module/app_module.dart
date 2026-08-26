/// Contract for all application modules (plugins).
///
/// Each module represents an independent feature area (e.g. calendar, tracker,
/// content). Modules are initialised and disposed by the core lifecycle manager.
abstract interface class AppModule {
  /// Unique identifier of the module (snake_case, e.g. 'calendar').
  String get id;

  /// Human-readable name of the module.
  String get name;

  /// Module version (semver format, e.g. '1.0.0').
  String get version;

  /// Called once when the module is activated.
  ///
  /// Implementations should perform any one-time setup here (register
  /// providers, open resources, etc.). Returns Future — module may be async
  /// (e.g. database initialization).
  Future<void> init();

  /// Called when the module is deactivated or the app is shutting down.
  ///
  /// Implementations should release resources and cancel subscriptions.
  Future<void> dispose();
}
