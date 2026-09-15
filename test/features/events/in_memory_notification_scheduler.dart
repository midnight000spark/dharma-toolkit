/// In-memory реализация порта планировщика для тестов (блок D пакета 6.1).
///
/// НЕ тестовый сюит (нет `*_test.dart` — не запускается), а хелпер: запоминает
/// запланированное и снятое, поэтому идемпотентность перепланирования и полоса
/// id проверяются без плагина и без платформы (F-57 — на Linux планирования
/// нет вовсе).
///
/// Фейк **строг к полосе id**: планирование уведомления вне полосы приложения
/// (D-36: 100000–199999) — ошибка, а не «как-нибудь». Молчаливое планирование
/// за пределами своей полосы сломало бы отмену по диапазону.
library;

import 'package:dharma_toolkit/features/events/domain/notification_plan.dart';
import 'package:dharma_toolkit/features/events/domain/notification_scheduler.dart';

/// Планировщик в памяти: ничего не показывает, всё помнит.
class InMemoryNotificationScheduler implements NotificationScheduler {
  final Map<int, NotificationPlanItem> scheduled = {};

  /// Сколько раз вызывали `cancelRange` (видно идемпотентность переплана).
  int cancelRangeCalls = 0;

  @override
  Future<void> schedule(NotificationPlanItem item) async {
    if (item.id < NotificationPlan.idRangeStart ||
        item.id > NotificationPlan.idRangeEnd) {
      throw ArgumentError.value(
        item.id,
        'item.id',
        'идентификатор вне полосы приложения '
            '${NotificationPlan.idRangeStart}..${NotificationPlan.idRangeEnd} '
            '(D-36)',
      );
    }
    scheduled[item.id] = item;
  }

  @override
  Future<void> cancel(int id) async {
    scheduled.remove(id);
  }

  @override
  Future<void> cancelRange({required int fromId, required int toId}) async {
    cancelRangeCalls++;
    scheduled.removeWhere((id, _) => id >= fromId && id <= toId);
  }

  @override
  Future<List<int>> pendingIds() async => scheduled.keys.toList()..sort();
}
