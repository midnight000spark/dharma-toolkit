import '../../../core/db/app_database.dart';

/// Доменная модель практики
class PracticeEntity {
  final int? id;
  final String? presetId;
  final String name;
  final String type; // 'counter' или 'timer'
  final int? target;
  final String? unit;
  final String traditionTag;
  final int currentCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  PracticeEntity({
    this.id,
    this.presetId,
    required this.name,
    required this.type,
    this.target,
    this.unit,
    required this.traditionTag,
    this.currentCount = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PracticeEntity.fromRow(Practice row) {
    return PracticeEntity(
      id: row.id,
      presetId: row.presetId,
      name: row.name,
      type: row.type,
      target: row.target,
      unit: row.unit,
      traditionTag: row.traditionTag,
      currentCount: row.currentCount,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  /// Прогресс выполнения (0.0 - 1.0)
  double get progress {
    if (target == null || target == 0) return 0.0;
    return currentCount / target!;
  }

  /// Осталось до цели
  int? get remaining {
    if (target == null) return null;
    return target! - currentCount;
  }
}
