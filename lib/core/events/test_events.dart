import 'app_event.dart';

/// Test event used only in tests to verify event bus behavior.
class TestPingEvent extends AppEvent {
  TestPingEvent(this.payload) : timestamp = DateTime.now();

  @override
  final DateTime timestamp;

  final String payload;
}
