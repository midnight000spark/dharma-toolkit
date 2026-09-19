import 'dart:async';
import 'dart:io';

import 'package:dharma_toolkit/core/db/app_database.dart'
    show kAppDatabaseFileName, PracticesCompanion;
import 'package:dharma_toolkit/core/db/database_module.dart';
import 'package:dharma_toolkit/core/module/app_module.dart';
import 'package:dharma_toolkit/core/module/module_registry.dart';
import 'package:dharma_toolkit/core/recovery/recovery_screen.dart';
import 'package:dharma_toolkit/core/recovery/startup.dart';
import 'package:dharma_toolkit/core/storage/storage_module.dart';
import 'package:drift/native.dart';
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
        return const WipeReport(prefsCleared: true);
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
        return const WipeReport(prefsCleared: true);
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

  // C2: `ErrorWidget.builder` вызывают и для сбоев выше MaterialApp, где
  // предка Directionality нет. Прежняя заглушка падала сама, фреймворк
  // подставлял замену для замены — рекурсия и тот же чёрный экран (класс
  // 5.3/B-5), ради которого её и вводили.
  //
  // Форма теста — прогон самого виджета-замены в качестве корня: test binding
  // запрещает подменять `ErrorWidget.builder` внутри теста
  // (`_verifyErrorWidgetBuilderUnset`), а само свойство, которое надо
  // проверить, — «заглушка достраивается без каких-либо предков».
  testWidgets('замена красного экрана достраивается без Directionality-предка '
      '(C2)', (tester) async {
    await tester.pumpWidget(
      humanErrorWidget(
        FlutterErrorDetails(exception: StateError('падение до первого кадра')),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull,
        reason: 'Text без Directionality-предка упал бы сам — и фреймворк '
            'взял бы замену для замены (рекурсия builder\'а)');
    expect(
      find.textContaining('Ошибка интерфейса. Приложение продолжит работу'),
      findsOneWidget,
    );
  });

  // S12-min: degradedModules из вердикта старта до экрана не доезжали.
  testWidgets('ограниченный режим показывается списком с классом отказа '
      '(S12-min)', (tester) async {
    await tester.pumpWidget(RecoveryApp(
      error: StateError('повреждённые данные'),
      degradations: [
        ModuleInitFailure(
          'config',
          StateError('FormatException…'),
          StackTrace.empty,
          kind: FailureKind.presetAssetSkipped,
          subject: 'presets/broken.json',
        ),
      ],
      onRetry: () async {},
      onReset: () async {},
      wipe: () async => const WipeReport(prefsCleared: true),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Приложение работает в ограниченном режиме:'),
        findsOneWidget);
    expect(
      find.byKey(
          const ValueKey('degradation-presetAssetSkipped-presets/broken.json')),
      findsOneWidget,
    );
    expect(find.textContaining('пресет пропущен'), findsOneWidget,
        reason: 'класс отказа человекочитаем');
    expect(find.textContaining('FormatException'), findsNothing,
        reason: 'B-19: сырые детали исключения остаются в логе');
  });

  testWidgets('без деградаций экрана-баннера нет (не выдуманная тревога)',
      (tester) async {
    await tester.pumpWidget(RecoveryApp(
      error: StateError('повреждённые данные'),
      onRetry: () async {},
      onReset: () async {},
      wipe: () async => const WipeReport(prefsCleared: true),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Приложение работает в ограниченном режиме:'),
        findsNothing);
  });

  // C3: у _run не было catch — отказ повторной попытки уходил в лог зоны
  // (а там корень уже смонтирован, то есть никуда), кнопка гасла на кадр и
  // становилась активной снова: «бесполезная кнопка / стереть всё».
  testWidgets('неудачная повторная попытка видна и считается (C3)',
      (tester) async {
    var attempts = 0;
    await tester.pumpWidget(RecoveryApp(
      error: StateError('повреждённые данные'),
      onRetry: () async {
        attempts++;
        throw StateError('опять не поднялись');
      },
      onReset: () async {},
      wipe: () async => const WipeReport(prefsCleared: true),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Попробовать снова'));
    await tester.pumpAndSettle();

    expect(attempts, 1);
    expect(
      find.byKey(const ValueKey('retry-failure')),
      findsOneWidget,
      reason: 'отказ обязан стать видимым сообщением на экране',
    );
    expect(find.textContaining('Повторная попытка не удалась (попытка 1)'),
        findsOneWidget);
    expect(find.textContaining('опять не поднялись'), findsNothing,
        reason: 'B-19: детали — в лог');

    await tester.tap(find.text('Попробовать снова'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.textContaining('попытка 2'), findsOneWidget,
        reason: 'счётчик попыток виден: retry не выглядит молчаливым');
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNotNull,
      reason: 'после отказа кнопка снова доступна (не зависла в _busy)',
    );
  });

  testWidgets('удачная попытка снимает сообщение о прошлом отказе (C3)',
      (tester) async {
    var failNext = true;
    await tester.pumpWidget(RecoveryApp(
      error: StateError('повреждённые данные'),
      onRetry: () async {
        if (failNext) {
          throw StateError('первая попытка упала');
        }
      },
      onReset: () async {},
      wipe: () async => const WipeReport(prefsCleared: true),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Попробовать снова'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('retry-failure')), findsOneWidget);

    failNext = false;
    await tester.tap(find.text('Попробовать снова'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('retry-failure')), findsNothing,
        reason: 'сообщение об отказе не должно висеть после успешной попытки');
  });

  // C1(2): «критичный модуль database» раньше не мог упасть — init только
  // конструировал AppDatabase над LazyDatabase, файл не открывался, и
  // повреждение физически не попадало в fatalFailures: оно всплывало текстом
  // на экране списка практик (сценарий (в) находки C1).
  group('зонд целостности БД (C1(2))', () {
    test('битый файл базы → init бросает, отказ классифицирован как фатал',
        () async {
      final dir = await Directory.systemTemp.createTemp('dharma_corrupt_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File(p.join(dir.path, kAppDatabaseFileName))
        ..writeAsStringSync('это не база данных, а простыня байтов');

      final module = DatabaseModule(executor: NativeDatabase(file));
      await expectLater(module.init(), throwsA(anything),
          reason: 'отказ открытия обязан всплыть в init, а не наружу в UI');

      final registry = ModuleRegistry.instance;
      await registry.disposeAll();
      addTearDown(registry.disposeAll);
      registry.register(module);

      final outcome = await bootstrapModules(registry);

      expect(outcome.ok, isFalse,
          reason: 'повреждение базы — фатал с причиной, а не «no such table» '
              'в списке практик');
      expect(outcome.fatalFailures.map((f) => f.moduleId), ['database']);
    });

    test('здоровая база проходит зонд и остаётся пригодной к записи',
        () async {
      final module = DatabaseModule(executor: NativeDatabase.memory());

      await module.init();

      // Не «getter вернул non-nullable», а поведение: соединение после зонда
      // живое и пишет (иначе «активный зонд» означал бы закрытую базу).
      final id = await module.database.into(module.database.practices).insert(
            PracticesCompanion.insert(
              name: 'Простирания',
              type: 'counter',
              traditionTag: 'nyingma',
            ),
          );
      expect(id, greaterThan(0));
      expect(await module.database.select(module.database.practices).get(),
          hasLength(1));

      await module.dispose();
    });
  });

  // C1(3): стирание обязано закрывать соединение до файловых операций, сносить
  // сайдкары журнала и беречь основной файл (rename вместо delete), а отказ —
  // попадать в отчёт, а не в debugPrint.
  group('аварийное стирание (C1(3))', () {
    late Directory dir;
    late String dbPath;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('dharma_wipe_');
      dbPath = p.join(dir.path, kAppDatabaseFileName);
      File(dbPath).writeAsStringSync('данные со счётчиком');
      File('$dbPath-journal').writeAsStringSync('journal');
      File('$dbPath-wal').writeAsStringSync('wal');
      File('$dbPath-shm').writeAsStringSync('shm');

      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return dir.path;
        }
        return null;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance
          .defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));
      SharedPreferences.setMockInitialValues({'dharma.wipe.test': 1});
    });

    tearDown(() async {
      if (dir.existsSync()) await dir.delete(recursive: true);
    });

    test('закрытие — раньше файлов; сайдкары снесены; база переименована',
        () async {
      final order = <String>[];

      final report = await wipeLocalState(closeDatabase: () async {
        order.add('close');
        // На момент закрытия основной файл ещё на месте: иначе SQLite дописал
        // бы его под уже удалённый путь.
        expect(File(dbPath).existsSync(), isTrue);
      });

      expect(order, ['close']);
      expect(File(dbPath).existsSync(), isFalse,
          reason: 'путь базы свободен — приложение стартует с чистой схемы');
      expect(report.renamedDatabaseTo, isNotNull);
      expect(File(report.renamedDatabaseTo!).existsSync(), isTrue,
          reason: 'файл сохранён под corrupt-именем: шанс вытащить счёт (D-26)');
      expect(p.basename(report.renamedDatabaseTo!),
          startsWith('$kAppDatabaseFileName.corrupt-'));
      expect(report.removedSidecars, unorderedEquals(<String>[
        '$kAppDatabaseFileName-journal',
        '$kAppDatabaseFileName-wal',
        '$kAppDatabaseFileName-shm',
      ]));
      for (final suffix in ['-journal', '-wal', '-shm']) {
        expect(File('$dbPath$suffix').existsSync(), isFalse,
            reason: 'оставленный журнал восстановил бы базу под удалённый путь');
      }
      expect(report.prefsCleared, isTrue);
      expect(report.errors, isEmpty);
      expect(report.clean, isTrue);
    });

    test('отказ закрытия попадает в отчёт и не отменяет стирание', () async {
      final report = await wipeLocalState(closeDatabase: () async {
        throw StateError('close не отдал соединение');
      });

      expect(report.clean, isFalse,
          reason: 'проглоченный отказ стирания — это «кнопка сработала», '
              'которая не сработала');
      expect(report.errors.single, contains('close не отдал соединение'));
      expect(File(dbPath).existsSync(), isFalse);
      expect(report.renamedDatabaseTo, isNotNull);
    });

    testWidgets('неполное стирание видно на экране, детали — в логе (C1(3))',
        (tester) async {
      await tester.pumpWidget(RecoveryApp(
        error: StateError('повреждённые данные'),
        onRetry: () async {},
        onReset: () async {},
        wipe: () async => const WipeReport(
          prefsCleared: true,
          errors: ['файл базы не переименован: errno 13'],
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('wipe-incomplete')), findsNothing,
          reason: 'до подтверждения стирания не было');

      await tester.tap(find.text('Сбросить настройки'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Сбросить'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('wipe-incomplete')), findsOneWidget);
      expect(
          find.textContaining('Стирание прошло не полностью'), findsOneWidget);
      expect(find.textContaining('errno 13'), findsNothing,
          reason: 'B-19: системные детали не уходят на экран');
    });
  });
}
