import 'package:flutter/material.dart';

import 'core/config/config_module.dart';
import 'core/db/database_module.dart';
import 'core/module/module_registry.dart';
import 'core/storage/storage_module.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final registry = ModuleRegistry.instance;
  registry.register(DatabaseModule());
  registry.register(StorageModule());
  registry.register(ConfigModule());

  await registry.initAll();

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
