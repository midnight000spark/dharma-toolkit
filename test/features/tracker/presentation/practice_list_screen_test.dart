import 'package:dharma_toolkit/features/tracker/domain/practice.dart';
import 'package:dharma_toolkit/features/tracker/presentation/providers/practice_provider.dart';
import 'package:dharma_toolkit/features/tracker/presentation/screens/practice_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('экран рендерится без ошибок', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: PracticeListScreen(traditionTag: 'test'),
        ),
      ),
    );

    expect(find.byType(PracticeListScreen), findsOneWidget);
  });

  testWidgets('показывает loading state', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: PracticeListScreen(traditionTag: 'test'),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('показывает список практик', (tester) async {
    final practices = [
      PracticeEntity(
        id: 1,
        name: 'Тестовая практика',
        type: 'counter',
        traditionTag: 'test',
        currentCount: 100,
        target: 1000,
        unit: 'раз',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceListProvider('test').overrideWith((ref) async => practices),
        ],
        child: const MaterialApp(
          home: PracticeListScreen(traditionTag: 'test'),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Тестовая практика'), findsOneWidget);
    expect(find.text('100 раз'), findsOneWidget);
    expect(find.text('10%'), findsOneWidget);
  });

  testWidgets('показывает error state', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceListProvider('test').overrideWith((ref) async {
            throw Exception('Тестовая ошибка');
          }),
        ],
        child: const MaterialApp(
          home: PracticeListScreen(traditionTag: 'test'),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.textContaining('Ошибка'), findsOneWidget);
  });
}
