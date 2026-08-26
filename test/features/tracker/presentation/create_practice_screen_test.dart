import 'package:dharma_toolkit/features/tracker/presentation/screens/create_practice_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('форма валидирует пустое название', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CreatePracticeScreen(traditionTag: 'test'),
      ),
    );

    // Нажимаем "Создать" без ввода названия
    await tester.tap(find.text('Создать'));
    await tester.pump();

    expect(find.text('Введите название'), findsOneWidget);
  });

  testWidgets('можно выбрать тип (counter/timer)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CreatePracticeScreen(traditionTag: 'test'),
      ),
    );

    // Проверяем, что по умолчанию выбран "Счётчик"
    expect(find.text('Счётчик'), findsOneWidget);

    // Открываем dropdown
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();

    // Выбираем "Таймер"
    await tester.tap(find.text('Таймер').last);
    await tester.pumpAndSettle();

    expect(find.text('Таймер'), findsWidgets);
  });

  testWidgets('можно ввести цель', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CreatePracticeScreen(traditionTag: 'test'),
      ),
    );

    // Вводим цель
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Цель (опционально)'),
      '1000',
    );

    expect(find.text('1000'), findsOneWidget);
  });

  testWidgets('кнопка "Создать" работает', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CreatePracticeScreen(traditionTag: 'test'),
      ),
    );

    // Вводим название
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Название'),
      'Тестовая практика',
    );

    // Нажимаем "Создать"
    await tester.tap(find.text('Создать'));
    await tester.pumpAndSettle();

    // Экран должен закрыться (вернуться назад)
    expect(find.byType(CreatePracticeScreen), findsNothing);
  });
}
