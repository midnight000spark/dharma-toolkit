/// Сервис уведомлений: политика платформенного слоя (блок A пакета 6.2).
///
/// Проверяется поведение, а не факт наличия класса: какие настройки уходят
/// платформам, с какой точностью ставится уведомление (D-36: честный inexact
/// вместо обещания точности), что снимает отмена по диапазону и что делает
/// сервис, когда платформа планировать не умеет (F-57).
///
/// База таймзон и локальная зона проверяются отдельным файлом
/// (`notification_service_timezone_test.dart`): база `timezone` — состояние
/// процесса, и «забыли поднять» можно поймать только в изолированном изоляте.
library;

import 'package:dharma_toolkit/features/events/domain/notification_plan.dart';
import 'package:dharma_toolkit/features/events/platform/notification_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

import 'platform_fakes.dart';

void main() {
  late FakeNotificationGateway gateway;
  late FakeLocalTimeZoneSource timeZone;
  late RecordingScheduleDegradation degradation;
  late List<String> warnings;

  NotificationService serviceWith() => NotificationService(
        gateway: gateway,
        timeZoneSource: timeZone,
        degradation: degradation,
        warn: warnings.add,
      );

  /// Сервис, прошедший инициализацию: только после неё есть локальная зона,
  /// в которой строится `TZDateTime` (F-56).
  Future<NotificationService> readyService() async {
    final service = serviceWith();
    await service.initialize();
    return service;
  }

  setUp(() {
    gateway = FakeNotificationGateway();
    timeZone = FakeLocalTimeZoneSource('Europe/Moscow');
    degradation = RecordingScheduleDegradation();
    warnings = [];
  });

  NotificationPlanItem item({
    int id = NotificationPlan.idRangeStart,
    DateTime? at,
    String title = 'Особый день',
    String body = 'Описание',
    String payload = '{"source":"calendar"}',
  }) =>
      NotificationPlanItem(
        id: id,
        scheduledAt: at ?? DateTime(2026, 6, 2, 8),
        title: title,
        body: body,
        payload: payload,
      );

  group('initialize — настройки платформ', () {
    test('инициализирует плагин настройками Android/iOS/macOS/Linux', () async {
      await serviceWith().initialize();

      expect(gateway.initializeCalled, isTrue);
      final settings = gateway.settings!;
      expect(settings.android?.defaultIcon, '@mipmap/ic_launcher');
      expect(settings.iOS, isNotNull);
      expect(settings.macOS, isNotNull);
      expect(settings.linux?.defaultActionName, 'Открыть');
    });

    test('спрашивает IANA-имя зоны у платформы ровно один раз', () async {
      await serviceWith().initialize();

      expect(timeZone.calls, 1);
    });
  });

  group('show — немедленный показ', () {
    test('передаёт id, заголовок, текст и payload', () async {
      await serviceWith().show(item(id: 100007, title: 'Лосар', body: 'Новый год',
          payload: '{"packId":"p1"}'));

      expect(gateway.shown.single.id, 100007);
      expect(gateway.shown.single.title, 'Лосар');
      expect(gateway.shown.single.body, 'Новый год');
      expect(gateway.shown.single.payload, '{"packId":"p1"}');
    });
  });

  group('schedule — точность и таймзона (D-36/F-57)', () {
    test('точное планирование недоступно → inexact, а не обещание точности',
        () async {
      gateway.exactAllowed = false;

      await (await readyService()).schedule(item());

      expect(gateway.scheduled.single.mode, AndroidScheduleMode.inexact);
    });

    test('точное планирование доступно → exact', () async {
      gateway.exactAllowed = true;

      await (await readyService()).schedule(item());

      expect(gateway.scheduled.single.mode, AndroidScheduleMode.exact);
    });

    test('момент уходит в локальной зоне устройства с тем же временем', () async {
      await (await readyService()).schedule(item(at: DateTime(2026, 6, 2, 8, 30)));

      final date = gateway.scheduled.single.scheduledDate;
      expect(date.hour, 8);
      expect(date.minute, 30);
      expect(date.location.name, tz.local.name);
    });

    test('платформа без планировщика (Linux) → деградация, не исключение',
        () async {
      gateway.zonedScheduleError =
          UnimplementedError('zonedSchedule() has not been implemented');

      await (await readyService()).schedule(item(id: 100042));

      expect(gateway.scheduled, isEmpty);
      expect(degradation.unsupported.single.id, 100042);
      expect(degradation.errors.single, isA<UnimplementedError>());
    });
  });

  group('отмена и ожидающие (полоса id приложения)', () {
    test('cancelRange снимает только id своей полосы, чужие не трогает',
        () async {
      gateway.pending.addAll([7, NotificationPlan.idRangeStart, 100001,
          NotificationPlan.idRangeEnd, 500000]);

      await serviceWith().cancelRange(
        fromId: NotificationPlan.idRangeStart,
        toId: NotificationPlan.idRangeEnd,
      );

      expect(gateway.cancelled, [100000, 100001, 199999]);
    });

    test('cancelRange с перевёрнутым диапазоном — ошибка аргумента', () async {
      expect(
        () => serviceWith().cancelRange(fromId: 200000, toId: 100000),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('pendingIds: платформа без перечисления отдаёт пустой список и лог',
        () async {
      gateway.pendingIdsError =
          UnimplementedError('pendingNotificationRequests not implemented');

      final ids = await serviceWith().pendingIds();

      expect(ids, isEmpty);
      expect(warnings.single, contains('F-57'));
    });

    test('cancel(одиночный) делегируется платформе', () async {
      await serviceWith().cancel(100005);

      expect(gateway.cancelled, [100005]);
    });
  });
}
