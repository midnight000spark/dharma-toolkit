import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_router.dart';
import 'core/config/config_module.dart';
import 'core/config/preset_manager.dart';
import 'core/db/database_module.dart';
import 'core/db/dev_seeder.dart';
import 'core/module/module_registry.dart';
import 'core/storage/storage_module.dart';
import 'shared/providers/app_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final registry = ModuleRegistry.instance;
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

  await registry.initAll();

  // Dev-посев: вместо хардкода практик — применение реального пресета
  // через реальный путь (B-3/3.4). Только debug, только если традиция ещё
  // не выбрана.
  if (kDebugMode) {
    await DevSeeder.seedIfEmpty(
      presets: presetManager,
      config: configModule,
    );
  }

  runApp(
    ProviderScope(
      overrides: [
        configModuleProvider.overrideWithValue(configModule),
        presetManagerProvider.overrideWithValue(presetManager),
      ],
      child: const DharmaToolkitApp(),
    ),
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
