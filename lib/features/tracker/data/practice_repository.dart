import 'package:drift/drift.dart';

import '../../../core/db/app_database.dart';
import '../domain/practice.dart';

/// Репозиторий для работы с практиками
class PracticeRepository {
  final AppDatabase _database;

  PracticeRepository(this._database);

  /// Получить все практики для конкретной традиции
  Future<List<PracticeEntity>> getByTradition(String traditionTag) async {
    final query = _database.select(_database.practices)
      ..where((t) => t.traditionTag.equals(traditionTag))
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);

    final rows = await query.get();
    return rows.map((row) => PracticeEntity.fromRow(row)).toList();
  }

  /// Получить практику по ID
  Future<PracticeEntity> getById(int id) async {
    final row = await (_database.select(_database.practices)
          ..where((t) => t.id.equals(id)))
        .getSingle();
    return PracticeEntity.fromRow(row);
  }

  /// Создать новую практику
  Future<int> create(PracticeEntity practice) async {
    return await _database.into(_database.practices).insert(
          PracticesCompanion.insert(
            presetId: Value(practice.presetId),
            name: practice.name,
            type: practice.type,
            target: Value(practice.target),
            unit: Value(practice.unit),
            traditionTag: practice.traditionTag,
            currentCount: Value(practice.currentCount),
          ),
        );
  }

  /// Обновить счётчик практики
  Future<void> incrementCount(int practiceId, int amount) async {
    await _database.transaction(() async {
      // Получаем текущую практику
      final current = await (_database.select(_database.practices)
            ..where((t) => t.id.equals(practiceId)))
          .getSingle();

      // Увеличиваем currentCount
      await (_database.update(_database.practices)
            ..where((t) => t.id.equals(practiceId)))
          .write(
        PracticesCompanion(
          currentCount: Value(current.currentCount + amount),
          updatedAt: Value(DateTime.now()),
        ),
      );

      // Добавляем запись в историю
      await _database.into(_database.countHistory).insert(
            CountHistoryCompanion.insert(
              practiceId: practiceId,
              count: amount,
            ),
          );
    });
  }

  /// Удалить практику
  Future<void> delete(int practiceId) async {
    await (_database.delete(_database.practices)
          ..where((t) => t.id.equals(practiceId)))
        .go();
  }
}
