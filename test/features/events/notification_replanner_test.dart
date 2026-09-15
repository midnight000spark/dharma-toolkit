/// Перепланировщик — первый потребитель шины событий (D-21, блок E пакета 6.2).
///
/// Проверяется путь «событие → перестроенный план → идемпотентное применение».
/// Событие публикуется в **настоящую** шину (локальный инстанс, R-12), а не
/// вызывается метод-обработчик напрямую: иначе тест не увидел бы, что подписки
/// нет вовсе — ровно та мутация, которую он обязан ловить.
library;

import 'package:dharma_toolkit/core/events/event_bus.dart';
import 'package:dharma_toolkit/core/events/notification_events.dart';
import 'package:dharma_toolkit/core/events/preset_events.dart';
import 'package:dharma_toolkit/features/events/application/notification_replanner.dart';
import 'package:dharma_toolkit/features/events/domain/notification_plan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'in_memory_notification_scheduler.dart';

void main() {
  late EventBus bus;
  late InMemoryNotificationScheduler scheduler;
  late List<String> warnings;

  setUp(() {
    bus = EventBus();
    scheduler = InMemoryNotificationScheduler();
    warnings = [];
  });

  tearDown(() => bus.dispose());

  NotificationPlanItem item(int id, String title) => NotificationPlanItem(
        id: id,
        scheduledAt: DateTime(2026, 6, 2, 8),
        title: title,
        body: 'Особое событие',
        payload: '',
      );

  NotificationReplanner replannerWith({
    required Future<NotificationPlan> Function() buildPlan,
  }) =>
      NotificationReplanner(
        bus: bus,
        scheduler: scheduler,
        buildPlan: buildPlan,
        warn: warnings.add,
      );

  /// Дождаться обработки: сначала событие доезжает до подписчика (микротаск
  /// шины), затем отрабатывает очередь перепланирований.
  Future<void> settle(NotificationReplanner replanner) async {
    await pumpEventQueue();
    await replanner.settled;
  }

  /// План, сборка которого завершается не сразу: так видно, дождался ли
  /// вызывающий результат или отпустил работу в свободный полёт.
  Future<NotificationPlan> slowPlan(List<int> builds) async {
    await Future<void>.delayed(Duration.zero);
    builds.add(1);
    return NotificationPlan(items: [item(100000, 'Событие')], notes: const []);
  }

  test('PresetChanged приводит к перепланированию', () async {
    final builds = <int>[];
    final replanner = replannerWith(buildPlan: () => slowPlan(builds));
    replanner.listen();

    bus.publish(PresetChanged(traditionTag: 'nyingma'));
    await settle(replanner);

    expect(builds, hasLength(1));
    expect(scheduler.scheduled.keys, [100000]);
  });

  test('NotificationSettingsChanged приводит к перепланированию', () async {
    final builds = <int>[];
    final replanner = replannerWith(buildPlan: () => slowPlan(builds));
    replanner.listen();

    bus.publish(NotificationSettingsChanged(traditionTag: 'nyingma'));
    await settle(replanner);

    expect(builds, hasLength(1));
  });

  test('start() перепланирует сразу — старт приложения триггер D-36', () async {
    final builds = <int>[];
    final replanner = replannerWith(buildPlan: () => slowPlan(builds));

    replanner.start();
    await replanner.settled;

    expect(builds, hasLength(1));
    expect(replanner.isListening, isTrue);
  });

  test('повторный listen() не удваивает подписку', () async {
    final builds = <int>[];
    final replanner = replannerWith(buildPlan: () => slowPlan(builds));

    replanner.listen();
    replanner.listen();
    bus.publish(PresetChanged(traditionTag: 'nyingma'));
    await settle(replanner);

    expect(builds, hasLength(1));
  });

  test('stop() снимает подписки: событие больше не перепланирует', () async {
    final builds = <int>[];
    final replanner = replannerWith(buildPlan: () => slowPlan(builds));

    replanner.listen();
    await replanner.stop();
    bus.publish(PresetChanged(traditionTag: 'nyingma'));
    await settle(replanner);

    expect(builds, isEmpty);
    expect(replanner.isListening, isFalse);
  });

  test('события обрабатываются по очереди, а не наложением', () async {
    final order = <String>[];
    final replanner = replannerWith(buildPlan: () async {
      order.add('build-${order.length}');
      await Future<void>.delayed(Duration.zero);
      return const NotificationPlan(items: [], notes: []);
    });
    replanner.listen();

    bus.publish(PresetChanged(traditionTag: 'nyingma'));
    bus.publish(NotificationSettingsChanged(traditionTag: 'nyingma'));
    await settle(replanner);

    expect(order, ['build-0', 'build-1']);
    expect(replanner.appliedPlans, 2);
  });

  test('сбой сборки плана не рвёт очередь и виден в логе', () async {
    var calls = 0;
    final replanner = replannerWith(buildPlan: () async {
      calls++;
      if (calls == 1) throw StateError('пресет не прочитан');
      return NotificationPlan(items: [item(100000, 'Событие')], notes: const []);
    });
    replanner.listen();

    bus.publish(PresetChanged(traditionTag: 'nyingma'));
    await settle(replanner);
    expect(scheduler.scheduled, isEmpty);
    expect(warnings.single, contains('пресет не прочитан'));

    bus.publish(NotificationSettingsChanged(traditionTag: 'nyingma'));
    await settle(replanner);

    expect(calls, 2);
    expect(scheduler.scheduled.keys, [100000]);
  });
}
