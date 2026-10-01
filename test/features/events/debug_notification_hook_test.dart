/// Dev-хук демо-напоминания: гейт, полоса id, путь через реальный порт
/// (блок A пакета 6.3).
///
/// Проверяется поведение, а не факт отрисовки: выключенный гейт обязан
/// означать «действия не было» (возврат `false` и пустой планировщик), а не
/// молчаливый no-op, который выглядит как успех (урок 1). Мутация
/// «дефолт гейта → константа» обязана красить тест о `kDebugMode`.
library;

import 'package:dharma_toolkit/core/events/event_bus.dart';
import 'package:dharma_toolkit/core/events/event_bus_provider.dart';
import 'package:dharma_toolkit/core/events/preset_events.dart';
import 'package:dharma_toolkit/features/events/domain/notification_plan.dart';
import 'package:dharma_toolkit/features/events/domain/notification_scheduler.dart';
import 'package:dharma_toolkit/features/events/presentation/dev/debug_notification_button.dart';
import 'package:dharma_toolkit/features/events/presentation/providers/event_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'in_memory_notification_scheduler.dart';

void main() {
  final now = DateTime(2026, 9, 17, 12, 0);

  group('гейт', () {
    test('дефолт гейта — решение приложения (kDebugMode), не литерал', () {
      // Мутация «gate ?? false» (или `?? true`) обязана покрасить это
      // утверждение: в тестовом прогоне kDebugMode == true, и подмена дефолта
      // литералом видна именно здесь.
      expect(debugDemoEnabled(), kDebugMode);
    });

    test('явный гейт перекрывает дефолт в обе стороны', () {
      expect(debugDemoEnabled(gate: false), isFalse);
      expect(debugDemoEnabled(gate: true), isTrue);
    });
  });

  group('постановка демо-напоминания через порт планировщика', () {
    test('гейт выключен → действия нет, планировщик пуст', () async {
      final scheduler = InMemoryNotificationScheduler();

      final scheduled = await scheduleDebugDemoNotification(
        scheduler: scheduler,
        now: now,
        gate: false,
      );

      expect(scheduled, isFalse);
      expect(scheduler.scheduled, isEmpty);
    });

    test('гейт включён → ровно один пункт в инструментальной под-полосе, '
        '+1 минута', () async {
      final scheduler = InMemoryNotificationScheduler();

      final scheduled = await scheduleDebugDemoNotification(
        scheduler: scheduler,
        now: now,
        gate: true,
      );

      expect(scheduled, isTrue);
      expect(scheduler.scheduled.keys.toList(), [debugDemoNotificationId]);
      final item = scheduler.scheduled.values.single;
      // S9: демо — вне рабочей полосы, чтобы переплан его не снимал.
      expect(item.id, inInclusiveRange(
          NotificationPlan.devRangeStart, NotificationPlan.devRangeEnd));
      expect(item.id,
          isNot(inInclusiveRange(
              NotificationPlan.idRangeStart, NotificationPlan.idRangeEnd)),
          reason: 'демо внутри рабочей полосы — коллизия отмены (S9)');
      expect(item.scheduledAt, now.add(debugDemoDelay));
      expect(item.title, 'Демо: проверка напоминаний');
      expect(item.payload, contains('debugDemo'));
    });

    test('S9: переплан не трогает демо — оно вне рабочей полосы', () async {
      final scheduler = InMemoryNotificationScheduler();
      await scheduleDebugDemoNotification(
        scheduler: scheduler,
        now: now,
        gate: true,
      );

      // Переплан применяет рабочий план: снимает рабочую полосу и ставит
      // пункты. Демо (инструментальная под-полоса) обязан пережить это.
      await applyNotificationPlan(
        scheduler,
        NotificationPlan(
          items: [
            NotificationPlanItem(
              id: NotificationPlan.idRangeStart,
              scheduledAt: now.add(const Duration(days: 1)),
              title: 'Рабочий пункт',
              body: 'тело',
              payload: '{}',
            ),
          ],
          notes: const [],
        ),
      );

      expect(scheduler.scheduled.keys, contains(debugDemoNotificationId),
          reason: 'переплан чистит рабочую полосу, а не инструментальную (S9)');
      expect(scheduler.scheduled.keys, contains(NotificationPlan.idRangeStart));
    });
  });

  group('кнопка', () {
    Widget host({
      required bool? gate,
      required InMemoryNotificationScheduler s,
      EventBus? bus,
    }) {
      return ProviderScope(
        overrides: [
          notificationSchedulerProvider.overrideWithValue(s),
          eventsClockProvider.overrideWithValue(() => now),
          if (bus != null) eventBusProvider.overrideWithValue(bus),
        ],
        child: MaterialApp(
            home: Scaffold(body: DebugNotificationButton(gate: gate))),
      );
    }

    testWidgets('гейт выключен — кнопки нет (SizedBox.shrink)', (tester) async {
      final scheduler = InMemoryNotificationScheduler();
      await tester.pumpWidget(host(gate: false, s: scheduler));

      expect(find.byType(InkWell), findsNothing);
      expect(find.text('demo +1 мин'), findsNothing);
    });

    testWidgets('гейт включён — нажатие ставит напоминание через порт',
        (tester) async {
      final scheduler = InMemoryNotificationScheduler();
      await tester.pumpWidget(host(gate: true, s: scheduler));

      expect(find.text('demo +1 мин'), findsOneWidget);
      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();

      expect(scheduler.scheduled.keys.toList(), [debugDemoNotificationId]);
      expect(find.text('запланировано'), findsOneWidget);
    });

    testWidgets('S9: переплан, не тронувший демо, ярлык не портит',
        (tester) async {
      final bus = EventBus();
      addTearDown(bus.dispose);
      final scheduler = InMemoryNotificationScheduler();
      await tester.pumpWidget(host(gate: true, s: scheduler, bus: bus));

      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();
      expect(find.text('запланировано'), findsOneWidget);

      // Триггер переплана без снятия демо: демо в под-полосе — ярлык правдив.
      bus.publish(PresetChanged(traditionTag: 'nyingma'));
      await tester.pumpAndSettle();

      expect(find.text('запланировано'), findsOneWidget);
      expect(scheduler.scheduled.keys, contains(debugDemoNotificationId));
    });

    testWidgets('S9: снятое демо — ярлык «снят перепланом», а не враньё',
        (tester) async {
      final bus = EventBus();
      addTearDown(bus.dispose);
      final scheduler = InMemoryNotificationScheduler();
      await tester.pumpWidget(host(gate: true, s: scheduler, bus: bus));

      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();
      expect(find.text('запланировано'), findsOneWidget);

      // Демо снято (явное действие/будущий переплан) и пришёл триггер:
      // прежний ярлык продолжал бы обещать «запланировано» (S9).
      await scheduler.cancel(debugDemoNotificationId);
      bus.publish(PresetChanged(traditionTag: 'nyingma'));
      await tester.pumpAndSettle();

      expect(find.text('снят перепланом'), findsOneWidget);
      expect(find.text('запланировано'), findsNothing);
    });
  });
}
