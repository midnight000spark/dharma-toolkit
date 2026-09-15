/// Публикация `NotificationSettingsChanged` хранилищем настроек
/// (D-21/D-36, пакет 6.2).
///
/// Запись настроек — второй триггер перепланирования: без события смена
/// «включено/время» не добралась бы до планировщика (поток настроек
/// обслуживает UI, а не перепланировщик).
library;

import 'package:dharma_toolkit/core/db/app_database.dart';
import 'package:dharma_toolkit/core/events/event_bus.dart';
import 'package:dharma_toolkit/core/events/notification_events.dart';
import 'package:dharma_toolkit/features/events/data/notification_settings_store.dart';
import 'package:dharma_toolkit/features/events/domain/notification_settings.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late EventBus bus;
  late List<NotificationSettingsChanged> events;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    bus = EventBus();
    events = [];
    bus.on<NotificationSettingsChanged>().listen(events.add);
  });

  tearDown(() async {
    await db.close();
    bus.dispose();
  });

  test('write публикует событие с тегом традиции', () async {
    final store = NotificationSettingsStore(db, eventBus: bus);

    await store.write('nyingma',
        NotificationSettings(enabled: false, hour: 6, minute: 30));
    await pumpEventQueue();

    expect(events.single.traditionTag, 'nyingma');
  });

  test('reset публикует событие — настройки вернулись к дефолту', () async {
    final store = NotificationSettingsStore(db, eventBus: bus);

    await store.reset('nyingma');
    await pumpEventQueue();

    expect(events.single.traditionTag, 'nyingma');
  });

  test('без шины запись работает и ничего не публикует', () async {
    final store = NotificationSettingsStore(db);

    await store.write('nyingma', NotificationSettings.defaults);
    await pumpEventQueue();

    expect(await store.read('nyingma'), NotificationSettings.defaults);
    expect(events, isEmpty);
  });

  test('невалидный тег не публикует событие (ошибка до записи)', () async {
    final store = NotificationSettingsStore(db, eventBus: bus);

    await expectLater(
      store.write('   ', NotificationSettings.defaults),
      throwsA(isA<ArgumentError>()),
    );
    await pumpEventQueue();

    expect(events, isEmpty);
  });
}
