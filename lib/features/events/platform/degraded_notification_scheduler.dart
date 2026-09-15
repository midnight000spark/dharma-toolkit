/// Заглушка планировщика для старта без уведомлений (пакет 6.2).
///
/// Инициализация платформенного сервиса асинхронна (база таймзон + плагин) и
/// может отказать: у платформы нет планировщика, канал недоступен, устройство
/// стартовало в среде без сервиса уведомлений. Ронять из-за этого приложение
/// нельзя — напоминания не критичны для работы тулкита; но и **молчать** нельзя:
/// каждый отказ пишется в лог с причиной, поэтому «уведомлений нет» видно, а не
/// приходится угадывать (урок 1: зелёное утверждение обязано подтверждаться,
/// а тишина — не подтверждение).
///
/// Носит то же имя-«деградацию», что и `DegradedNotificationScheduler` в
/// отчёте composition root: путь отказа один и назван явно.
library;

import '../domain/notification_plan.dart';
import '../domain/notification_scheduler.dart';

/// Планировщик, который ничего не планирует и говорит об этом в лог.
class DegradedNotificationScheduler implements NotificationScheduler {
  DegradedNotificationScheduler({required this.reason, this.warn});

  /// Причина, по которой уведомления недоступны (для лога и диагностики).
  final String reason;

  /// Куда писать предупреждения (в приложении — `debugPrint`).
  final void Function(String message)? warn;

  void _notify(String what) {
    warn?.call('Уведомления недоступны ($reason): $what пропущено.');
  }

  @override
  Future<void> schedule(NotificationPlanItem item) async =>
      _notify('планирование #${item.id}');

  @override
  Future<void> cancel(int id) async => _notify('снятие #$id');

  @override
  Future<void> cancelRange({required int fromId, required int toId}) async =>
      _notify('снятие полосы $fromId..$toId');

  @override
  Future<List<int>> pendingIds() async {
    _notify('перечисление ожидающих');
    return const [];
  }
}
