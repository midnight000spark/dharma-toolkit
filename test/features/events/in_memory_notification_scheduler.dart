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
  InMemoryNotificationScheduler({
    this.permission = NotificationPermission.granted,
  });

  /// Что вернёт запрос разрешения (W1): тесты проверяют и отказ, и согласие.
  NotificationPermission permission;

  /// Сколько раз спрашивали разрешение (запрос обязан состояться — W1).
  int permissionRequests = 0;

  final Map<int, NotificationPlanItem> scheduled = {};

  /// Доставленные (показанные) уведомления: id → пункт (W2). Доставка — явное
  /// действие теста [deliver], как в жизни — исход таймера; доставленное больше
  /// не числится ожидающим.
  final Map<int, NotificationPlanItem> delivered = {};

  /// Умеет ли «платформа» перечислять показанные (W2)? Дефолт `false` —
  /// минимальный контракт порта: полоса снимает ожидающие, а доставленные
  /// домен обязан снять по журналу (`previousPlanIds`). `true` — платформа,
  /// которая перечисляет показанные сама.
  bool listsActive = false;

  /// Отвечает ли «платформа» за точное планирование (W29): контракт порта —
  /// `schedule` ставит exact только при `true`, иначе честный inexact (D-36).
  bool exactAllowed = false;

  /// Пункты, на которых фейк отказывает (W29): per-item отказ — как отказ
  /// платформы по конкретному уведомлению (остальные не затронуты).
  final Set<int> failIds = {};

  /// Поддерживает ли «платформа» планирование вовсе (F-57): при `false`
  /// каждый пункт отказывает [ScheduleUnsupportedException].
  bool schedulingSupported = true;

  /// Сколько раз вызывали `cancelRange` (видно идемпотентность переплана).
  int cancelRangeCalls = 0;

  /// «Сработало»: пункт покидает ожидающие и появляется в показанных.
  /// Возвращает снятый пункт (null — такого ожидающего не было).
  NotificationPlanItem? deliver(int id) {
    final item = scheduled.remove(id);
    if (item != null) delivered[id] = item;
    return item;
  }

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
    if (!schedulingSupported) {
      throw ScheduleUnsupportedException(item.id);
    }
    if (failIds.contains(item.id)) {
      throw StateError('пункт ${item.id} не поставлен (per-item отказ, W29)');
    }
    scheduled[item.id] = item;
  }

  @override
  Future<void> cancel(int id) async {
    scheduled.remove(id);
    delivered.remove(id);
  }

  @override
  Future<void> cancelRange({required int fromId, required int toId}) async {
    cancelRangeCalls++;
    scheduled.removeWhere((id, _) => id >= fromId && id <= toId);
    if (listsActive) {
      delivered.removeWhere((id, _) => id >= fromId && id <= toId);
    }
  }

  @override
  Future<List<int>> pendingIds() async => scheduled.keys.toList()..sort();

  @override
  Future<bool> canScheduleExact() async => exactAllowed;

  @override
  Future<NotificationPermission> requestNotificationsPermission() async {
    permissionRequests++;
    return permission;
  }
}
