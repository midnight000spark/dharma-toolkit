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
import 'package:go_router/go_router.dart';

void main() {
  group('CreatePracticeScreen', () {
    late AppDatabase db;
    late PracticeRepository repository;

    setUp(() async {
      db = AppDatabase.withExecutor(NativeDatabase.memory());
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
      db = AppDatabase.withExecutor(NativeDatabase.memory());
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

  // W31: без границы ввода в поле имени проходило 5000+ символов и уезжало в
  // БД и заголовки; лимит обрезает ввод на месте (урок 4 — проверяется путь
  // ввода, а не факт отрисовки).
  group('W31: лимиты ввода', () {
    late AppDatabase db;
    late PracticeRepository repository;

    setUp(() async {
      db = AppDatabase.withExecutor(NativeDatabase.memory());
      repository = PracticeRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    Future<void> pumpForm(WidgetTester tester) async {
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
    }

    String textOf(WidgetTester tester, String label) {
      final editable = tester.widget<EditableText>(find.descendant(
        of: find.widgetWithText(TextFormField, label),
        matching: find.byType(EditableText),
      ));
      return editable.controller.text;
    }

    testWidgets('имя обрезается до 120 символов, а не уходит целиком',
        (tester) async {
      await pumpForm(tester);

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Название'), 'а' * 10000);
      await tester.pump();

      expect(textOf(tester, 'Название').length, 120,
          reason: 'W31: ввод обязан обрезаться лимитом поля');
    });

    testWidgets('единица измерения обрезается до 24 символов', (tester) async {
      await pumpForm(tester);

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Единица измерения'), 'б' * 5000);
      await tester.pump();

      expect(textOf(tester, 'Единица измерения').length, 24);
    });
  });

  // R-19: форма предлагала тип «Таймер», которого в MVP нет (FR-TRK-7 —
  // бэклог v1.1), и созданный «таймер» открывался экраном счёта по тапам.
  // Guard проверяет, что список типов берётся из доменного PracticeTypes
  // (урок 3), а не из литералов виджета.
  group('R-19: форма не предлагает несуществующий тип практики', () {
    late AppDatabase db;
    late PracticeRepository repository;

    setUp(() async {
      db = AppDatabase.withExecutor(
          NativeDatabase.memory(setup: enableForeignKeys));
      repository = PracticeRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    testWidgets('все пункты типа — ровно доменный набор PracticeTypes',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            practiceRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(
            home: CreatePracticeScreen(traditionTag: 'test'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Открываем выпадающий список типов.
      await tester.tap(find.text('Счётчик'));
      await tester.pumpAndSettle();

      final offered = tester
          .widgetList<DropdownMenuItem<String>>(
              find.byType(DropdownMenuItem<String>))
          .map((item) => item.value)
          .toSet();

      expect(offered, PracticeTypes.available.toSet(),
          reason: 'R-19: UI показывает ровно типы домена, не свои литералы');
      expect(find.text('Таймер'), findsNothing,
          reason: 'R-19: тип без экрана не предлагается пользователю');

      // Закрываем меню, чтобы не оставлять открытый route.
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
    });

    testWidgets('у каждого доменного типа есть человекочитаемая подпись',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            practiceRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(
            home: CreatePracticeScreen(traditionTag: 'test'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Счётчик'));
      await tester.pumpAndSettle();

      // Сырое значение вместо подписи («counter») означало бы, что новый тип
      // домена забыли подписать — это заметно, а не молчит.
      for (final type in PracticeTypes.available) {
        expect(find.text(type), findsNothing,
            reason: 'тип "$type" показан сырым значением — нет подписи');
      }

      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
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

/// Открывает экран создания через реальный GoRouter (экран после сохранения
/// зовёт context.pop() — навигация приложения одна, go_router API, 6.5).
Future<void> _pumpCreateScreen(
    WidgetTester tester, _GatedRepository repo) async {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              key: const Key('home'),
              child: const Text('home'),
              onPressed: () {},
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/create',
        builder: (context, state) =>
            const CreatePracticeScreen(traditionTag: 'test'),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        practiceRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  unawaited(router.push('/create'));
  await tester.pumpAndSettle();
}
