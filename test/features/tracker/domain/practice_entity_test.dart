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

  group('PracticeEntity.copyWith', () {
    test('меняет только названное поле, остальные сохраняются', () {
      final original = PracticeEntity(
        id: 1,
        presetId: 'pres-1',
        name: 'Нёндро',
        type: 'counter',
        target: 100000,
        unit: 'повторения',
        traditionTag: 'nyingma',
        currentCount: 42,
        createdAt: DateTime(2026, 1, 1, 10),
        updatedAt: DateTime(2026, 1, 1, 11),
      );

      final changed = original.copyWith(currentCount: 43);

      expect(changed.currentCount, 43);
      expect(changed.id, original.id);
      expect(changed.presetId, original.presetId);
      expect(changed.name, original.name);
      expect(changed.type, original.type);
      expect(changed.target, original.target);
      expect(changed.unit, original.unit);
      expect(changed.traditionTag, original.traditionTag);
      expect(changed.createdAt, original.createdAt);
      expect(changed.updatedAt, original.updatedAt);
      // оригинал не mutated
      expect(original.currentCount, 42);
    });

    test('copyWith с несколькими полями — все применены', () {
      final changed = make(target: 10, count: 1).copyWith(
        name: 'Другое',
        target: 20,
        currentCount: 5,
      );
      expect(changed.name, 'Другое');
      expect(changed.target, 20);
      expect(changed.currentCount, 5);
    });
  });
}
