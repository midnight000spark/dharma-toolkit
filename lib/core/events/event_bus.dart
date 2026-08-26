import 'dart:async';

import 'app_event.dart';

/// Global event bus. Modules publish and subscribe to events without knowing
/// about each other — this is key to modularity (D-5).
class EventBus {
  EventBus._();
  static final EventBus instance = EventBus._();

  final _controller = StreamController<AppEvent>.broadcast();

  /// Publish an event. All subscribers will receive it asynchronously.
  void publish(AppEvent event) {
    if (!_controller.isClosed) {
      _controller.add(event);
    }
  }

  /// Subscribe to events of a specific type T.
  ///
  /// Returns a Stream — the subscriber manages the subscription themselves.
  Stream<T> on<T extends AppEvent>() {
    return _controller.stream.where((e) => e is T).cast<T>();
  }

  /// Close the bus. Called when the application shuts down.
  void dispose() {
    _controller.close();
  }
}
