import 'package:dharma_toolkit/features/tracker/domain/practice.dart';
import 'package:flutter_test/flutter_test.dart';

/// Доменные тесты прогресса (B-2, урок 3: guarantee живёт в PracticeEntity,
/// а не в клампинге по каждому UI-месту).
void main() {
  PracticeEntity make({int? target, int count = 0}) => PracticeEntity(
        name: 'Тест',
        type: 'counter',
        target: target,
        traditionTag: 'test',
        currentCount: count,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

  group('PracticeEntity.progress (B-2)', () {
    test('перевыполнение 150/100: progress клампнут в 1.0, rawProgress 1.5',
        () {
      final p = make(target: 100, count: 150);
      expect(p.progress, 1.0);
      expect(p.rawProgress, 1.5);
    });

    test('обычный прогресс 50/100: progress == rawProgress == 0.5', () {
      final p = make(target: 100, count: 50);
      expect(p.progress, 0.5);
      expect(p.rawProgress, 0.5);
    });

    test('нулевая цель даёт 0.0 в обоих (нет Infinity/NaN)', () {
      final p = make(target: 0, count: 10);
      expect(p.progress, 0.0);
      expect(p.rawProgress, 0.0);
    });

    test('отрицательная цель (-5) даёт 0.0 в обоих', () {
      final p = make(target: -5, count: 3);
      expect(p.progress, 0.0);
      expect(p.rawProgress, 0.0);
    });

    test('цель null даёт 0.0 в обоих', () {
      final p = make(target: null, count: 7);
      expect(p.progress, 0.0);
      expect(p.rawProgress, 0.0);
    });

    test('currentCount никогда не клампнется доменом: 150 остаётся 150', () {
      final p = make(target: 100, count: 150);
      expect(p.currentCount, 150);
    });
  });
}
