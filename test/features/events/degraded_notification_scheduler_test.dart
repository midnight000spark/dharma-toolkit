/// Прямой тест деградированного планировщика уведомлений (пакет 6.2, F-57).
///
/// `DegradedNotificationScheduler` подключается, когда платформенный сервис
/// уведомлений не поднялся (Linux/ошибка инициализации; `main.dart`). Его
/// обещание — «ничего не планирую и говорю об этом в лог», а не тишина:
/// «уведомлений нет» обязано быть видно, а не угадываться (урок 1). Прямого
/// покрытия у него не было (C-01/§4.1 аудита 27.09) — тесты трогали класс лишь
/// как константу в биндинге композиции. Здесь проверяется каждый выход
/// warn-пути (schedule/cancel/cancelRange/pendingIds/canScheduleExact/
/// requestNotificationsPermission) и честный пустой `pendingIds()`.
library;

import 'package:dharma_toolkit/features/events/domain/notification_plan.dart';
import 'package:dharma_toolkit/features/events/domain/notification_scheduler.dart';
import 'package:dharma_toolkit/features/events/platform/degraded_notification_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

NotificationPlanItem itemOf(int id) => NotificationPlanItem(
      id: id,
      scheduledAt: DateTime(2026, 6, 2, 8),
      title: 'Событие',
      body: 'тело',
      payload: '{}',
    );

void main() {
  late List<String> warnings;
  late DegradedNotificationScheduler scheduler;

  setUp(() {
    warnings = [];
    scheduler = DegradedNotificationScheduler(
      reason: 'нет плагина',
      warn: warnings.add,
    );
  });

  test('pendingIds пуст и называет пропуск в warn', () async {
    expect(await scheduler.pendingIds(), isEmpty);
    expect(warnings, hasLength(1));
    expect(warnings.single, contains('нет плагина'));
    expect(warnings.single, contains('перечисление ожидающих'));
  });

  test('schedule/cancel/cancelRange не планируют, но пишут в warn', () async {
    await scheduler.schedule(itemOf(100000));
    await scheduler.cancel(100000);
    await scheduler.cancelRange(fromId: 100000, toId: 100001);

    expect(warnings, hasLength(3));
    expect(warnings[0], contains('планирование #100000'));
    expect(warnings[1], contains('снятие #100000'));
    expect(warnings[2], contains('снятие полосы 100000..100001'));
    for (final warning in warnings) {
      expect(warning, contains('нет плагина'));
    }
  });

  test('canScheduleExact — false: точность не обещана, но видна в warn',
      () async {
    expect(await scheduler.canScheduleExact(), isFalse);
    expect(warnings.single, contains('проверка точности'));
  });

  test('разрешение — unavailable, а не denied (деградация, не отказ)', () async {
    expect(
      await scheduler.requestNotificationsPermission(),
      NotificationPermission.unavailable,
    );
    expect(warnings.single, contains('разрешения'));
  });

  test('без warn-колбэка деградация не бросает (тишина вне приложения)',
      () async {
    final silent = DegradedNotificationScheduler(reason: 'x');
    await silent.schedule(itemOf(1));
    expect(await silent.pendingIds(), isEmpty);
  });
}
