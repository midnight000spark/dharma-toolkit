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

  /// Прогресс выполнения, зажатый в [0.0, 1.0] (B-2, урок 3: чинится в домене,
  /// а не клампингом в каждом UI-месте). Невалидная или отсутствующая цель
  /// (null/0/отрицательная) даёт 0.0.
  double get progress => rawProgress.clamp(0.0, 1.0).toDouble();

  /// Прогресс без клампа сверху: перевыполнение — правда о подвиге, а не
  /// ошибка (112% цели можно показать отдельной надписью). Невалидная или
  /// отсутствующая цель (null/0/отрицательная) даёт 0.0.
  double get rawProgress {
    if (target == null || target! <= 0) return 0.0;
    return currentCount / target!;
  }

  /// Осталось до цели
  int? get remaining {
    if (target == null) return null;
    return target! - currentCount;
  }

  /// Копия с изменёнными полями (мелочь D-24). Поля не переданы — сохраняют
  /// значение оригинала; обнуляемые поля (target/unit/presetId/id)
  /// copyWith не очищает.
  PracticeEntity copyWith({
    int? id,
    String? presetId,
    String? name,
    String? type,
    int? target,
    String? unit,
    String? traditionTag,
    int? currentCount,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PracticeEntity(
      id: id ?? this.id,
      presetId: presetId ?? this.presetId,
      name: name ?? this.name,
      type: type ?? this.type,
      target: target ?? this.target,
      unit: unit ?? this.unit,
      traditionTag: traditionTag ?? this.traditionTag,
      currentCount: currentCount ?? this.currentCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
