import 'package:dharma_toolkit/core/db/app_database.dart';
import 'package:dharma_toolkit/features/tracker/data/practice_repository.dart';
import 'package:dharma_toolkit/features/tracker/presentation/providers/practice_provider.dart';
import 'package:dharma_toolkit/features/tracker/presentation/screens/create_practice_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CreatePracticeScreen', () {
    late AppDatabase db;
    late PracticeRepository repository;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repository = PracticeRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    testWidgets('форма валидирует пустое название', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            practiceRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(
            home: CreatePracticeScreen(traditionTag: 'sample'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Тапаем "Создать" без ввода названия
      await tester.tap(find.text('Создать'));
      await tester.pumpAndSettle();

      expect(find.text('Введите название'), findsOneWidget);
    });

    testWidgets('можно ввести цель', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            practiceRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(
            home: CreatePracticeScreen(traditionTag: 'sample'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Вводим цель
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Цель (опционально)'),
        '1000',
      );

      expect(find.text('1000'), findsOneWidget);
    });

    testWidgets('можно ввести название', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            practiceRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(
            home: CreatePracticeScreen(traditionTag: 'sample'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Вводим название
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Название'),
        'Тестовая практика',
      );

      expect(find.text('Тестовая практика'), findsOneWidget);
    });
  });
}
