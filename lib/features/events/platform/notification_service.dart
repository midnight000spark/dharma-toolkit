/// Платформенный сервис локальных уведомлений (F-55/F-56/F-57, блок A пакета
/// 6.2).
///
/// Здесь живёт **политика**, а не транспорт: какие настройки инициализации
/// дать платформам, в какой таймзоне считать момент, с какой точностью ставить
/// (exact при разрешении, иначе честный inexact — D-36), что делать при отказе
/// платформы. Вендор спрятан за [NotificationGateway], поэтому все решения
/// сервиса проверяются тестами без плагина и без устройства.
///
/// **Таймзоны (F-56).** `TZDateTime` без поднятой базы бросает
/// `LocationNotFoundException`, а `timezone` по умолчанию считает локалью UTC —
/// то есть «08:00» превратилось бы в 08:00 UTC, враньё о времени практикующего
/// (D-36: дефолт 08:00 *локального*). Поэтому [initialize] обязан поднять базу
/// и выставить локальную зону; отказ — исключение, а не тихая работа в UTC.
///
/// **Права.** Показ на Android 13+ требует runtime-разрешения
/// `POST_NOTIFICATIONS`, точная точность — `SCHEDULE_EXACT_ALARM` (F-57).
/// Диалоги разрешений — не этот слой: их показывает UI (Этап 8, SCR-12/14),
/// а сервис лишь честно отвечает на вопрос о точности ([canScheduleExact]).
/// [show] — путь немедленного показа: он же используется демо-сценарием на
/// платформе без планировщика.
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../domain/notification_plan.dart';
import 'notification_gateway.dart';
import 'schedule_degradation.dart';

/// Обёртка над плагином уведомлений: инициализация, показ, планирование.
class NotificationService {
  NotificationService({
    required this.gateway,
    required this.timeZoneSource,
    ScheduleDegradation? degradation,
    this.warn,
  }) : degradation =
            degradation ?? LogOnlyScheduleDegradation(warn: warn);

  final NotificationGateway gateway;
  final LocalTimeZoneSource timeZoneSource;

  /// Поведение при отказе платформы планировать (F-57).
  final ScheduleDegradation degradation;

  /// Куда писать предупреждения (в приложении — `debugPrint`).
  final void Function(String message)? warn;

  /// Канал уведомлений (Android 8+): тихий — importance/priority low (D-36,
  /// UX-A-2: напоминание, а не будильник).
  static const String channelId = 'dharma_reminders';
  static const String channelName = 'Напоминания о событиях';
  static const String channelDescription = 'Особые дни календаря традиции';

