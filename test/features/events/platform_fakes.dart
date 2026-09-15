/// Фейки платформенного слоя уведомлений (пакет 6.2) — не сюит.
///
/// Подменяют ровно тот шов, который объявлен в `lib/features/events/platform`:
/// транспорт плагина и источник таймзоны. Благодаря этому политика сервиса
/// (настройки по платформам, режим точности, деградация Linux) проверяется без
/// устройства и без плагина, а тест способен **покраснеть** от неверного
/// поведения (урок 1), а не только подтвердить факт вызова.
library;

import 'package:dharma_toolkit/features/events/domain/notification_plan.dart';
import 'package:dharma_toolkit/features/events/platform/notification_gateway.dart';
import 'package:dharma_toolkit/features/events/platform/schedule_degradation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

/// Зафиксированный вызов `show`.
class ShownCall {
  const ShownCall({
    required this.id,
    required this.title,
    required this.body,
    required this.payload,
  });

  final int id;
  final String title;
  final String body;
  final String payload;
}

/// Зафиксированный вызов `zonedSchedule`.
class ScheduledCall {
  const ScheduledCall({
    required this.id,
    required this.scheduledDate,
    required this.mode,
    required this.title,
    required this.body,
    required this.payload,
  });

  final int id;
  final tz.TZDateTime scheduledDate;
  final AndroidScheduleMode mode;
  final String title;
  final String body;
  final String payload;
}

/// Транспорт в памяти: помнит вызовы и отказы, которые ему велели сыграть.
class FakeNotificationGateway implements NotificationGateway {
  /// Инициализировали ли плагин и с какими настройками.
  bool initializeCalled = false;
  InitializationSettings? settings;

  /// Показанные немедленно уведомления.
  final List<ShownCall> shown = [];

  /// Поставленные на дату уведомления (порядок вызовов).
  final List<ScheduledCall> scheduled = [];

  /// Снятые id (порядок вызовов).
  final List<int> cancelled = [];

  /// Ожидающие уведомления: сюда же можно предзаполнить «чужие» id.
  final List<int> pending = [];

  /// Отвечает ли платформа, что точное планирование разрешено (Android 14+).
  bool exactAllowed = false;

  /// Чем сыграть отказ: `UnimplementedError` — платформа без планировщика
  /// (Linux, F-57).
  Object? zonedScheduleError;
  Object? pendingIdsError;

  @override
  Future<void> initialize({
    required InitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
  }) async {
    initializeCalled = true;
    this.settings = settings;
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    required NotificationDetails details,
    required String payload,
  }) async {
    shown.add(ShownCall(id: id, title: title, body: body, payload: payload));
  }

  @override
  Future<void> zonedSchedule({
    required int id,
    required tz.TZDateTime scheduledDate,
    required NotificationDetails details,
    required AndroidScheduleMode androidScheduleMode,
    required String title,
    required String body,
    required String payload,
  }) async {
    final error = zonedScheduleError;
    if (error != null) throw error;
    scheduled.add(ScheduledCall(
      id: id,
      scheduledDate: scheduledDate,
      mode: androidScheduleMode,
      title: title,
      body: body,
      payload: payload,
    ));
    if (!pending.contains(id)) pending.add(id);
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    pending.remove(id);
  }

  @override
  Future<List<int>> pendingIds() async {
    final error = pendingIdsError;
    if (error != null) throw error;
    return List.of(pending);
  }

  @override
  Future<bool> canScheduleExactNotifications() async => exactAllowed;
}

/// Таймзона устройства, подставленная тестом (в тестовом процессе метод-канал
/// `FlutterTimezone` недоступен).
class FakeLocalTimeZoneSource implements LocalTimeZoneSource {
  FakeLocalTimeZoneSource(this.zone);

  final String zone;
  int calls = 0;

  @override
  Future<String> identifier() async {
    calls++;
    return zone;
  }
}

/// Деградация, которая запоминает, что ей отдали.
class RecordingScheduleDegradation implements ScheduleDegradation {
  /// Пункты, планирование которых платформа отвергла.
  final List<NotificationPlanItem> unsupported = [];

  /// Отказы вендора, как их увидел сервис.
  final List<UnimplementedError> errors = [];

  @override
  Future<void> onScheduleUnsupported(
      NotificationPlanItem item, UnimplementedError error) async {
    unsupported.add(item);
    errors.add(error);
  }
}
