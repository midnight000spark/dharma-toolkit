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
import 'package:dharma_toolkit/features/events/domain/notification_settings.dart';
import 'package:flutter_test/flutter_test.dart';

import 'in_memory_notification_scheduler.dart';

/// Планировщик, падающий на выбранных id (C7): проверка per-item обработки —
/// одно упавшее уведомление не срывает остальные.
class _FailingScheduler extends InMemoryNotificationScheduler {
  _FailingScheduler(this.failIds);

  final Set<int> failIds;

  @override
  Future<void> schedule(NotificationPlanItem item) async {
    if (failIds.contains(item.id)) {
      throw StateError('пункт ${item.id} не поставлен');
    }
    return super.schedule(item);
  }
}

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

  test('сбой сборки плана не рвёт очередь, повтор ограничен и виден в логе',
      () async {
    var calls = 0;
    final replanner = replannerWith(buildPlan: () async {
      calls++;
      if (calls <= NotificationReplanner.buildAttempts) {
        throw StateError('пресет не прочитан');
      }
      return NotificationPlan(items: [item(100000, 'Событие')], notes: const []);
    });
    replanner.listen();

    bus.publish(PresetChanged(traditionTag: 'nyingma'));
    await settle(replanner);
    expect(calls, NotificationReplanner.buildAttempts,
        reason: 'W3: сборка повторяется ограниченно, а не один раз');
    expect(scheduler.scheduled, isEmpty);
    expect(warnings.single, contains('пресет не прочитан'));
    expect(replanner.replanFailures, 1);

    bus.publish(NotificationSettingsChanged(traditionTag: 'nyingma'));
    await settle(replanner);

    expect(calls, NotificationReplanner.buildAttempts + 1);
    expect(scheduler.scheduled.keys, [100000]);
    expect(replanner.appliedPlans, 1);
  });

  group('W2 — показанное снимается при переплане (журнал C7)', () {
    test('доставленный id прошлого журнала снимается при следующем переплане',
        () async {
      final replanner = replannerWith(
        buildPlan: () async => NotificationPlan(
          items: [item(100000, 'A')],
          notes: const [],
        ),
      );
      replanner.start();
      await replanner.settled;
      expect(scheduler.scheduled.keys, [100000]);

      // Уведомление сработало и осталось в шторке: в pending его уже нет, и
      // платформа (listsActive = false) его не перечисляет.
      scheduler.deliver(100000);
      expect(scheduler.delivered.keys, [100000]);

      bus.publish(PresetChanged(traditionTag: 'theravada'));
      await settle(replanner);

      expect(scheduler.delivered, isEmpty,
          reason: 'переплан обязан снять показанное прошлого плана (журнал C7)');
      expect(scheduler.scheduled.keys, [100000],
          reason: 'новый план поставлен заново');
    });
  });

  group('W3 — битая строка настроек не оставляет старую полосу', () {
    test('ошибка чтения настроек: полоса пуста, replanFailures растёт',
        () async {
      var broken = false;
      final replanner = replannerWith(buildPlan: () async {
        if (broken) {
          throw InvalidNotificationSettingsException(
              'hour', 'час вне диапазона (традиция «nyingma»)');
        }
        return NotificationPlan(items: [item(100000, 'A')], notes: const []);
      });
      replanner.start();
      await replanner.settled;
      expect(scheduler.scheduled.keys, [100000]);

      // Строка настроек испорчена: чтение падает, оба ограниченных повтора
      // тоже; старую полосу жить не оставляем.
      broken = true;
      bus.publish(PresetChanged(traditionTag: 'nyingma'));
      await settle(replanner);

      expect(await scheduler.pendingIds(), isEmpty,
          reason: 'битая строка не оставляет старую полосу');
      expect(replanner.replanFailures, 1);
      expect(warnings.last, contains('полоса снимается'));
      expect(replanner.appliedPlans, 1,
          reason: 'успешный переплан остаётся единственным');
    });

    test('транзиентный отказ сборки переживается повтором', () async {
      var calls = 0;
      final replanner = replannerWith(buildPlan: () async {
        calls++;
        if (calls == 1) throw StateError('БД занята');
        return NotificationPlan(items: [item(100000, 'A')], notes: const []);
      });

      replanner.start();
      await replanner.settled;

      expect(calls, 2, reason: 'ограниченный retry спас транзиентный отказ');
      expect(scheduler.scheduled.keys, [100000]);
      expect(replanner.replanFailures, 0);
      expect(replanner.appliedPlans, 1);
      expect(warnings, isEmpty, reason: 'успешный повтор — не деградация');
    });
  });

  group('C7 — применение плана по пунктам (журнал, applied/degraded)', () {
    test('отказ на пункте k не срывает остальные; отказ виден в журнале',
        () async {
      final failing = _FailingScheduler({100001});
      final replanner = NotificationReplanner(
        bus: bus,
        scheduler: failing,
        buildPlan: () async => NotificationPlan(
          items: [
            item(100000, 'A'),
            item(100001, 'B'),
            item(100002, 'C'),
          ],
          notes: const [],
        ),
        warn: warnings.add,
      );
      replanner.start();
      await replanner.settled;

      // Пункты после упавшего поставлены: один отказ не срывает план.
      expect(failing.scheduled.keys, [100000, 100002]);
      // Журнал: снимок последнего плана + исход по каждому пункту.
      final journal = replanner.lastJournal!;
      expect(journal.plan.items.map((i) => i.id), [100000, 100001, 100002]);
      expect(journal.failedIds, [100001]);
      expect(journal.isDegraded, isTrue);
      expect(journal.items.firstWhere((i) => i.item.id == 100001).error,
          isA<StateError>());
      expect(warnings.single, contains('деградировало'));
      // Метрики: degraded учтён, applied не растёт на деградации.
      expect(replanner.appliedPlans, 0);
      expect(replanner.degradedPlans, 1);
    });

    test('полное применение: applied растёт, журнал без отказов', () async {
      final replanner = replannerWith(
        buildPlan: () async => NotificationPlan(
          items: [item(100000, 'A')],
          notes: const [],
        ),
      );
      replanner.start();
      await replanner.settled;

      expect(replanner.appliedPlans, 1);
      expect(replanner.degradedPlans, 0);
      expect(replanner.lastJournal!.isDegraded, isFalse);
      expect(replanner.lastJournal!.failedIds, isEmpty);
    });

    test('сбой сборки плана журнал не подменяет', () async {
      var calls = 0;
      final replanner = replannerWith(buildPlan: () async {
        calls++;
        if (calls == 1) {
          return NotificationPlan(items: [item(100000, 'A')], notes: const []);
        }
        throw StateError('пресет не прочитан');
      });
      replanner.start();
      await replanner.settled;
      final first = replanner.lastJournal;
      expect(first, isNotNull);

      bus.publish(PresetChanged(traditionTag: 'nyingma'));
      await settle(replanner);

      // Журнал остаётся снимком последнего применённого плана — W2 не должен
      // потерять полосу из-за неудачной пересборки.
      expect(identical(replanner.lastJournal, first), isTrue);
      expect(replanner.appliedPlans, 1);
    });
  });
}