  /// Настройки инициализации по платформам (F-55).
  ///
  /// Разрешения на iOS/macOS **не запрашиваются при инициализации**
  /// (`requestAlertPermission: false` и т.д.): запрос — решение пользователя
  /// в UI-контексте, а не побочный эффект старта приложения.
  static const InitializationSettings initializationSettings =
      InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    iOS: DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    ),
    macOS: DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    ),
    linux: LinuxInitializationSettings(defaultActionName: 'Открыть'),
  );

  /// Детали показа: один тихий канал на все напоминания.
  static const NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.low,
      priority: Priority.low,
    ),
    iOS: DarwinNotificationDetails(),
    macOS: DarwinNotificationDetails(),
    linux: LinuxNotificationDetails(),
  );

  /// Поднять базу таймзон, выставить локальную зону устройства и
  /// инициализировать плагин.
  ///
  /// Бросает [tz.LocationNotFoundException], если платформа назвала зону, а
  /// такой в базе нет, и любые отказы плагина. Вызывается из composition root:
  /// там отказ превращается в честную деградацию «уведомлений нет», а не в
  /// работу по UTC или в падение старта.
  Future<void> initialize() async {
    tz_data.initializeTimeZones();
    final identifier = await timeZoneSource.identifier();
    tz.setLocalLocation(tz.getLocation(identifier));
    await gateway.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );
  }

  /// Показать уведомление немедленно (без планирования).
  ///
  /// Единственный путь показа на платформе, где планирование не поддержано
  /// (F-57): вызывается явно, а не подменяет собой молча неудавшееся
  /// планирование (см. [ScheduleDegradation]).
  Future<void> show(NotificationPlanItem item) async {
    await gateway.show(
      id: item.id,
      title: item.title,
      body: item.body,
      details: _details,
      payload: item.payload,
    );
  }

  /// Поставить уведомление по пункту плана [item].
  ///
  /// Момент берётся в локальной зоне устройства: `scheduledAt` домена —
  /// локальные дата-время (D-36), а `TZDateTime` нужен плагину (F-56).
  ///
  /// Точность честная: [canScheduleExact] даёт `exact` только при реально
  /// выданном разрешении, иначе `inexact` — D-36 запрещает обещать точность,
  /// которой нет (F-57: при отозванном разрешении Android exact-планирование
  /// просто не выполняется с ошибкой в лог).
  ///
  /// Отказ платформы «планирования нет вовсе» ([UnimplementedError], Linux)
  /// уходит в [ScheduleDegradation], а не наружу: это не сбой приложения,
  /// а известное ограничение (F-57, урок 3).
  Future<void> schedule(NotificationPlanItem item) async {
    try {
      await gateway.zonedSchedule(
        id: item.id,
        scheduledDate: tz.TZDateTime.from(item.scheduledAt, tz.local),
        details: _details,
        androidScheduleMode: await _androidScheduleMode(),
        title: item.title,
        body: item.body,
        payload: item.payload,
      );
    } on UnimplementedError catch (error) {
      await degradation.onScheduleUnsupported(item, error);
    }
  }

  /// Снять уведомление по id.
  Future<void> cancel(int id) => gateway.cancel(id);

  /// Снять уведомления полосы приложения `fromId..toId` включительно.
  ///
  /// Отмена идёт **по своему диапазону id**, а не `cancelAll()` (D-36):
  /// `cancelAll` платформы снёс бы и уведомления, которые приложение поставит
  /// когда-нибудь вне полосы напоминаний. Чужие id не трогаются: перечисляются
  /// ожидающие уведомления и снимаются только попавшие в диапазон.
  Future<void> cancelRange({required int fromId, required int toId}) async {
    if (fromId > toId) {
      throw ArgumentError.value(
          '$fromId > $toId', 'fromId..toId', 'начало не может быть позже конца');
    }
    final pending = await pendingIds();
    for (final id in pending) {
      if (id < fromId || id > toId) continue;
      await gateway.cancel(id);
    }
  }

  /// Идентификаторы ожидающих уведомлений.
  ///
  /// Платформа без перечисления ожидающих (Linux, F-57) даёт пустой список с
  /// предупреждением: там и планирование невозможно, поэтому «ожидающих нет» —
  /// правда, а не сокрытие отказа. На платформах с планированием (Android/iOS)
  /// перечисление поддержано, и пустой список означает именно «ничего не
  /// поставлено».
  Future<List<int>> pendingIds() async {
    try {
      return await gateway.pendingIds();
    } on UnimplementedError {
      warn?.call(
        'Платформа не перечисляет запланированные уведомления (F-57): '
        'ожидающих нет — планирование на ней не поддерживается.',
      );
      return const [];
    }
  }

  /// Доступно ли точное планирование (Android 14+, F-57).
  ///
  /// `false` — не «ошибка», а «точность не обещана»: вызывающий обязан
  /// выбрать inexact (D-36).
  Future<bool> canScheduleExact() async {
    try {
      return await gateway.canScheduleExactNotifications();
    } on UnimplementedError {
      return false;
    }
  }

  Future<AndroidScheduleMode> _androidScheduleMode() async =>
      await canScheduleExact()
          ? AndroidScheduleMode.exact
          : AndroidScheduleMode.inexact;

  void _onNotificationResponse(NotificationResponse response) {
    // Навигация по нажатию — Этап 8 (SCR-12/14): пока честная запись в лог,
    // без молчаливой «обработки», которой нет.
    warn?.call(
      'Нажатие на уведомление: id=${response.id}, '
      'payload="${response.payload ?? ''}"',
    );
  }
}
