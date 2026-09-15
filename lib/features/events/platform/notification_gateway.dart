/// Шов между политикой уведомлений и вендором `flutter_local_notifications`
/// (F-55, пакет 6.2).
///
/// **Зачем шов, если есть плагин.** `FlutterLocalNotificationsPlugin` в 22.3.0 —
/// не просто класс: у него приватный конструктор и фабрика-синглтон
/// (`factory FlutterLocalNotificationsPlugin() => _instance`), поэтому его
/// **нельзя ни подклассом, ни моком** подменить точечно. Требование «интерфейс
/// для внешней зависимости» (AGENT, правила кода) и урок 1 («тест обязан
/// уметь покраснеть») закрываются узким собственным интерфейсом: политика
/// (какие настройки, какой режим точности, что делать при отказе платформы)
/// живёт в [NotificationService] и проверяется без плагина, а транспорт —
/// здесь, в одном тонком классе без ветвлений.
///
/// Шов объявляет ровно то, что приложение использует: шесть вызовов. Расти ему
/// без нужды нельзя — каждый новый метод тянет за собой недоказуемый код.
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/timezone.dart' as tz;

/// Что приложение требует от локальных уведомлений платформы.
abstract class NotificationGateway {
  /// Инициализировать плагин настройками по платформам.
  Future<void> initialize({
    required InitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
  });

  /// Показать уведомление немедленно.
  Future<void> show({
    required int id,
    required String title,
    required String body,
    required NotificationDetails details,
    required String payload,
  });

  /// Поставить уведомление на момент [scheduledDate] в таймзоне [tz.local].
  ///
  /// Платформа без планировщика (Linux, F-57) обязана бросить
  /// [UnimplementedError] — это и есть сигнал деградации, а не тишина.
  Future<void> zonedSchedule({
    required int id,
    required tz.TZDateTime scheduledDate,
    required NotificationDetails details,
    required AndroidScheduleMode androidScheduleMode,
    required String title,
    required String body,
    required String payload,
  });

  /// Снять уведомление по id (и запланированное, и уже показанное).
  Future<void> cancel(int id);

  /// Идентификаторы ожидающих уведомлений; платформа без перечисления бросает
  /// [UnimplementedError] (F-57).
  Future<List<int>> pendingIds();

  /// Доступно ли *точное* планирование (Android 14+, F-57). Платформа без
  /// такого понятия отвечает `false` — «точность не обещана».
  Future<bool> canScheduleExactNotifications();
}

/// Транспорт поверх `FlutterLocalNotificationsPlugin` — единственное место,
/// где приложение касается вендора напрямую.
class FlutterLocalNotificationsGateway implements NotificationGateway {
  FlutterLocalNotificationsGateway();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  @override
  Future<void> initialize({
    required InitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
  }) async {
    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: onDidReceiveNotificationResponse,
    );
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    required NotificationDetails details,
    required String payload,
  }) async {
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: details,
      payload: payload,
    );
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
    await _plugin.zonedSchedule(
      id: id,
      scheduledDate: scheduledDate,
      notificationDetails: details,
      androidScheduleMode: androidScheduleMode,
      title: title,
      body: body,
      payload: payload,
    );
  }

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);

  @override
  Future<List<int>> pendingIds() async {
    final pending = await _plugin.pendingNotificationRequests();
    return [for (final request in pending) request.id];
  }

  @override
  Future<bool> canScheduleExactNotifications() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    // Не-Android (или Android без платформенной реализации) точности не
    // обещает: `null` — «спросить не у кого», а не «разрешено».
    return await android?.canScheduleExactNotifications() ?? false;
  }
}

/// Источник IANA-имени таймзоны устройства (F-56).
///
/// `timezone` читать зону устройства не умеет, `FlutterTimezone` — статический
/// класс с метод-каналом, который в тестах недоступен. Поэтому шов: политика
/// инициализации проверяется с подставленным именем, а платформа — здесь.
abstract class LocalTimeZoneSource {
  /// IANA-имя локальной зоны, например `Europe/Moscow`.
  Future<String> identifier();
}

/// Продовая реализация: имя зоны у нативной платформы.
class FlutterTimeZoneSource implements LocalTimeZoneSource {
  const FlutterTimeZoneSource();

  @override
  Future<String> identifier() async =>
      (await FlutterTimezone.getLocalTimezone()).identifier;
}
