/// Публикация `PresetChanged` менеджером пресетов (D-21/D-36, пакет 6.2).
///
/// Событие — триггер перепланирования напоминаний, поэтому проверяется путь
/// «применили пресет → событие ушло в шину с верным тегом», включая сброс
/// (пустой тег = напоминаний не будет). Без шины менеджер обязан работать как
/// раньше: событие — не условие применения пресета.
library;

import 'package:dharma_toolkit/core/config/preset_manager.dart';
import 'package:dharma_toolkit/core/config/preset_schema.dart';
import 'package:dharma_toolkit/core/db/app_database.dart';
import 'package:dharma_toolkit/core/events/event_bus.dart';
import 'package:dharma_toolkit/core/events/preset_events.dart';
import 'package:dharma_toolkit/core/storage/storage_module.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late StorageModule storage;
  late EventBus bus;
  late List<PresetChanged> events;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    storage = StorageModule();
    await storage.init();
    bus = EventBus();
    events = [];
    bus.on<PresetChanged>().listen(events.add);
  });

  tearDown(() async {
    await storage.dispose();
    await db.close();
    bus.dispose();
  });

  PresetSchema preset(String id) => PresetSchema(
        id: id,
        name: id,
        version: '1.0.0',
        modules: const ['calendar'],
        tradition: 'vajrayana',
        practices: const [],
        eventPacks: const [],
        contentPacks: const [],
      );

  test('applyPreset публикует событие с тегом традиции', () async {
    final manager = PresetManager(() => db, storage, eventBus: bus);

    await manager.applyPreset(preset('nyingma'));
    await pumpEventQueue();

    expect(events.single.traditionTag, 'nyingma');
  });

  test('смена пресета публикует событие с новым тегом', () async {
    final manager = PresetManager(() => db, storage, eventBus: bus);

    await manager.applyPreset(preset('nyingma'));
    await manager.switchPreset(preset('theravada_default'));
    await pumpEventQueue();

    expect(events.map((e) => e.traditionTag),
        ['nyingma', 'theravada_default']);
  });

  test('resetPreset публикует пустой тег — активной традиции нет', () async {
    final manager = PresetManager(() => db, storage, eventBus: bus);

    await manager.applyPreset(preset('nyingma'));
    await manager.resetPreset();
    await pumpEventQueue();

    expect(events.last.traditionTag, isEmpty);
  });

  test('без шины применение пресета работает и не публикует ничего', () async {
    final manager = PresetManager(() => db, storage);

    await manager.applyPreset(preset('nyingma'));
    await pumpEventQueue();

    expect(manager.activePreset?.id, 'nyingma');
    expect(events, isEmpty);
  });
}
