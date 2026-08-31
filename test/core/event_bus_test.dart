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

/// Тесты на ЛОКАЛЬНЫХ инстансах (R-12, шаг 4.2): прежний файл диспозил
/// глобальную шину в последнем тесте, и любой тест, дописанный ниже, молча
/// получал пустоту. Глобальный [EventBus.instance] здесь не диспозится
/// никогда; поведение закрытой шины проверяется на своём автобусе.
void main() {
  late EventBus bus;

  setUp(() => bus = EventBus());
  tearDown(() => bus.dispose());

  group('EventBus (локальный инстанс)', () {
    test('publish доставляет событие подписчику', () async {
      final received = <TestPingEvent>[];

      final sub = bus.on<TestPingEvent>().listen(received.add);

      bus.publish(TestPingEvent('hello'));
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      expect(received.first.payload, 'hello');

      await sub.cancel();
    });

    test('on<T> фильтрует события по типу', () async {
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

    test('несколько подписчиков получают одно событие', () async {
      final received1 = <TestPingEvent>[];
      final received2 = <TestPingEvent>[];

      final sub1 = bus.on<TestPingEvent>().listen(received1.add);
      final sub2 = bus.on<TestPingEvent>().listen(received2.add);

      bus.publish(TestPingEvent('broadcast'));
      await Future<void>.delayed(Duration.zero);

      expect(received1.single.payload, 'broadcast');
      expect(received2.single.payload, 'broadcast');

      await sub1.cancel();
      await sub2.cancel();
    });

    test('publish после dispose бросает StateError, а не молчит (R-12)', () {
      bus.dispose();

      expect(
        () => bus.publish(TestPingEvent('after dispose')),
        throwsStateError,
      );
      expect(bus.isDisposed, isTrue);
    });

    test('после dispose поток подписки завершается (done)', () async {
      var done = false;
      final sub = bus.on<AppEvent>().listen(null, onDone: () => done = true);

      bus.dispose();
      await Future<void>.delayed(Duration.zero);

      expect(done, isTrue,
          reason: 'вещательный поток обязан закрыться вместе с автобусом');
      await sub.cancel();
    });

    test('повторный dispose — no-op, не бросает', () {
      bus.dispose();
      expect(() => bus.dispose(), returnsNormally);
      expect(bus.isDisposed, isTrue);
    });

    test('локальные автобусы изолированы: событие одного не видит другой',
        () async {
      final other = EventBus();
      addTearDown(other.dispose);

      final onThis = <TestPingEvent>[];
      final onOther = <TestPingEvent>[];
      final subA = bus.on<TestPingEvent>().listen(onThis.add);
      final subB = other.on<TestPingEvent>().listen(onOther.add);

      bus.publish(TestPingEvent('only here'));
      await Future<void>.delayed(Duration.zero);

      expect(onThis, hasLength(1));
      expect(onOther, isEmpty);

      await subA.cancel();
      await subB.cancel();
    });
  });

  group('глобальный EventBus.instance', () {
    test('предсоздан и не диспозится тестами (D-21: потребитель — Этап 6)',
        () {
      expect(EventBus.instance, isA<EventBus>());
      expect(EventBus.instance.isDisposed, isFalse,
          reason: 'глобальную шину в тестах закрывать нельзя — она '
              'переживает прогон и должна быть живой для будущих потребителей');
    });
  });
}
