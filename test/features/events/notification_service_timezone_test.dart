/// Инициализация таймзон устройства (F-56, блок A пакета 6.2).
///
/// **Почему отдельным файлом.** База `timezone` — состояние процесса: однажды
/// поднятая `initializeTimeZones()`, она остаётся поднятой до конца изолята.
/// Если бы этот тест жил рядом с остальными тестами сервиса, мутация «убрать
/// `initializeTimeZones()`» не покраснела бы — базу успел бы поднять соседний
/// тест (урок 1: тест, который не может упасть, не доказывает ничего).
/// Отдельный файл — отдельный изолят, поэтому проверка честная.
///
/// TZDateTime в UTC-дефолте — не мелочь: `timezone` без `setLocalLocation`
/// считает локалью UTC, и «08:00» из D-36 превратилось бы в 08:00 UTC —
/// враньё о времени практикующего (мотивация D-34).
library;

import 'package:dharma_toolkit/features/events/platform/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

import 'platform_fakes.dart';

void main() {
  test('initialize() поднимает базу таймзон и ставит локальную зону', () async {
    final gateway = FakeNotificationGateway();
    final service = NotificationService(
      gateway: gateway,
      timeZoneSource: FakeLocalTimeZoneSource('Europe/Moscow'),
    );

    await service.initialize();

    // База поднята: до initializeTimeZones() этот вызов бросает
    // LocationNotFoundException.
    expect(() => tz.getLocation('Europe/Moscow'), returnsNormally);
    // Локальная зона — зона устройства, а не UTC-дефолт пакета.
    expect(tz.local.name, 'Europe/Moscow');
    expect(gateway.initializeCalled, isTrue);
  });

  test('зона, которой нет в базе, — громкая ошибка, а не работа в UTC', () async {
    final service = NotificationService(
      gateway: FakeNotificationGateway(),
      timeZoneSource: FakeLocalTimeZoneSource('Mars/Olympus'),
    );

    await expectLater(service.initialize(), throwsA(isA<Exception>()));
  });
}
