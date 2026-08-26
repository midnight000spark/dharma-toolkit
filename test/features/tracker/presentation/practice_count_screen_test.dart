import 'package:dharma_toolkit/features/tracker/domain/practice.dart';
import 'package:dharma_toolkit/features/tracker/presentation/screens/practice_count_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final testPractice = PracticeEntity(
    id: 1,
    name: 'Тестовая практика',
    type: 'counter',
    traditionTag: 'test',
    currentCount: 100,
    target: 1000,
    unit: 'раз',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  testWidgets('экран рендерится с практикой', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PracticeCountScreen(practice: testPractice),
      ),
    );

    expect(find.byType(PracticeCountScreen), findsOneWidget);
    expect(find.text('Тестовая практика'), findsOneWidget);
  });

  testWidgets('показывает текущий счёт', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PracticeCountScreen(practice: testPractice),
      ),
    );

    expect(find.text('100'), findsOneWidget);
  });

  testWidgets('показывает прогресс-бар если есть target', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PracticeCountScreen(practice: testPractice),
      ),
    );

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Цель: 1000'), findsOneWidget);
  });

  testWidgets('кнопки +1, +10, +100 увеличивают счёт', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PracticeCountScreen(practice: testPractice),
      ),
    );

    // Начальное значение
    expect(find.text('100'), findsOneWidget);

    // Нажимаем +1
    await tester.tap(find.text('+1'));
    await tester.pump();
    expect(find.text('101'), findsOneWidget);

    // Нажимаем +10
    await tester.tap(find.text('+10'));
    await tester.pump();
    expect(find.text('111'), findsOneWidget);

    // Нажимаем +100
    await tester.tap(find.text('+100'));
    await tester.pump();
    expect(find.text('211'), findsOneWidget);
  });
}
