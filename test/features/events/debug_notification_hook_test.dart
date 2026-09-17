/// Dev-хук демо-напоминания: гейт, полоса id, путь через реальный порт
/// (блок A пакета 6.3).
///
/// Проверяется поведение, а не факт отрисовки: выключенный гейт обязан
/// означать «действия не было» (возврат `false` и пустой планировщик), а не
/// молчаливый no-op, который выглядит как успех (урок 1). Мутация
/// «дефолт гейта → константа» обязана красить тест о `kDebugMode`.
library;

import 'package:dharma_toolkit/features/events/domain/notification_plan.dart';
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

    test('гейт включён → ровно один пункт в полосе приложения, +1 минута',
        () async {
      final scheduler = InMemoryNotificationScheduler();

      final scheduled = await scheduleDebugDemoNotification(
        scheduler: scheduler,
        now: now,
        gate: true,
      );

      expect(scheduled, isTrue);
      expect(scheduler.scheduled.keys.toList(), [debugDemoNotificationId]);
      final item = scheduler.scheduled.values.single;
      expect(item.id, inInclusiveRange(
          NotificationPlan.idRangeStart, NotificationPlan.idRangeEnd));
      expect(item.scheduledAt, now.add(debugDemoDelay));
      expect(item.title, 'Демо: проверка напоминаний');
      expect(item.payload, contains('debugDemo'));
    });
  });

  group('кнопка', () {
    Widget host({required bool? gate, required InMemoryNotificationScheduler s}) {
      return ProviderScope(
        overrides: [
          notificationSchedulerProvider.overrideWithValue(s),
          eventsClockProvider.overrideWithValue(() => now),
        ],
        child: MaterialApp(home: Scaffold(body: DebugNotificationButton(gate: gate))),
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
  });
}
