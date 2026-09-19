import 'dart:async';
import 'dart:io';

import 'package:dharma_toolkit/core/db/app_database.dart'
    show kAppDatabaseFileName;
import 'package:dharma_toolkit/core/module/app_module.dart';
import 'package:dharma_toolkit/core/module/module_registry.dart';
import 'package:dharma_toolkit/core/recovery/recovery_screen.dart';
import 'package:dharma_toolkit/core/recovery/startup.dart';
import 'package:dharma_toolkit/core/storage/storage_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// B-5: сбой инициализации даёт экран восстановления, а не чёрный экран.
///
/// R-27: widget-тесты этого файла идут **только в fake-async зоне** — стирание
/// (`wipe`) инжектируется, живых таймингов и реальных платформенных каналов в
/// них нет. Прежняя форма ждала реальный I/O фиксированным окном
/// (`runAsync` + `Duration(milliseconds: 50)`) и флейкала: `onReset` не
/// успевал выполниться, `expect(resets, 1)` падал по `Actual: <0>`.
/// Поведение реального [wipeLocalState] покрыто отдельным тестом ниже —
/// там `await` идёт по фактическому завершению future, а канал path_provider
/// замокан (F-40), поэтому фиксированных окон не требуется и там.

/// Хранилище, которое всегда падает на init.
class _FailingStorage extends StorageModule {
  @override
  Future<void> init() async {
    throw StateError('Симуляция повреждённых настроек');
  }
}

/// Некритичный модуль-отказ (не входит в kCriticalModuleIds).
class _FailingAuxiliary implements AppModule {
  @override
  String get id => 'aux';

  @override
  String get name => 'Вспомогательный';

  @override
  String get version => '1.0.0';

  @override
  Future<void> init() async {
    throw StateError('Вспомогательный сломан');
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ModuleRegistry.instance.disposeAll();
  });

  tearDown(() async {
    await ModuleRegistry.instance.disposeAll();
  });

  testWidgets('провал StorageModule → критичный вердикт и RecoveryApp, '
      'не чёрный экран (B-5)', (tester) async {
    final registry = ModuleRegistry.instance;
    registry.register(_FailingStorage());

    final outcome = await bootstrapModules(registry);

    expect(outcome.ok, isFalse);
    expect(outcome.fatalFailures.single.moduleId, 'storage');

    var retries = 0;
    var resets = 0;
    var wipeCalls = 0;
    await tester.pumpWidget(RecoveryApp(
      error: outcome.fatalFailures.single.error,
      onRetry: () async {
        retries++;
      },
      onReset: () async {
        resets++;
      },
      wipe: () async {
        wipeCalls++;
      },
    ));
    await tester.pumpAndSettle();

    // Не чёрный экран: есть внятное сообщение и обе кнопки.
    expect(find.text('Не удалось прочитать данные'), findsOneWidget);
    expect(find.text('Попробовать снова'), findsOneWidget);
    expect(find.text('Сбросить настройки'), findsOneWidget);

    // B-19: на экране нет деталей исключения — только человеческое сообщение.
    expect(find.textContaining('Симуляция повреждённых настроек'), findsNothing,
        reason: 'сырое исключение не должно доходить до пользователя');
    expect(
      find.textContaining('Попробуйте ещё раз. Если не поможет'),
      findsOneWidget,
    );

    await tester.tap(find.text('Попробовать снова'));
    await tester.pumpAndSettle();
    expect(retries, 1);

    // I-3: сброс только через явное подтверждение — до диалога ничего не
    // стирается и не вызывается.
    await tester.tap(find.text('Сбросить настройки'));
    await tester.pumpAndSettle();
    expect(find.text('Сбросить все данные?'), findsOneWidget);
    expect(wipeCalls, 0);
    expect(resets, 0);

    // Отмена в диалоге: стирание не запускается вовсе.
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(wipeCalls, 0, reason: 'после отмены стирания нет');
    expect(resets, 0, reason: 'после отмены перезапуска нет');

    // Подтверждение: стирание, затем onReset — ровно по разу.
    await tester.tap(find.text('Сбросить настройки'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Сбросить'));
    await tester.pumpAndSettle();
    expect(wipeCalls, 1,
        reason: 'stiranie + onReset только после подтверждения');
    expect(resets, 1,
        reason: 'stiranie + onReset только после подтверждения');
  });

  testWidgets('стирание не завершено → onReset ждёт факта, экран занят (R-27)',
      (tester) async {
    final gate = Completer<void>();
    var wiped = false;
    var resets = 0;

    await tester.pumpWidget(RecoveryApp(
      error: StateError('повреждённые данные'),
      onRetry: () async {},
      onReset: () async {
        resets++;
      },
      wipe: () async {
        await gate.future;
        wiped = true;
      },
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Сбросить настройки'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Сбросить'));
    await tester.pumpAndSettle();

    // Гард R-27: пока стирание не завершилось (инжектированная задержка —
    // закрытые ворота), onReset не вызывается, а обе кнопки заняты: прежняя
    // форма теста смотрела на фиксированное окно времени, а не на факт.
    expect(wiped, isFalse);
    expect(resets, 0,
        reason: 'onReset не имеет права обгонять незавершённое стирание');
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNull,
      reason: 'во время стирания повторный запуск заблокирован',
    );
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
      reason: 'во время стирания повторная попытка заблокирована',
    );

    gate.complete();
    await tester.pumpAndSettle();

    expect(wiped, isTrue);
    expect(resets, 1, reason: 'после завершения стирания — один перезапуск');
  });

  test('wipeLocalState стирает настройки и файл БД (реальный путь, R-27)',
      () async {
    final dir = Directory.systemTemp.createTempSync('dharma-r27');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    const channel = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') return dir.path;
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    SharedPreferences.setMockInitialValues({'dharma.test': 1});
    final dbFile = File(p.join(dir.path, kAppDatabaseFileName))
      ..writeAsStringSync('повреждённая БД');
    expect(dbFile.existsSync(), isTrue);

    // Ждём фактического завершения future, а не фиксированного окна времени.
    await wipeLocalState();

    expect(dbFile.existsSync(), isFalse, reason: 'файл БД удалён');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isEmpty, reason: 'настройки очищены');
  });

  test('отказ некритичного модуля — деградация, старт допустим (5.4)',
      () async {
    final registry = ModuleRegistry.instance;
    registry.register(_FailingAuxiliary());

    final outcome = await bootstrapModules(registry);

    expect(outcome.ok, isTrue);
    expect(outcome.degradedModules.map((f) => f.moduleId), ['aux']);
  });
}
