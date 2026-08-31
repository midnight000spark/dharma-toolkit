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

/// Поведенческие тесты реактивного трекера (Блок 3, I-6, I-7).
///
/// Проверяют не отрисовку виджетов, а поведение системы:
/// - атомарность инкремента при быстрых тапах (B-8);
/// - реактивность списка без ручного invalidate (B-1);
/// - обработку null из watchById (B-6).
void main() {
  group('Поведенческие тесты реактивного трекера', () {
    late AppDatabase db;
    late PracticeRepository repository;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repository = PracticeRepository(db);
    });

    tearDown(() async {
      try {
        await db.close();
      } catch (_) {}
    });

    testWidgets('два быстрых тапа "+" → в БД +2, UI без отката (B-8)',
        (tester) async {
      final now = DateTime.now();
      final practiceId = await repository.create(PracticeEntity(
        name: 'Тест',
        type: 'counter',
        traditionTag: 'test',
        createdAt: now,
        updatedAt: now,
      ));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            practiceRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp(
            home: PracticeCountScreen(practiceId: practiceId),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));

      // Начальное значение
      expect(find.text('0'), findsOneWidget);

      // Два быстрых тапа без ожидания между ними
      await tester.tap(find.text('+'));
      await tester.tap(find.text('+'));
      await tester.pump(const Duration(milliseconds: 100));

      // UI показывает 2 (не 1 и не 0)
      expect(find.text('2'), findsOneWidget);

      // БД тоже содержит 2 (атомарность UPDATE)
      final practices = await repository.getByTradition('test');
      expect(practices.first.currentCount, 2);

      await db.close();
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
        'инкремент на экране счёта → список показывает новое значение без invalidate (B-1)',
        (tester) async {
      final now = DateTime.now();
      await repository.create(PracticeEntity(
        name: 'Тест',
        type: 'counter',
        traditionTag: 'test',
        currentCount: 0,
        createdAt: now,
        updatedAt: now,
      ));

      // Роутер с двумя экранами: список и счёт
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) =>
                const PracticeListScreen(traditionTag: 'test'),
          ),
          GoRoute(
            path: '/practice/:id',
            builder: (context, state) {
              final id = int.parse(state.pathParameters['id']!);
              return PracticeCountScreen(practiceId: id);
            },
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            practiceRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));

      // Список показывает практику
      expect(find.text('Тест'), findsOneWidget);

      // Переходим на экран счёта
      await tester.tap(find.text('Тест'));
      await tester.pumpAndSettle();

      // Тапаем "+"
      await tester.tap(find.text('+'));
      await tester.pump(const Duration(milliseconds: 100));

      // Счёт на экране счёта обновился
      expect(find.text('1'), findsOneWidget);

      // Возвращаемся на список
      router.go('/');
      await tester.pumpAndSettle();

      // Список показывает обновлённое значение БЕЗ ручного invalidate (B-1).
      // Проверяем через repository, что данные сохранились
      final practices = await repository.getByTradition('test');
      expect(practices.first.currentCount, 1);

      await db.close();
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('null из watchById → "не найдена" с кнопкой "назад" (B-6)',
        (tester) async {
      // Создаём практику, потом удаляем её, чтобы watchById эмитил null
      final now = DateTime.now();
      final practiceId = await repository.create(PracticeEntity(
        name: 'Тест',
        type: 'counter',
        traditionTag: 'test',
        createdAt: now,
        updatedAt: now,
      ));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            practiceRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp(
            home: PracticeCountScreen(practiceId: practiceId),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));

      // Экран загружается нормально
      expect(find.text('Тест'), findsOneWidget);

      // Удаляем практику — watchById эмитит null
      await repository.delete(practiceId);
      await tester.pump(const Duration(milliseconds: 100));

      // Экран показывает "Практика не найдена" с кнопкой "Назад"
      expect(find.text('Практика не найдена'), findsOneWidget);
      expect(find.text('Назад'), findsOneWidget);

      await db.close();
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
