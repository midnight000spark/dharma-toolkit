import 'package:dharma_toolkit/core/db/app_database.dart';
import 'package:dharma_toolkit/features/tracker/data/practice_repository.dart';
import 'package:dharma_toolkit/features/tracker/domain/practice.dart';
import 'package:dharma_toolkit/features/tracker/presentation/providers/practice_provider.dart';
import 'package:dharma_toolkit/features/tracker/presentation/screens/practice_list_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  group('PracticeListScreen', () {
    late AppDatabase db;
    late PracticeRepository repository;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repository = PracticeRepository(db);

      final now = DateTime.now();

      // Создаём тестовые практики
      await repository.create(PracticeEntity(
        name: 'Простирания',
        type: 'counter',
        target: 1000,
        unit: 'раз',
        traditionTag: 'sample',
        currentCount: 100,
        createdAt: now,
        updatedAt: now,
      ));

      await repository.create(PracticeEntity(
        name: 'Мантра',
        type: 'counter',
        target: 10000,
        unit: 'раз',
        traditionTag: 'sample',
        currentCount: 500,
        createdAt: now.add(const Duration(seconds: 1)),
        updatedAt: now.add(const Duration(seconds: 1)),
      ));
    });

    tearDown(() async {
      // Закрываем БД, если ещё не закрыта (игнорируем ошибки повторного закрытия)
      try {
        await db.close();
      } catch (_) {}
    });

    testWidgets('показывает список практик', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            practiceRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp.router(
            routerConfig: GoRouter(
              routes: [
                GoRoute(
                  path: '/',
                  builder: (context, state) =>
                      const PracticeListScreen(traditionTag: 'sample'),
                ),
              ],
            ),
          ),
        ),
      );

      // Ждём эмиссии стрима (не pumpAndSettle — стримы не settling)
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Простирания'), findsOneWidget);
      expect(find.text('Мантра'), findsOneWidget);
      expect(find.text('100 раз'), findsOneWidget);
      expect(find.text('500 раз'), findsOneWidget);

      // Закрываем БД и заменяем виджет, чтобы dispose прошёл без pending timers
      await db.close();
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('показывает прогресс в процентах', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            practiceRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp.router(
            routerConfig: GoRouter(
              routes: [
                GoRoute(
                  path: '/',
                  builder: (context, state) =>
                      const PracticeListScreen(traditionTag: 'sample'),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));

      // 100/1000 = 10%
      expect(find.text('10%'), findsOneWidget);
      // 500/10000 = 5%
      expect(find.text('5%'), findsOneWidget);

      await db.close();
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('имеет FAB для создания', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            practiceRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp.router(
            routerConfig: GoRouter(
              routes: [
                GoRoute(
                  path: '/',
                  builder: (context, state) =>
                      const PracticeListScreen(traditionTag: 'sample'),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);

      await db.close();
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
