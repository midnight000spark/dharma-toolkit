import 'package:dharma_toolkit/core/events/app_event.dart';
import 'package:dharma_toolkit/core/events/event_bus.dart';
import 'package:dharma_toolkit/core/events/test_events.dart';
import 'package:flutter_test/flutter_test.dart';

/// Another test event to verify type filtering.
class _TestPongEvent extends AppEvent {
  _TestPongEvent(this.value) : timestamp = DateTime.now();

  @override
  final DateTime timestamp;

  final int value;
}

void main() {
  group('EventBus', () {
    test('publish delivers event to subscriber', () async {
      final bus = EventBus.instance;
      final received = <TestPingEvent>[];

      final sub = bus.on<TestPingEvent>().listen(received.add);

      bus.publish(TestPingEvent('hello'));

      // Wait for async delivery
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      expect(received.first.payload, 'hello');

      await sub.cancel();
    });

    test('on<T> filters events by type', () async {
      final bus = EventBus.instance;
      final pings = <TestPingEvent>[];
      final pongs = <_TestPongEvent>[];

      final sub1 = bus.on<TestPingEvent>().listen(pings.add);
      final sub2 = bus.on<_TestPongEvent>().listen(pongs.add);

      bus.publish(TestPingEvent('ping'));
      bus.publish(_TestPongEvent(42));
      bus.publish(TestPingEvent('ping2'));

      await Future<void>.delayed(Duration.zero);

      expect(pings, hasLength(2));
      expect(pongs, hasLength(1));
      expect(pongs.first.value, 42);

      await sub1.cancel();
      await sub2.cancel();
    });

    test('multiple subscribers receive the same event', () async {
      final bus = EventBus.instance;
      final received1 = <TestPingEvent>[];
      final received2 = <TestPingEvent>[];
      final received3 = <TestPingEvent>[];

      final sub1 = bus.on<TestPingEvent>().listen(received1.add);
      final sub2 = bus.on<TestPingEvent>().listen(received2.add);
      final sub3 = bus.on<TestPingEvent>().listen(received3.add);

      bus.publish(TestPingEvent('broadcast'));

      await Future<void>.delayed(Duration.zero);

      expect(received1, hasLength(1));
      expect(received2, hasLength(1));
      expect(received3, hasLength(1));
      expect(received1.first.payload, 'broadcast');
      expect(received2.first.payload, 'broadcast');
      expect(received3.first.payload, 'broadcast');

      await sub1.cancel();
      await sub2.cancel();
      await sub3.cancel();
    });

    test('dispose closes the stream', () async {
      final bus = EventBus.instance;
      final received = <AppEvent>[];

      final sub = bus.on<AppEvent>().listen(received.add);

      bus.dispose();

      // After dispose, publishing should not throw (guarded by isClosed check)
      bus.publish(TestPingEvent('after dispose'));

      await Future<void>.delayed(Duration.zero);

      // Stream is closed, so no events should be received
      expect(received, isEmpty);

      await sub.cancel();
    });
  });
}
