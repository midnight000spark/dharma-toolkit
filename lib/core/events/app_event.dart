/// Base class for all application events.
///
/// Modules communicate through events without knowing about each other
/// directly — this is key to modularity (D-5).
abstract class AppEvent {
  const AppEvent();

  /// When the event was created.
  DateTime get timestamp;
}
