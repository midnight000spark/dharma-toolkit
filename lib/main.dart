import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/config_module.dart';
import 'core/config/preset_manager.dart';
import 'core/db/database_module.dart';
import 'core/db/dev_seeder.dart';
import 'core/module/module_registry.dart';
import 'core/storage/storage_module.dart';
import 'features/tracker/presentation/router.dart';

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

  // Seed test data in debug mode
  if (kDebugMode) {
    await DevSeeder.seedIfEmpty(databaseModule.database);
  }

  runApp(const ProviderScope(child: DharmaToolkitApp()));
}

class DharmaToolkitApp extends ConsumerWidget {
  const DharmaToolkitApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Дхарма-тулкит',
      routerConfig: trackerRouter,
    );
  }
}
