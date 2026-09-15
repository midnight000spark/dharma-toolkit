/// Адаптер порта планировщика: граница полосы id и идемпотентность
/// перепланирования (блок B пакета 6.2).
///
/// Проверяется то, что видно пользователю при смене традиции: старые
/// напоминания снимаются, новые ставятся, чужие id не трогаются. Идемпотентность
/// измеряется на уровне «что осталось в pending», а не «сколько раз вызвали
/// метод» (урок 4).
library;

import 'package:dharma_toolkit/features/events/domain/notification_plan.dart';
import 'package:dharma_toolkit/features/events/domain/notification_scheduler.dart';
import 'package:dharma_toolkit/features/events/platform/notification_scheduler_adapter.dart';
import 'package:dharma_toolkit/features/events/platform/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'platform_fakes.dart';

void main() {
  late FakeNotificationGateway gateway;
  late NotificationSchedulerAdapter adapter;

  setUp(() async {
    gateway = FakeNotificationGateway();
    final service = NotificationService(
      gateway: gateway,
      timeZoneSource: FakeLocalTimeZoneSource('Europe/Moscow'),
    );
    // Планирование работает только после инициализации: TZDateTime берёт
    // локальную зону из поднятой базы, а не из UTC-дефолта (F-56).
    await service.initialize();
    adapter = NotificationSchedulerAdapter(service);
  });

  NotificationPlanItem item(int id, String title) => NotificationPlanItem(
        id: id,
        scheduledAt: DateTime(2026, 6, 2, 8),
        title: title,
        body: 'Особый день',
        payload: '',
      );

  test('schedule ставит уведомление через платформенный сервис', () async {
    await adapter.schedule(item(NotificationPlan.idRangeStart, 'День'));

    expect(gateway.scheduled.single.id, NotificationPlan.idRangeStart);
    expect(gateway.scheduled.single.title, 'День');
  });

  test('schedule вне полосы приложения — ошибка, а не планирование', () async {
    expect(
      () => adapter.schedule(item(1, 'Чужой id')),
      throwsA(isA<ArgumentError>()),
    );
    expect(gateway.scheduled, isEmpty);
  });

  test('повторный applyNotificationPlan не оставляет дублей', () async {
    final plan = NotificationPlan(
      items: [item(100000, 'Первый'), item(100001, 'Второй')],
      notes: const [],
    );

    await applyNotificationPlan(adapter, plan);
    await applyNotificationPlan(adapter, plan);

    expect(gateway.pending, [100000, 100001]);
  });

  test('новый план короче — хвост прежнего снимается отменой по полосе',
      () async {
    await applyNotificationPlan(
      adapter,
      NotificationPlan(
        items: [item(100000, 'Первый'), item(100001, 'Второй')],
        notes: const [],
      ),
    );

    await applyNotificationPlan(
      adapter,
      NotificationPlan(items: [item(100000, 'Первый')], notes: const []),
    );

    expect(gateway.pending, [100000]);
  });

  test('полоса id не задевает уведомления вне неё', () async {
    gateway.pending.addAll([7, 300000]);

    await applyNotificationPlan(
      adapter,
      NotificationPlan(items: [item(100000, 'Первый')], notes: const []),
    );

    expect(gateway.pending, [7, 300000, 100000]);
  });

  test('pendingIds отдаёт ожидающие уведомления платформы', () async {
    gateway.pending.addAll([100001, 100000]);

    expect(await adapter.pendingIds(), [100001, 100000]);
  });
}
