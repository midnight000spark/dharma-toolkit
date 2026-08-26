/// Contract for all application modules (plugins).
///
/// Each module represents an independent feature area (e.g. calendar, tracker,
/// content). Modules are initialised and disposed by the core lifecycle manager.
abstract interface class AppModule {
  /// Unique identifier of the module (e.g. `'calendar'`).
  String get id;

  /// Human-readable name of the module.
  String get name;

  /// Called once when the module is activated.
  ///
  /// Implementations should perform any one-time setup here (register
  /// providers, open resources, etc.).
  Future<void> init();

  /// Called when the module is deactivated or the app is shutting down.
  ///
  /// Implementations should release resources and cancel subscriptions.
  Future<void> dispose();
}
