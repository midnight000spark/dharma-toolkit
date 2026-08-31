import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_router.dart';
import 'core/config/config_module.dart';
import 'core/config/preset_manager.dart';
import 'core/db/app_database.dart';
import 'core/db/database_module.dart';
import 'core/db/dev_seeder.dart';
import 'core/module/module_registry.dart';
import 'core/recovery/recovery_screen.dart';
import 'core/recovery/startup.dart';
import 'core/storage/storage_module.dart';
import 'shared/providers/app_providers.dart';

/// Готовые сервисы, без которых не собрать ProviderScope.
class AppServices {
  final ConfigModule config;
  final PresetManager presetManager;

  /// Единственный экземпляр БД в приложении (D-22): создан [DatabaseModule]
  /// при инициализации; уходит в `appDatabaseProvider.overrideWithValue`.
  final AppDatabase database;

  const AppServices({
    required this.config,
    required this.presetManager,
    required this.database,
  });
}

/// Точка входа (B-5).
///
/// Порядок инициализации — контракт (6.6):
///   1. binding → 2. глобальные обработчики ошибок → 3. модули реестра
///      (database → storage → config → preset_manager, см. [bootstrapServices])
///   → 4. посев (только debug, некритично) → 5. runApp.
/// Сбой инициализации НЕ валит процесс в чёрный экран: критичные модули
/// уводят на [RecoveryApp], некритичные деградируют с логом (5.4).
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 5.3: красный экран фреймворка — не интерфейс пользователя.
  ErrorWidget.builder = humanErrorWidget;
  // Ошибки фреймворка логируются, не убивая процесс; зона (runZonedGuarded)
  // перехватывает асинхронные отказы.
  FlutterError.onError = FlutterError.presentError;

  var rootMounted = false;
  void mount(Widget root) {
    rootMounted = true;
    runApp(root);
  }

  /// Полный цикл старта; повтор вызывается и кнопкой «Попробовать снова»,
  /// и после аварийного стирания (screen сам затирает до [onReset]).
  Future<void> start() async {
    final (services, outcome) = await bootstrapServices();
    if (!outcome.ok || services == null) {
      mount(RecoveryApp(
        error: outcome.fatalFailures.isNotEmpty
            ? outcome.fatalFailures.first.error
            : StateError('Инициализация не завершена'),
        onRetry: start,
        onReset: start,
      ));
      return;
    }
    mount(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(services.database),
          configModuleProvider.overrideWithValue(services.config),
          presetManagerProvider.overrideWithValue(services.presetManager),
        ],
        child: const DharmaToolkitApp(),
      ),
    );
  }

  runZonedGuarded<void>(
    () async {
      await start();
    },
    (error, stack) {
      debugPrint('Необработанная ошибка: $error\n$stack');
      // До монтирования корня асинхронный отказ = всё ещё чёрный экран:
      // показываем восстановление. После монтирования — только лог
      // (один сбойный виджет не должен уносить приложение).
      if (!rootMounted) {
        mount(RecoveryApp(error: error, onRetry: start, onReset: start));
      }
    },
  );
}

/// Регистрирует и инициализирует модули приложения.
///
/// Порядок регистрации = порядок инициализации (контракт 6.6):
///   database (ленивое соединение, disk-free на старте) →
///   storage (нужен preset_manager для чтения активного id) →
///   config (загрузка пресетов) → preset_manager (читает БД+storage).
/// Повторный вызов (retry с экрана восстановления) сначала корректно
/// диспопит прошлую попытку — disposeAll гарантирует очистку (6.2).
///
/// Возвращает сервисы (null при фатальном отказе) и вердикт старта.
Future<(AppServices?, StartupOutcome)> bootstrapServices() async {
  final registry = ModuleRegistry.instance;
  if (registry.all.isNotEmpty) {
    await registry.disposeAll();
  }

  final databaseModule = DatabaseModule();
  final storageModule = StorageModule();
  final configModule = ConfigModule();
  // PresetManager uses lazy access to database via callback
  final presetManager = PresetManager(
    () => databaseModule.database,
    storageModule,
  );

  registry.register(databaseModule);
  registry.register(storageModule);
  registry.register(configModule);
  registry.register(presetManager);

  final outcome = await bootstrapModules(registry);
  if (!outcome.ok) {
    return (null, outcome);
  }

  // Dev-посев: вместо хардкода практик — применение реального пресета
  // через реальный путь (B-3/3.4). Только debug и только если традиция ещё
  // не выбрана; отказ seeding — деградация, не катастрофа (5.4).
  if (kDebugMode) {
    try {
      await DevSeeder.seedIfEmpty(
        presets: presetManager,
        config: configModule,
      );
    } catch (error) {
      debugPrint('Dev-посев пропущен: $error');
    }
  }

  return (
    AppServices(
      config: configModule,
      presetManager: presetManager,
      database: databaseModule.database,
    ),
    outcome,
  );
}

class DharmaToolkitApp extends ConsumerWidget {
  const DharmaToolkitApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Дхарма-тулкит',
      routerConfig: ref.watch(routerProvider),
    );
  }
}
