import 'dart:io';

import 'package:dharma_toolkit/core/db/app_database.dart'
    show kAppDatabaseFileName;
import 'package:dharma_toolkit/core/db/database_module.dart';
import 'package:dharma_toolkit/core/module/app_module.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DatabaseModule', () {
    test('implements AppModule', () {
      final module = DatabaseModule();
      expect(module, isA<AppModule>());
    });

    test('has correct id, name, version', () {
      final module = DatabaseModule();

      expect(module.id, 'database');
      expect(module.name, 'База данных');
      expect(module.version, '1.0.0');
    });

    test('throws StateError when accessing database before init', () {
      final module = DatabaseModule();

      expect(() => module.database, throwsA(isA<StateError>()));
    });

    test('init проходит активный зонд на настоящем файле (C1(2))', () async {
      final dir = await Directory.systemTemp.createTemp('dharma_dbmodule_');
      addTearDown(() => dir.delete(recursive: true));
      final path = dir.path;
      mockDocumentsDirectory(path);

      final module = DatabaseModule();
      await module.init();

      // Поведенчески: после init соединение УЖЕ открыто и схема создана — а не
      // «откроется когда-нибудь при первом запросе» (было сутью C1(2)).
      // Файл базы существует СРАЗУ после init, до любого прикладного запроса:
      // именно это и значит «модуль database может упасть» (C1(2)). Без
      // активного зонда файл появился бы только на первом обращении.
      expect(File('$path/$kAppDatabaseFileName').existsSync(), isTrue,
          reason: 'init обязан открывать файл, а не откладывать открытие');
      final version = await module.database
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(version.read<int>('user_version'), module.database.schemaVersion);

      await module.dispose();
    });

    test('повторный dispose не бросает, после dispose база недоступна',
        () async {
      final dir = await Directory.systemTemp.createTemp('dharma_dbmodule_');
      addTearDown(() => dir.delete(recursive: true));
      final path = dir.path;
      mockDocumentsDirectory(path);

      final module = DatabaseModule();

      await module.init();
      await module.dispose();
      await expectLater(module.dispose(), completes);

      // Поведенческая проверка (урок 1): после закрытия модуль обязан
      // сбросить инстанс — доступ к базе снова бросает StateError.
      expect(() => module.database, throwsStateError);
    });
  });
}

/// Прод-конструктор [DatabaseModule] после C1(2) открывает файл из
/// path_provider прямо в `init`, поэтому канал обязан отвечать: иначе тест
/// проверял бы отказ платформы, а не контракт модуля.
void mockDocumentsDirectory(String path) {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(channel, (call) async {
    if (call.method == 'getApplicationDocumentsDirectory') return path;
    return null;
  });
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
}
