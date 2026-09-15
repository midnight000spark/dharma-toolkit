/// Адаптер порта планировщика к платформенному сервису (блок B пакета 6.2).
///
/// Домен (`NotificationScheduler`, 6.1) не знает ни о вендоре, ни о таймзонах:
/// его пункты — [NotificationPlanItem] с локальными датой-временем и id в
/// полосе приложения. Адаптер — место, где это встречается с
/// [NotificationService]; он же держит **границу полосы id** (D-36): планировать
/// уведомление вне 100000–199999 нельзя, иначе отмена по диапазону перестанет
/// находить свои уведомления, а `pendingIds` смешается с чужими.
///
/// Проверка дублирует одноимённый инвариант домена не «на всякий случай»: за
/// адаптером стоит платформа, где ошибка видна не сразу (уведомление просто
/// не снимется при смене пресета), поэтому граница проверяется на входе в
/// платформенный слой, где она и нарушается.
library;

import '../domain/notification_plan.dart';
import '../domain/notification_scheduler.dart';
import 'notification_service.dart';

/// Платформенный [NotificationScheduler] поверх [NotificationService].
class NotificationSchedulerAdapter implements NotificationScheduler {
  NotificationSchedulerAdapter(this._service);

  final NotificationService _service;

  @override
  Future<void> schedule(NotificationPlanItem item) async {
    _ensureOwnRange(item.id);
    await _service.schedule(item);
  }

  @override
  Future<void> cancel(int id) => _service.cancel(id);

  @override
  Future<void> cancelRange({required int fromId, required int toId}) =>
      _service.cancelRange(fromId: fromId, toId: toId);

  @override
  Future<List<int>> pendingIds() => _service.pendingIds();

  static void _ensureOwnRange(int id) {
    if (id < NotificationPlan.idRangeStart || id > NotificationPlan.idRangeEnd) {
      throw ArgumentError.value(
        id,
        'item.id',
        'идентификатор вне полосы приложения '
            '${NotificationPlan.idRangeStart}..${NotificationPlan.idRangeEnd} '
            '(D-36): такое уведомление не снимется отменой по диапазону',
      );
    }
  }
}
