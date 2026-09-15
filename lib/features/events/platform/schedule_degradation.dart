/// Честная деградация, когда платформа не умеет планировать уведомления
/// (F-57, пакет 6.2; урок 3 — чинить на слое причины).
///
/// Linux-реализация плагина переопределяет `initialize`/`show`/`cancel`, но
/// **не** `zonedSchedule`: базовый интерфейс бросает [UnimplementedError]
/// (проверено по исходникам platform_interface 12.2.0 L66–74 и
/// flutter_local_notifications_linux 8.0.1). Это не ошибка вызова и не повод
/// падать: планирования на платформе просто нет.
///
/// **Выбор поведения — осознанный: лог, а не немедленный показ.**
/// Немедленный показ всех пунктов плана (до 60 дней, D-36) означал бы залп
/// уведомлений при каждом перепланировании и враньё о дате события — прямое
/// нарушение UX-A-2 («напоминание, а не будильник») и FR-EVT-4 (никаких
/// показов в обход даты). Показ в обход планировщика остаётся доступен как
/// явный вызов `NotificationService.show` и решается на слое UI/демо, а не
/// здесь молчаливой подменой.
library;

import '../domain/notification_plan.dart';

/// Что делать, когда платформа отказалась ставить уведомление на дату.
abstract class ScheduleDegradation {
  /// Планирование пункта [item] не поддержано платформой ([error] — отказ
  /// вендора, сохраняется для диагностики).
  Future<void> onScheduleUnsupported(
      NotificationPlanItem item, UnimplementedError error);
}

/// Поведение по умолчанию: предупредить в лог и не показывать ничего.
///
/// Сообщение называет пункт и причину — иначе «тишина на Linux» выглядела бы
/// как успешное планирование, а это ровно тот класс дефектов, который закрыт
/// правилом приёмки «зелёное утверждение обязано подтверждаться».
class LogOnlyScheduleDegradation implements ScheduleDegradation {
  const LogOnlyScheduleDegradation({this.warn});

  /// Куда писать предупреждение (в приложении — `debugPrint`).
  final void Function(String message)? warn;

  @override
  Future<void> onScheduleUnsupported(
      NotificationPlanItem item, UnimplementedError error) async {
    warn?.call(
      'Планирование уведомлений не поддержано платформой (F-57): '
      '${item.id} «${item.title}» на ${item.scheduledAt.toIso8601String()} '
      'не поставлено. Причина: $error',
    );
  }
}
