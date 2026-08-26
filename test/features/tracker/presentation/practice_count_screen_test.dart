import 'package:dharma_toolkit/core/db/app_database.dart';
import 'package:dharma_toolkit/features/tracker/data/practice_repository.dart';
import 'package:dharma_toolkit/features/tracker/domain/practice.dart';
import 'package:dharma_toolkit/features/tracker/presentation/providers/practice_provider.dart';
import 'package:dharma_toolkit/features/tracker/presentation/screens/practice_count_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PracticeCountScreen', () {
    late AppDatabase db;
    late PracticeRepository repository;
    late int practiceId;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repository = PracticeRepository(db);

      final now = DateTime.now();
      practiceId = await repository.create(PracticeEntity(
        name: 'Тестовая практика',
        type: 'counter',
        target: 100,
        unit: 'раз',
        traditionTag: 'test',
        currentCount: 10,
        createdAt: now,
        updatedAt: now,
      ));
    });

    tearDown(() async {
      await db.close();
    });

    testWidgets('экран загружает практику по ID', (tester) async {
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

      await tester.pumpAndSettle();

      expect(find.text('Тестовая практика'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
      expect(find.text('Цель: 100'), findsOneWidget);
    });

    testWidgets('тап +1 увеличивает счёт', (tester) async {
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

      await tester.pumpAndSettle();

      // Начальное значение
      expect(find.text('10'), findsOneWidget);

      // Тапаем +1
      await tester.tap(find.text('+1'));
      await tester.pumpAndSettle();

      // Проверяем, что счёт увеличился
      expect(find.text('11'), findsOneWidget);

      // Проверяем, что данные сохранились в репозитории
      final practices = await repository.getByTradition('test');
      expect(practices.first.currentCount, 11);
    });

    testWidgets('тап +10 увеличивает счёт на 10', (tester) async {
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

      await tester.pumpAndSettle();

      await tester.tap(find.text('+10'));
      await tester.pumpAndSettle();

      expect(find.text('20'), findsOneWidget);

      final practices = await repository.getByTradition('test');
      expect(practices.first.currentCount, 20);
    });
  });
}
