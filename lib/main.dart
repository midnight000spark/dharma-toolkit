import 'package:flutter/material.dart';

import 'core/config/config_module.dart';
import 'core/config/preset_manager.dart';
import 'core/db/database_module.dart';
import 'core/module/module_registry.dart';
import 'core/storage/storage_module.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final registry = ModuleRegistry.instance;
  final databaseModule = DatabaseModule();
  final storageModule = StorageModule();
  final configModule = ConfigModule();

  registry.register(databaseModule);
  registry.register(storageModule);
  registry.register(configModule);

  await registry.initAll();

  // PresetManager depends on DatabaseModule and StorageModule
  final presetManager = PresetManager(
    databaseModule.database,
    storageModule,
  );
  registry.register(presetManager);
  await presetManager.init();

  runApp(const DharmaToolkitApp());
}

class DharmaToolkitApp extends StatelessWidget {
  const DharmaToolkitApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Дхарма-тулкит',
      home: const Scaffold(
        body: Center(
          child: Text('Дхарма-тулкит запущен'),
        ),
      ),
    );
  }
}
