/// Порт планировщика уведомлений (D-34/D-36, блок D пакета 6.1).
///
/// Порт отделяет домен от вендора (урок 3 — чинить на слое причины): правила
/// планирования живут в [NotificationPlan], а платформенный адаптер
/// (`flutter_local_notifications` + `timezone`/`flutter_timezone`, F-55/F-56)
/// подключается пакетом 6.2 и заменяем без правки домена. Поэтому же тесты
/// работают без плагина и на Linux, где планирования нет вовсе (F-57).
///
/// **Отмена — по полосе id приложения** (100000–199999, D-36), а не
/// `cancelAll()`: `cancelAll` у платформы снёс бы и чужие уведомления, если
/// они когда-нибудь появятся.
library;

import 'notification_plan.dart';

/// Что домен умеет требовать от платформы.
abstract class NotificationScheduler {
  /// Поставить уведомление согласно пункту плана.
  Future<void> schedule(NotificationPlanItem item);

  /// Снять одно уведомление по id.
  Future<void> cancel(int id);

  /// Снять все уведомления полосы приложения `fromId..toId` включительно.
  Future<void> cancelRange({required int fromId, required int toId});

  /// Идентификаторы ожидающих уведомлений (для проверки идемпотентности).
  Future<List<int>> pendingIds();
}

/// Применить план идемпотентно: снять свою полосу, затем поставить заново
/// (D-36 — «cancelAll своего диапазона + schedule заново»).
///
/// Повторный вызов на том же плане не создаёт дублей: сначала полоса
/// очищается целиком, поэтому в pending остаются ровно пункты плана.
Future<void> applyNotificationPlan(
  NotificationScheduler scheduler,
  NotificationPlan plan,
) async {
  await scheduler.cancelRange(
    fromId: NotificationPlan.idRangeStart,
    toId: NotificationPlan.idRangeEnd,
  );
  for (final item in plan.items) {
    await scheduler.schedule(item);
  }
}
