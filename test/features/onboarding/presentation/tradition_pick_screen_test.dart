import 'dart:async';

import 'package:dharma_toolkit/app_router.dart';
import 'package:dharma_toolkit/core/config/config_module.dart';
import 'package:dharma_toolkit/core/config/preset_manager.dart';
import 'package:dharma_toolkit/core/config/preset_schema.dart';
import 'package:dharma_toolkit/core/db/app_database.dart';
import 'package:dharma_toolkit/core/storage/storage_module.dart';
import 'package:dharma_toolkit/features/tracker/data/practice_repository.dart';
import 'package:dharma_toolkit/features/tracker/presentation/providers/practice_provider.dart';
import 'package:dharma_toolkit/shared/providers/app_providers.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Поведенческий тест (урок 2): на `/pick` тап по «Ньингма» → в списке
/// практики из пресета. Тест идёт через тот же путь, что и пользователь:
/// GoRouter → applyPreset → материализация в БД → список.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ConfigModule читает ассеты через rootBundle — это реальный ввод-вывод.
  // Внутри тела testWidgets он живёт в fake-async зоне: первый `config.init()`
  // в файле проходит, повторный (во втором тесте) виснет без выхода —
  // обнаружено при добавлении теста R-22. Поэтому ассеты грузятся один раз в
  // setUpAll (обычная зона), а тесты делят read-only экземпляр конфига.
  late ConfigModule config;

  setUpAll(() async {
    config = ConfigModule();
    await config.init();
  });

  testWidgets('тап по Ньингма на /pick создаёт четыре практики в списке',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final database = AppDatabase.forTesting(
      NativeDatabase.memory(setup: enableForeignKeys),
    );
    final storage = StorageModule();
    await storage.init();
    final presetManager = PresetManager(() => database, storage);
    await presetManager.init();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          configModuleProvider.overrideWithValue(config),
          presetManagerProvider.overrideWithValue(presetManager),
          // Репозиторий собирается поверх appDatabaseProvider (D-22);
          // в тесте подменяем провайдер на тот же in-memory экземпляр —
          // путь данных не меняется.
          practiceRepositoryProvider
              .overrideWithValue(PracticeRepository(database)),
        ],
        child: Consumer(
          builder: (context, ref, _) => MaterialApp.router(
            routerConfig: ref.watch(routerProvider),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Активного пресета нет — редирект на экран выбора, «Ньингма» видна.
    expect(find.text('Выберите традицию'), findsOneWidget);
    expect(find.text('Ньингма'), findsOneWidget);
    // Недоступные пресеты (kagyu, zen_soto, bon_default…) помечены «скоро»
    // и некликабельны — не фейкаем Этап 8.
    expect(find.textContaining('Скоро'), findsWidgets);

    await tester.tap(find.text('Ньингма'));
    await tester.pumpAndSettle();

    // applied: список показывает четыре практики нёндро.
    expect(find.text('Простирания'), findsOneWidget);
    expect(find.text('Мантра Ваджрасаттвы'), findsOneWidget);
    expect(find.text('Подношение мандал'), findsOneWidget);
    expect(find.text('Гуру-йога'), findsOneWidget);

    // Данные действительно в БД, а не только в виджете.
    final stored = await (database.select(database.practices)).get();
    expect(stored, hasLength(4));
    expect(stored.every((p) => p.traditionTag == 'nyingma'), isTrue);

    await storage.dispose();
    await database.close();
  });

  // R-22: тап-спам по карточке пресета запускал несколько конкурентных
  // applyPreset: select не видел незакоммиченную строку, второй insert падал
  // ConstraintException, а исключение из async onTap молча проглатывалось
  // зоной. Транзакция в PresetManager закрывает целостность БД
  // (preset_materialization_test), этот тест — про гард повторного тапа.
  testWidgets('R-22: второй тап по карточке во время применения игнорируется',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final database = AppDatabase.forTesting(
      NativeDatabase.memory(setup: enableForeignKeys),
    );
    final storage = StorageModule();
    await storage.init();
    // Двойник с воротами: применение «висит», пока тест его не разрешит
    // (паттерн B-9, урок 5 — детерминированная имитация полёта).
    final presetManager = _GatedPresetManager(() => database, storage)
      ..gate = Completer<void>();
    await presetManager.init();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          configModuleProvider.overrideWithValue(config),
          presetManagerProvider.overrideWithValue(presetManager),
          practiceRepositoryProvider
              .overrideWithValue(PracticeRepository(database)),
        ],
        child: Consumer(
          builder: (context, ref, _) => MaterialApp.router(
            routerConfig: ref.watch(routerProvider),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Выберите традицию'), findsOneWidget);

    await tester.tap(find.text('Ньингма'));
    await tester.pump(); // тап обработан: применение в полёте

    // Второй тап, пока применение не завершилось.
    await tester.tap(find.text('Ньингма'));
    await tester.pump();
    expect(presetManager.applyCalls, 1,
        reason: 'R-22: повторный тап не запускает второе применение');

    presetManager.gate!.complete();
    await tester.pumpAndSettle();

    // Материализация прошла ровно один раз, навигация ушла на главную.
    final stored = await (database.select(database.practices)).get();
    expect(stored, hasLength(4));
    expect(find.text('Простирания'), findsWidgets);

    await storage.dispose();
    await database.close();
  });
}

/// Двойник менеджера: [applyPreset] встаёт на [gate], пока тест его не
/// разрешит, и считает вызовы.
class _GatedPresetManager extends PresetManager {
  _GatedPresetManager(super.databaseGetter, super.storage);

  Completer<void>? gate;
  int applyCalls = 0;

  @override
  Future<void> applyPreset(PresetSchema preset) async {
    applyCalls++;
    final g = gate;
    if (g != null) await g.future;
    return super.applyPreset(preset);
  }
}
