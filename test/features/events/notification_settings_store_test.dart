/// Хранилище настроек уведомлений: дефолт, upsert, изоляция по тегу и границы
/// домена (FR-EVT-3, D-36; миграция схемы v4 — блок D пакета 6.1).
///
/// Проверяется путь сохранения, а не факт наличия класса: настройки переживают
/// повторное чтение, традиции не влияют друг на друга, а испорченное значение
/// (час вне диапазона) всплывает ошибкой, а не «тихо исправляется».
library;

import 'package:dharma_toolkit/core/db/app_database.dart';
import 'package:dharma_toolkit/features/events/data/notification_settings_store.dart';
import 'package:dharma_toolkit/features/events/domain/notification_settings.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late NotificationSettingsStore store;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    store = NotificationSettingsStore(db);
  });

  tearDown(() => db.close());

  group('NotificationSettings — домен', () {
    test('дефолт D-36: включено, 08:00', () {
      expect(NotificationSettings.defaults.enabled, isTrue);
      expect(NotificationSettings.defaults.hour, 8);
      expect(NotificationSettings.defaults.minute, 0);
    });

    test('отрицательное время и час 24 — ошибка с именем поля (R-23)', () {
      expect(
        () => NotificationSettings(enabled: true, hour: -1, minute: 0),
        throwsA(isA<InvalidNotificationSettingsException>()
            .having((e) => e.field, 'field', 'hour')),
      );
      expect(
        () => NotificationSettings(enabled: true, hour: 24, minute: 0),
        throwsA(isA<InvalidNotificationSettingsException>()),
      );
      expect(
        () => NotificationSettings(enabled: true, hour: 8, minute: 60),
        throwsA(isA<InvalidNotificationSettingsException>()
            .having((e) => e.field, 'field', 'minute')),
      );
    });

    test('copyWith сохраняет остальные поля', () {
      final s = NotificationSettings.defaults
          .copyWith(enabled: false, minute: 30);
      expect(s.enabled, isFalse);
      expect(s.hour, 8);
      expect(s.minute, 30);
    });
  });

  group('NotificationSettingsStore', () {
    test('строки нет → дефолт D-36, не ошибка', () async {
      expect(await store.read('nyingma'), NotificationSettings.defaults);
    });

    test('запись переживает повторное чтение (путь сохранения)', () async {
      final settings =
          NotificationSettings(enabled: false, hour: 6, minute: 45);
      await store.write('nyingma', settings);

      // Новый экземпляр стора — как после перезапуска приложения.
      final fresh = NotificationSettingsStore(db);
      expect(await fresh.read('nyingma'), settings);
    });

    test('повторная запись обновляет строку, а не плодит дубли', () async {
      await store.write('nyingma', NotificationSettings.defaults);
      await store
          .write('nyingma', NotificationSettings.defaults.copyWith(hour: 5));

      final rows = await db.select(db.notificationSettingsRows).get();
      expect(rows, hasLength(1));
      expect(await store.read('nyingma'), NotificationSettings.defaults
          .copyWith(hour: 5));
    });

    test('изоляция по тегу: настройки традиций независимы', () async {
      await store.write('nyingma',
          NotificationSettings(enabled: true, hour: 5, minute: 0));
      await store.write('theravada_default',
          NotificationSettings(enabled: false, hour: 21, minute: 15));

      expect((await store.read('nyingma')).hour, 5);
      expect((await store.read('theravada_default')).enabled, isFalse);
      expect((await store.read('theravada_default')).minute, 15);
    });

    test('пустой тег традиции — ошибка, а не строка-фантом', () async {
      expect(
        () => store.write('  ', NotificationSettings.defaults),
        throwsArgumentError,
      );
    });

    test('reset возвращает дефолт', () async {
      await store.write('nyingma',
          NotificationSettings(enabled: false, hour: 5, minute: 5));
      await store.reset('nyingma');
      expect(await store.read('nyingma'), NotificationSettings.defaults);
    });

    test('испорченное значение в БД всплывает ошибкой, не клампингом '
        '(R-23)', () async {
      // Прямая запись в обход домена: так выглядела бы строка, испорченная
      // другой версией приложения или ручной правкой файла БД.
      await db.customStatement(
        "INSERT INTO notification_settings "
        "(tradition_tag, enabled, hour, minute) VALUES ('nyingma', 1, 99, 0)",
      );

      await expectLater(
        store.read('nyingma'),
        throwsA(isA<InvalidNotificationSettingsException>()
            .having((e) => e.field, 'field', 'hour')
            .having((e) => e.reason, 'reason', contains('nyingma'))),
      );
    });

    test('watch отдаёт дефолт до записи и новое значение после', () async {
      final events = <NotificationSettings>[];
      final sub = store.watch('nyingma').listen(events.add);
      addTearDown(sub.cancel);

      await pumpEventQueue();
      await store.write('nyingma',
          NotificationSettings(enabled: true, hour: 4, minute: 0));
      await pumpEventQueue();

      expect(events.first, NotificationSettings.defaults);
      expect(events.last.hour, 4);
    });
  });
}
