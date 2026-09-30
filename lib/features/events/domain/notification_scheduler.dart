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

/// Исход применения одного пункта плана (C7).
enum PlanItemOutcome {
  /// Пункт принят планировщиком.
  applied,

  /// Планировщик отказал по этому пункту; остальные пункты не затронуты.
  failed,
}

/// Судьба одного пункта в применении плана.
class PlanItemApplication {
  const PlanItemApplication({
    required this.item,
    required this.outcome,
    this.error,
  });

  /// Пункт, который применялся.
  final NotificationPlanItem item;

  /// Исход пункта.
  final PlanItemOutcome outcome;

  /// Ошибка планировщика (заполнена только при [PlanItemOutcome.failed]).
  final Object? error;
}

/// Журнал применения плана (C7): снимок плана + исход по каждому пункту.
///
/// Снимок последнего плана — фундамент фикса W2 (снятие показанного по
/// журналу): планировщик не помнит, что было запланировано, а журнал помнит.
class NotificationApplicationJournal {
  const NotificationApplicationJournal({
    required this.plan,
    required this.items,
  });

  /// План, который применялся (исход — в [items], а не в самом факте).
  final NotificationPlan plan;

  /// Исход по пунктам в порядке плана.
  final List<PlanItemApplication> items;

  /// Был ли хоть один отказ — деградация, а не отказ целиком.
  bool get isDegraded => items.any((i) => i.outcome == PlanItemOutcome.failed);

  /// Идентификаторы пунктов, по которым планировщик отказал.
  List<int> get failedIds => [
        for (final i in items)
          if (i.outcome == PlanItemOutcome.failed) i.item.id,
      ];
}

/// Применить план идемпотентно и **по пунктам** (C7): снять свою полосу,
/// затем поставить каждый пункт, не прерывая остальные из-за одного отказа.
///
/// Возвращает журнал применения: снимок плана + исход по пунктам. Отказ по
/// пункту — деградация, а не исключение (раньше один `try` на весь план
/// срывал все оставшиеся уведомления). Отказ снятия полосы остаётся
/// исключением: ставить план поверх неочищенной полосы — это дубли
/// уведомлений, а не деградация.
Future<NotificationApplicationJournal> applyNotificationPlan(
  NotificationScheduler scheduler,
  NotificationPlan plan,
) async {
  await scheduler.cancelRange(
    fromId: NotificationPlan.idRangeStart,
    toId: NotificationPlan.idRangeEnd,
  );
  final applications = <PlanItemApplication>[];
  for (final item in plan.items) {
    try {
      await scheduler.schedule(item);
      applications.add(PlanItemApplication(
        item: item,
        outcome: PlanItemOutcome.applied,
      ));
    } catch (error) {
      applications.add(PlanItemApplication(
        item: item,
        outcome: PlanItemOutcome.failed,
        error: error,
      ));
    }
  }
  return NotificationApplicationJournal(plan: plan, items: applications);
}
