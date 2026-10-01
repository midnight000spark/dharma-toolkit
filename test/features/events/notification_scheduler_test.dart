/// Порт планировщика: идемпотентное перепланирование и полоса id (D-36, блок D).
///
/// Проверяется контракт порта на in-memory фейке: снятие «своей» полосы не
/// трогает чужие уведомления, повторное применение плана не плодит дублей —
/// это и есть обещанная D-36 идемпотентность, а не «надеемся на плагин».
library;

import 'package:dharma_toolkit/features/events/domain/notification_plan.dart';
import 'package:dharma_toolkit/features/events/domain/notification_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

import 'in_memory_notification_scheduler.dart';

NotificationPlanItem itemOf(int id, {String title = 'Событие'}) =>
    NotificationPlanItem(
      id: id,
      scheduledAt: DateTime(2026, 6, 2, 8),
      title: title,
      body: 'тело',
      payload: '{}',
    );

NotificationPlan planOf(List<NotificationPlanItem> items) =>
    NotificationPlan(items: items, notes: const []);

void main() {
  late InMemoryNotificationScheduler scheduler;

  setUp(() => scheduler = InMemoryNotificationScheduler());

  group('applyNotificationPlan — идемпотентность (D-36)', () {
    test('план применён: все пункты в pending', () async {
      final plan = planOf([itemOf(100000), itemOf(100001), itemOf(100002)]);

      await applyNotificationPlan(scheduler, plan);

      expect(await scheduler.pendingIds(), [100000, 100001, 100002]);
    });

    test('повторное применение того же плана не удваивает pending', () async {
      final plan = planOf([itemOf(100000), itemOf(100001)]);

      await applyNotificationPlan(scheduler, plan);
      await applyNotificationPlan(scheduler, plan);
      await applyNotificationPlan(scheduler, plan);

      expect(await scheduler.pendingIds(), [100000, 100001]);
      expect(scheduler.cancelRangeCalls, 3);
      expect(scheduler.scheduled, hasLength(2));
    });

    test('смена плана не оставляет «хвостов» прошлого', () async {
      await applyNotificationPlan(
          scheduler, planOf([itemOf(100000), itemOf(100001)]));
      await applyNotificationPlan(scheduler, planOf([itemOf(100000)]));

      expect(await scheduler.pendingIds(), [100000]);
    });

    test('пустой план очищает полосу (выключенные уведомления)', () async {
      await applyNotificationPlan(scheduler, planOf([itemOf(100000)]));
      await applyNotificationPlan(
          scheduler, const NotificationPlan(items: [], notes: []));

      expect(await scheduler.pendingIds(), isEmpty);
    });

    test('снятие полосы не трогает чужие уведомления', () async {
      // Чужой id (например, системный или другого модуля) — вне полосы.
      scheduler.scheduled[42] = itemOf(42);

      await applyNotificationPlan(scheduler, planOf([itemOf(100000)]));

      expect(await scheduler.pendingIds(), [42, 100000]);
    });
  });

  group('W2 — показанное не остаётся в шторке при переплане', () {
    test('доставленное прошлого плана снимается по журналу (previousPlanIds)',
        () async {
      // План поставлен, одно уведомление сработало: оно вне pending и
      // «платформа» его не перечисляет (listsActive = false) — та самая
      // ситуация, из-за которой показанное оставалось в шторке.
      await applyNotificationPlan(
          scheduler, planOf([itemOf(100000), itemOf(100001)]));
      scheduler.deliver(100000);
      expect(scheduler.delivered.keys, [100000]);

      await applyNotificationPlan(
        scheduler,
        planOf([itemOf(100002)]),
        previousPlanIds: const [100000, 100001],
      );

      expect(scheduler.delivered, isEmpty,
          reason: 'журнал C7 обязан снять доставленное прошлого плана');
      expect(await scheduler.pendingIds(), [100002]);
    });

    test('без журнала (previousPlanIds пуст) поведение прежнее — доставленное '
        'снимает только платформа, умеющая перечислять', () async {
      await applyNotificationPlan(scheduler, planOf([itemOf(100000)]));
      scheduler.deliver(100000);

      await applyNotificationPlan(scheduler, planOf([itemOf(100001)]));

      expect(scheduler.delivered.keys, [100000],
          reason: 'порт не обещает перечисление показанных — это честная '
              'граница контракта, а не тихая потеря');
    });

    test('платформа с перечислением показанных снимает их сама (listsActive)',
        () async {
      scheduler.listsActive = true;
      await applyNotificationPlan(scheduler, planOf([itemOf(100000)]));
      scheduler.deliver(100000);

      await applyNotificationPlan(scheduler, planOf([itemOf(100001)]));

      expect(scheduler.delivered, isEmpty);
    });
  });

  group('полоса id приложения (D-36)', () {
    test('границы полосы: 100000..199999', () {
      expect(NotificationPlan.idRangeStart, 100000);
      expect(NotificationPlan.idRangeEnd, 199999);
    });

    test('W29: per-item отказ фейка не срывает остальные пункты', () async {
      scheduler.failIds.add(100001);

      final journal = await applyNotificationPlan(
          scheduler, planOf([itemOf(100000), itemOf(100001), itemOf(100002)]));

      expect(journal.failedIds, [100001]);
      expect(journal.isDegraded, isTrue);
      expect(await scheduler.pendingIds(), [100000, 100002]);
    });

    test('W29: платформа без планировщика — отказ по каждому пункту честной '
        'формы', () async {
      scheduler.schedulingSupported = false;

      final journal = await applyNotificationPlan(
          scheduler, planOf([itemOf(100000), itemOf(100001)]));

      expect(journal.items.map((i) => i.error),
          everyElement(isA<ScheduleUnsupportedException>()));
      expect(await scheduler.pendingIds(), isEmpty);
    });

    test('планирование вне полосы — ошибка, а не «как-нибудь»', () async {
      await expectLater(
        scheduler.schedule(itemOf(99999)),
        throwsArgumentError,
      );
      await expectLater(
        scheduler.schedule(itemOf(200000)),
        throwsArgumentError,
      );
      expect(await scheduler.pendingIds(), isEmpty);
    });

    test('cancel снимает ровно один id', () async {
      await applyNotificationPlan(
          scheduler, planOf([itemOf(100000), itemOf(100001)]));

      await scheduler.cancel(100000);

      expect(await scheduler.pendingIds(), [100001]);
    });
  });
}
