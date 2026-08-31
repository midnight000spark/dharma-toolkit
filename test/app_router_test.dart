import 'package:dharma_toolkit/app_router.dart';
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
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// B-7: некорректные маршруты не роняют приложение.
/// Харнесс минимальный: in-memory пресет применяется напрямую (ConfigModule
/// и ассеты здесь не проверяются — они покрыты тестами /pick и 5.0.2).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late StorageModule storage;

  final nyingma = PresetSchema(
    id: 'nyingma',
    name: 'Ньингма',
    version: '1.0.0',
    modules: ['tracker'],
    tradition: 'vajrayana',
    moduleConfigs: const {},
    practices: [
      PresetPractice(
          id: 'prostrations', name: 'Простирания', type: 'counter',
          target: 100000, unit: 'повторений'),
    ],
    eventPacks: const [],
    contentPacks: const [],
  );

  Future<GoRouter> pumpApp(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    database = AppDatabase.forTesting(
      NativeDatabase.memory(setup: enableForeignKeys),
    );
    storage = StorageModule();
    await storage.init();
    final presetManager = PresetManager(() => database, storage);
    await presetManager.init();
    await presetManager.applyPreset(nyingma);

    late GoRouter built;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          presetManagerProvider.overrideWithValue(presetManager),
          practiceRepositoryProvider
              .overrideWithValue(PracticeRepository(database)),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            built = ref.watch(routerProvider);
            return MaterialApp.router(routerConfig: built);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return built;
  }

  /// Гасим дерево до закрытия БД: сначала отмена подписок drift, затем нулевые
  /// таймеры StreamQueryStore (иначе «Timer is still pending» / ошибки
  /// закрытой БД в канале тест-раннера).
  Future<void> settleDown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await database.close();
  }

  tearDown(() async {
    try {
      await storage.dispose();
    } catch (_) {}
  });

  testWidgets('нечисловой id /practice/abc → список, без падения (B-7)',
      (tester) async {
    final router = await pumpApp(tester);

    expect(find.text('Практики'), findsOneWidget);

    router.go('/practice/abc');
    await tester.pumpAndSettle();

    // Не FormatException/чёрный экран, а редирект на список практик.
    expect(tester.takeException(), isNull);
    expect(find.text('Практики'), findsOneWidget);
    expect(find.text('Простирания'), findsOneWidget);

    await settleDown(tester);
  });

  testWidgets('несуществующий маршрут → error-экран с кнопкой «Назад» (B-7)',
      (tester) async {
    final router = await pumpApp(tester);

    router.go('/no-such-page');
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Страница не найдена'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Назад'), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Назад'));
    await tester.pumpAndSettle();

    expect(find.text('Практики'), findsOneWidget);

    await settleDown(tester);
  });
}
