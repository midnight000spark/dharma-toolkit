import 'package:dharma_toolkit/core/db/app_database.dart';
import 'package:dharma_toolkit/features/tracker/data/practice_repository.dart';
import 'package:dharma_toolkit/features/tracker/domain/practice.dart';
import 'package:dharma_toolkit/features/tracker/presentation/providers/practice_provider.dart';
import 'package:dharma_toolkit/features/tracker/presentation/screens/practice_count_screen.dart';
import 'package:dharma_toolkit/features/tracker/presentation/screens/practice_list_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Трекер-UX 5.0.5: удаление трекера (FR-TRK-11, D-29 — только long-press +
/// диалог, swipe нет) и произвольный инкремент (FR-TRK-9 — диалог с общими
/// правилами валидации). Тесты поведенческие (уроки 1/4): проверяют путь
/// сохранения и каскад истории в БД, а не факт отрисовки.
/// FK включены (enableForeignKeys) — как в production-соединении: каскад
/// истории — обязанность БД (F-33/B-11), и тест без PRAGMA был бы фиктивным.
void main() {
  late AppDatabase db;
  late PracticeRepository repository;
  late int practiceId;

  setUp(() async {
    db = AppDatabase.forTesting(
      NativeDatabase.memory(setup: enableForeignKeys),
    );
    repository = PracticeRepository(db);
    final now = DateTime.now();
    practiceId = await repository.create(PracticeEntity(
      name: 'Простирания',
      type: 'counter',
      target: 1000,
      unit: 'раз',
      traditionTag: 'test',
      currentCount: 100,
      createdAt: now,
      updatedAt: now,
    ));
    // История счёта: 5 атомарных инкрементов по 1 (итоговый счёт — 105).
    for (var i = 0; i < 5; i++) {
      await repository.incrementCount(practiceId, 1);
    }
  });

  tearDown(() async {
    try {
      await db.close();
    } catch (_) {}
  });

  Future<void> pumpList(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [practiceRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp.router(
          routerConfig: GoRouter(
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) =>
                    const PracticeListScreen(traditionTag: 'test'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> pumpCount(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [practiceRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(home: PracticeCountScreen(practiceId: practiceId)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<List<int>> historyCounts(int id) async {
    final rows = await (db.select(
      db.countHistory,
    )..where((t) => t.practiceId.equals(id))).get();
    return rows.map((r) => r.count).toList();
  }

  /// Завершение по проверенному паттерну reactive_tracker_test: закрыть БД
  /// до unmount ProviderScope — иначе dispose стримов Drift оставляет
  /// pending timer внутри fake-async.
  Future<void> finish(WidgetTester tester) async {
    await db.close();
    await tester.pumpWidget(const SizedBox.shrink());
  }

  group('Удаление трекера long-press (FR-TRK-11)', () {
    testWidgets('долгое нажатие открывает диалог с именем, счётом и '
        'предупреждением; «Отмена» ничего не удаляет', (tester) async {
      await pumpList(tester);

      await tester.longPress(find.text('Простирания'));
      await tester.pump();

      expect(find.text('Удалить «Простирания»?'), findsOneWidget);
      expect(find.textContaining('Текущий счёт: 105 раз'), findsOneWidget);
      expect(
        find.textContaining('История счёта будет стёрта'),
        findsOneWidget,
      );
      expect(find.textContaining('Действие необратимо'), findsOneWidget);

      await tester.tap(find.text('Отмена'));
      await tester.pump(const Duration(milliseconds: 300));

      // Запись на месте и в БД, и в списке (стрим не солгал).
      final rows = await repository.getByTradition('test');
      expect(rows.map((p) => p.id), contains(practiceId));
      expect(find.text('Простирания'), findsOneWidget);

      await finish(tester);
    });

    testWidgets('«Удалить» стирает практику и её историю (каскад), список '
        'обновляется стримом', (tester) async {
      await pumpList(tester);
      expect(await historyCounts(practiceId), hasLength(5));

      await tester.longPress(find.text('Простирания'));
      await tester.pump();
      await tester.tap(find.text('Удалить'));
      await tester.pump(const Duration(milliseconds: 100));

      // Список обновился без ручной перезагрузки (D-16).
      expect(find.text('Простирания'), findsNothing);
      expect(find.text('Пока нет практик'), findsOneWidget);

      // Путь сохранения: практика удалена из БД…
      final remaining = await (db.select(
        db.practices,
      )..where((t) => t.id.equals(practiceId))).get();
      expect(remaining, isEmpty);
      // …и история стёрта каскадом (FK ON DELETE CASCADE, F-33) — не осиротела.
      expect(await historyCounts(practiceId), isEmpty);

      await finish(tester);
    });

    testWidgets('тап (не long-press) удаление НЕ открывает (D-29)',
        (tester) async {
      await pumpList(tester);

      await tester.tap(find.text('Простирания'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('История счёта будет стёрта'), findsNothing);
      final rows = await repository.getByTradition('test');
      expect(rows, hasLength(1));

      await finish(tester);
    });
  });

  group('Произвольный инкремент (FR-TRK-9)', () {
    testWidgets('«1 500» → счёт +1500 и строка истории с этим числом',
        (tester) async {
      await pumpCount(tester);
      expect(find.text('105'), findsOneWidget); // 100 + 5 из setUp

      await tester.tap(find.text('Ввести число'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '1 500');
      await tester.tap(find.text('Прибавить'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('1605'), findsOneWidget);
      final practices = await repository.getByTradition('test');
      expect(practices.single.currentCount, 1605);
      // Строка count_history записана (тот же атомарный incrementCount).
      expect(await historyCounts(practiceId), contains(1500));

      await finish(tester);
    });

    for (final (raw, errorText) in const [
      ('-5', 'Число должно быть целым больше нуля'),
      ('abc', 'Число должно быть целым больше нуля'),
      ('', 'Введите число'),
    ]) {
      testWidgets('невалидный ввод «$raw» → видимая ошибка, счёт не изменился',
          (tester) async {
        await pumpCount(tester);

        await tester.tap(find.text('Ввести число'));
        await tester.pump();
        await tester.enterText(find.byType(TextField), raw);
        await tester.tap(find.text('Прибавить'));
        await tester.pump();

        // Диалог открыт, ошибка под полем — молчаливого no-op нет (урок 4).
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text(errorText), findsOneWidget);

        await tester.tap(find.text('Отмена'));
        await tester.pump(const Duration(milliseconds: 300));

        final practices = await repository.getByTradition('test');
        expect(practices.single.currentCount, 105);
        expect(await historyCounts(practiceId), hasLength(5));

        await finish(tester);
      });
    }
  });
}
