import 'package:dharma_toolkit/core/module/app_module.dart';
import 'package:dharma_toolkit/core/module/module_registry.dart';
import 'package:dharma_toolkit/core/recovery/recovery_screen.dart';
import 'package:dharma_toolkit/core/recovery/startup.dart';
import 'package:dharma_toolkit/core/storage/storage_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// B-5: сбой инициализации даёт экран восстановления, а не чёрный экран.

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
    await tester.pumpWidget(RecoveryApp(
      error: outcome.fatalFailures.single.error,
      onRetry: () async {
        retries++;
      },
      onReset: () async {
        resets++;
      },
    ));
    await tester.pumpAndSettle();

    // Не чёрный экран: есть внятное сообщение и обе кнопки.
    expect(find.text('Не удалось прочитать данные'), findsOneWidget);
    expect(find.text('Попробовать снова'), findsOneWidget);
    expect(find.text('Сбросить настройки'), findsOneWidget);

    await tester.tap(find.text('Попробовать снова'));
    await tester.pumpAndSettle();
    expect(retries, 1);

    // I-3: сброс только через явное подтверждение — до диалога ничего не
    // стирается и не вызывается.
    await tester.tap(find.text('Сбросить настройки'));
    await tester.pumpAndSettle();
    expect(find.text('Сбросить все данные?'), findsOneWidget);
    expect(resets, 0);

    // wipeLocalState обращается к платформенным каналам (prefs/path_provider)
    // — их ответы в widget-тесте требуют реального async (документированный
    // паттерн tester.runAsync).
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(TextButton, 'Сбросить'));
      await Future<void>.delayed(Duration.zero);
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    });
    await tester.pumpAndSettle();
    expect(resets, 1,
        reason: 'stiranie + onReset только после подтверждения');
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
