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

  /// Стрим всех практик для конкретной традиции (D-16, I-1).
  ///
  /// Реактивный аналог [getByTradition]: Drift переэмитит список при любом
  /// изменении таблицы `practices` (insert/update/delete). Используется
  /// экраном списка для автоматического обновления без ручного invalidate.
  Stream<List<PracticeEntity>> watchByTradition(String traditionTag) {
    final query = _database.select(_database.practices)
      ..where((t) => t.traditionTag.equals(traditionTag))
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);

    return query.watch().map(
          (rows) => rows.map((row) => PracticeEntity.fromRow(row)).toList(),
        );
  }

  /// Получить практику по ID
  Future<PracticeEntity> getById(int id) async {
    final row = await (_database.select(_database.practices)
          ..where((t) => t.id.equals(id)))
        .getSingle();
    return PracticeEntity.fromRow(row);
  }

  /// Стрим практики по ID (D-16, I-1).
  ///
  /// Реактивный аналог [getById]. Если практика удалена или не существует,
  /// стрим эмитит `null` — это лекарство от B-6 (вечный спиннер): экран
  /// получает явное состояние «не найдена» вместо неопределённого Future,
  /// который мог упасть с исключением.
  Stream<PracticeEntity?> watchById(int id) {
    return (_database.select(_database.practices)
          ..where((t) => t.id.equals(id)))
        .watchSingleOrNull()
        .map((row) => row == null ? null : PracticeEntity.fromRow(row));
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

  /// Атомарно увеличить счётчик практики на [amount] (I-2, B-8).
  ///
  /// Один `UPDATE ... SET current_count = current_count + ?` вместо
  /// read-modify-write: нет гонки при быстром тапе (B-8), нет лишнего
  /// чтения. Запись в историю — в той же транзакции.
  Future<void> incrementCount(int practiceId, int amount) async {
    await _database.transaction(() async {
      // Атомарный инкремент: current_count = current_count + amount.
      // PracticesCompanion.custom принимает Expression<int>, что позволяет
      // сослаться на колонку таблицы в правой части присваивания.
      await (_database.update(_database.practices)
            ..where((t) => t.id.equals(practiceId)))
          .write(
        PracticesCompanion.custom(
          currentCount: _database.practices.currentCount + Variable(amount),
          updatedAt: Variable(DateTime.now()),
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
