import 'dart:async';

import 'package:dharma_toolkit/core/db/app_database.dart';
import 'package:dharma_toolkit/features/tracker/data/practice_repository.dart';
import 'package:dharma_toolkit/features/tracker/domain/practice.dart';
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

  // B-9: тесты пути сохранения (урок 4 — проверяем не отрисовку, а сохранение;
  // урок 5/F-38 — гонку двойного тапа детерминирует Completer-двойник).
  group('CreatePracticeScreen: путь сохранения (B-9)', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    testWidgets('двойной тап во время сохранения → ровно одна запись',
        (tester) async {
      final repo = _GatedRepository(db)..gate = Completer<int>();
      await _pumpCreateScreen(tester, repo);

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Название'), 'Обход');

      final button = find.widgetWithText(ElevatedButton, 'Создать');
      await tester.tap(button);
      await tester.pump(); // обрабатываем тап и setState(_saving: true)

      // Пока create в полёте — кнопка задизейблена.
      expect(tester.widget<ElevatedButton>(button).onPressed, isNull,
          reason: 'B-9: кнопка обязана блокироваться на время сохранения');

      await tester.tap(button); // второй тап — по заблокированной кнопке
      await tester.pump();
      expect(repo.createCalls, 1);

      repo.gate!.complete(1);
      await tester.pumpAndSettle();

      final rows = await repo.getByTradition('test');
      expect(rows.length, 1, reason: 'двойной тап не плодит дубли');
    });

    testWidgets('имя из пробелов → ошибка, запись не создаётся',
        (tester) async {
      final repo = _GatedRepository(db);
      await _pumpCreateScreen(tester, repo);

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Название'), '   ');
      await tester.tap(find.text('Создать'));
      await tester.pumpAndSettle();

      expect(find.text('Введите название'), findsOneWidget);
      expect(repo.createCalls, 0);
      expect(await repo.getByTradition('test'), isEmpty);
    });

    testWidgets('цель «100 000» сохраняется как 100000', (tester) async {
      final repo = _GatedRepository(db);
      await _pumpCreateScreen(tester, repo);

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Название'), 'Нёндро');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Цель (опционально)'), '100 000');
      await tester.tap(find.text('Создать'));
      await tester.pumpAndSettle();

      expect(repo.saved.single.target, 100000);
      final rows = await repo.getByTradition('test');
      expect(rows.single.target, 100000,
          reason: 'пробел-группировка не должен терять цель');
    });

    testWidgets('отрицательная цель «-5» → видимая ошибка, молча не теряется',
        (tester) async {
      final repo = _GatedRepository(db);
      await _pumpCreateScreen(tester, repo);

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Название'), 'Тест');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Цель (опционально)'), '-5');
      await tester.tap(find.text('Создать'));
      await tester.pumpAndSettle();

      expect(
          find.text('Цель должна быть целым числом больше нуля'),
          findsOneWidget);
      expect(repo.createCalls, 0);
    });

    testWidgets('единица из пробелов нормализуется в null', (tester) async {
      final repo = _GatedRepository(db);
      await _pumpCreateScreen(tester, repo);

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Название'), 'Чай');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Единица измерения'), '   ');
      await tester.tap(find.text('Создать'));
      await tester.pumpAndSettle();

      expect(repo.saved.single.unit, isNull);
    });

    testWidgets('имя с обрамляющими пробелами сохраняется trimmed',
        (tester) async {
      final repo = _GatedRepository(db);
      await _pumpCreateScreen(tester, repo);

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Название'), '  Мантра  ');
      await tester.tap(find.text('Создать'));
      await tester.pumpAndSettle();

      final rows = await repo.getByTradition('test');
      expect(rows.single.name, 'Мантра');
    });
  });
}

/// Репозиторий-двойник: [create] встает на Completer, пока тест его не
/// разрешит — детерминированная имитация «сохранение в полёте» (урок 5).
class _GatedRepository extends PracticeRepository {
  Completer<int>? gate;
  int createCalls = 0;
  final saved = <PracticeEntity>[];

  _GatedRepository(super.database);

  @override
  Future<int> create(PracticeEntity practice) async {
    createCalls++;
    saved.add(practice);
    final g = gate;
    if (g != null) await g.future;
    return super.create(practice);
  }
}

/// Открывает экран создания внутри реального маршрута Navigator
/// (pop после сохранения обязан быть куда.pop).
Future<void> _pumpCreateScreen(
    WidgetTester tester, _GatedRepository repo) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        practiceRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              key: const Key('open-create'),
              child: const Text('open'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      const CreatePracticeScreen(traditionTag: 'test'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open-create')));
  await tester.pumpAndSettle();
}
