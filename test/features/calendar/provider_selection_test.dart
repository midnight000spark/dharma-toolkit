/// Реактивный выбор календаря по активному пресету (5b.4, R-21/D-32).
///
/// Поведенческие тесты пути переключения (урок 4): провайдер обязан сменить
/// реализацию на `applyPreset`/`switchPreset`/`resetPreset` БЕЗ перезапуска
/// контейнера. Тесты краснеют, если:
///  * проводка вернётся на чтение plain-поля `activePreset` (R-21 —
///    мина Этапа 8: смена традиции из настроек не дойдёт до UI);
///  * реестр тег→реализация перепутает местами или начнёт угадывать школу
///    по литералу вне реестра (принцип №3, R-20).
///
/// Детерминизм — уровень репозитория/контейнера, без виджетов (урок 5).
library;

import 'package:dharma_toolkit/core/config/preset_manager.dart';
import 'package:dharma_toolkit/core/config/preset_schema.dart';
import 'package:dharma_toolkit/core/db/app_database.dart';
import 'package:dharma_toolkit/core/storage/storage_module.dart';
import 'package:dharma_toolkit/features/calendar/data/tibetan/tibetan_calendar_provider.dart';
import 'package:dharma_toolkit/features/calendar/data/uposatha/uposatha_calendar_provider.dart';
import 'package:dharma_toolkit/features/calendar/presentation/providers/calendar_providers.dart';
import 'package:dharma_toolkit/shared/providers/app_providers.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

PresetSchema _preset({
  required String id,
  required String tradition,
  List<PresetPractice> practices = const [],
}) =>
    PresetSchema(
      id: id,
      name: id,
      version: '1.0.0',
      modules: const ['calendar', 'tracker'],
      tradition: tradition,
      practices: practices,
      eventPacks: const [],
      contentPacks: const [],
    );

final _nyingma = _preset(id: 'nyingma', tradition: 'vajrayana');
final _theravada = _preset(id: 'theravada_default', tradition: 'theravada');
final _custom = _preset(id: 'my_custom_set', tradition: 'vajrayana');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late StorageModule storage;
  late PresetManager manager;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    database = AppDatabase.forTesting(
      NativeDatabase.memory(setup: enableForeignKeys),
    );
    storage = StorageModule();
    await storage.init();
    manager = PresetManager(() => database, storage);
    await manager.init();
    container = ProviderContainer(
      overrides: [presetManagerProvider.overrideWithValue(manager)],
    );
    // Держим подписку, чтобы потоковые провайдеры жили между read-вызовами.
    container.listen(activeTraditionTagProvider, (_, _) {});
  });

  tearDown(() async {
    container.dispose();
    await database.close();
    try {
      await storage.dispose();
    } catch (_) {}
  });

  /// Ждём, пока реактивная проводка донесёт тег до провайдера.
  /// Цикл с yields вместо таймеров: детерминированно и без magic-waits.
  Future<void> settleTag(String expected) async {
    for (var i = 0; i < 50; i++) {
      if (container.read(activeTraditionTagProvider).value == expected) return;
      await Future<void>.delayed(Duration.zero);
    }
    fail('тег так и не стал "$expected" '
        '(сейчас: ${container.read(activeTraditionTagProvider).value})');
  }

  test('применение Ньингма → тег nyingma, календарь тибетский', () async {
    await manager.applyPreset(_nyingma);
    await settleTag('nyingma');

    expect(container.read(activeTraditionTagProvider).value, 'nyingma');
    final cal = container.read(activeCalendarProviderProvider);
    expect(cal, isA<TibetanCalendarProvider>(),
        reason: 'Ваджраяна-пресет должен получить тибетский календарь');
    expect(cal!.traditionTag, 'nyingma',
        reason: 'тег изоляции — id активного пресета (принцип №3/B-4)');
  });

  test('переключение на Тхераваду в живом контейнере → упосатхи (R-21)',
      () async {
    await manager.applyPreset(_nyingma);
    await settleTag('nyingma');
    expect(container.read(activeCalendarProviderProvider),
        isA<TibetanCalendarProvider>());

    await manager.switchPreset(_theravada);
    await settleTag('theravada_default');

    final cal = container.read(activeCalendarProviderProvider);
    expect(cal, isA<UposathaCalendarProvider>(),
        reason: 'смена пресета без перезапуска обязана сменить и календарь');
    expect(cal!.traditionTag, 'theravada_default');
  });

  test('reset → тега и календаря нет, падению неоткуда взяться', () async {
    await manager.applyPreset(_nyingma);
    await settleTag('nyingma');

    await manager.resetPreset();
    await settleTag('');

    expect(container.read(activeCalendarProviderProvider), isNull,
        reason: 'сброшенный пресет — деградация null, не исключение');
  });

  test('незарегистрированный тег → честная деградация (null), не чужой календарь',
      () async {
    await manager.applyPreset(_custom);
    await settleTag('my_custom_set');

    final cal = container.read(activeCalendarProviderProvider);
    expect(cal, isNull,
        reason: 'неизвестный тег не должен молча получать чужую реализацию');
    // Тег при этом живёт и изолирует данные — выбор календаря на него не влияет.
    expect(container.read(activeTraditionTagProvider).value, 'my_custom_set');
  });

  test('стабильность инстанса: повторный выбор по тому же тегу — тот же объект',
      () async {
    await manager.applyPreset(_nyingma);
    await settleTag('nyingma');
    expect(container.read(activeCalendarProviderProvider),
        same(container.read(activeCalendarProviderProvider)),
        reason: 'family-провайдер стабилен по ключу (D-22, без new-ов в UI)');
  });
}
