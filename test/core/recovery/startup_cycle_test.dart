import 'dart:io';

import 'package:dharma_toolkit/core/module/app_module.dart';
import 'package:dharma_toolkit/core/module/module_registry.dart';
import 'package:dharma_toolkit/core/recovery/startup.dart';
import 'package:dharma_toolkit/main.dart' show AppServices, bootstrapServices;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// C3: контроль цикла старта. `main` под тестом означало бы `runApp` всего
/// приложения, поэтому поток вынесен в [runStartupCycle] и проверяется здесь.

/// Мок сервисов: цикл оперирует типом T, содержимое не важно.
class _Services {
  const _Services(this.tag);
  final String tag;
}

class _FailingAuxiliary implements AppModule {
  @override
  String get id => 'zz_aux';

  @override
  String get name => 'Вспомогательный';

  @override
  String get version => '1.0.0';

  @override
  Future<void> init() async {}

  @override
  Future<void> dispose() async {
    throw StateError('dispose упал — как у ленивой базы после неудачного '
        'открытия (C3:LazyDatabase кеширует ошибку и пере-брасывает её на '
        'каждом close)');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('runStartupCycle (C3)', () {
    test('отказ bootstrap не уходит наружу — смонтировано восстановление',
        () async {
      Object? mountedError;
      final boom = StateError('второй прогон тоже упал');

      final root = await runStartupCycle<_Services>(
        bootstrap: () async => throw boom,
        mountApp: (_) async {},
        mountRecovery: (error, outcome) => mountedError = error,
      );

      expect(root, MountedRoot.recovery);
      expect(mountedError, same(boom),
          reason: 'причина обязана дойти до экрана: без неё «Попробовать '
              'снова» выглядит как несработавшая кнопка');
    });

    test('фатальные отказы модулей → recovery с первым из них и Services null',
        () async {
      final outcome = StartupOutcome(
        fatalFailures: [
          ModuleInitFailure('storage', StateError('настройки не читаются'),
              StackTrace.empty),
        ],
        degradedModules: const [],
      );

      final root = await runStartupCycle<_Services>(
        bootstrap: () async => (null, outcome),
        mountApp: (_) async {},
        mountRecovery: (error, received) => expect(received, same(outcome)),
      );

      expect(root, MountedRoot.recovery);
    });

    test('успешный цикл → рабочий корень, восстановление не монтируется',
        () async {
      var mounted = <String>[];

      final root = await runStartupCycle<_Services>(
        bootstrap: () async => (
          const _Services('ok'),
          const StartupOutcome(fatalFailures: [], degradedModules: [])
        ),
        mountApp: (services) async => mounted.add('app:${services.tag}'),
        mountRecovery: (error, outcome) => mounted.add('recovery'),
      );

      expect(root, MountedRoot.app);
      expect(mounted, ['app:ok']);
    });

    test('бросок из mountApp тоже даёт recovery (чёрного экрана нет)',
        () async {
      final boom = StateError('DatabaseModule not initialized в роутере');

      final root = await runStartupCycle<_Services>(
        bootstrap: () async => (
          const _Services('ok'),
          const StartupOutcome(fatalFailures: [], degradedModules: [])
        ),
        mountApp: (_) async => throw boom,
        mountRecovery: (error, outcome) => expect(error, same(boom)),
      );

      expect(root, MountedRoot.recovery);
    });
  });

  group('bootstrapServices после отказа диспоза (C3)', () {
    late Directory tempDir;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      // Composition root трогает реальный путь прод-соединения (ленивый файл
      // из path_provider), поэтому канал обязан отвечать: без него Dev-посев
      // падает MissingPluginException, а LazyDatabase пере-брасывает ошибку
      // opener'а второй раз уже в зону теста (тот же контур, что R-27).
      tempDir = await Directory.systemTemp.createTemp('dharma_bootstrap_');
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return tempDir.path;
        }
        return null;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance
          .defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));
      await ModuleRegistry.instance.disposeAll();
    });

    tearDown(() async {
      await ModuleRegistry.instance.disposeAll();
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });

    test('отказ disposeAll не отменяет пересоздание реестра', () async {
      final registry = ModuleRegistry.instance;
      registry.register(_FailingAuxiliary());

      final (services, outcome) = await bootstrapServices();

      expect(services, isNotNull,
          reason: 'повторная попытка обязана дойти до пересборки: раньше '
              'disposeAll переподнимал ошибку ленивой базы, и retry молча '
              'прерывался');
      expect(outcome.ok, isTrue);
      expect(
        registry.all.map((m) => m.id),
        containsAll(['database', 'storage', 'config', 'preset_manager']),
      );
      expect(registry.all.map((m) => m.id), isNot(contains('zz_aux')),
          reason: 'прошлая попытка всё же вычищена');
    });

    test('сервисы собраны из реальных модулей реестра', () async {
      final (services, _) = await bootstrapServices();

      expect(services, isA<AppServices>());
      final registry = ModuleRegistry.instance;
      expect(services!.config, same(registry.get('config')));
      expect(services.presetManager, same(registry.get('preset_manager')));
    });
  });
}

