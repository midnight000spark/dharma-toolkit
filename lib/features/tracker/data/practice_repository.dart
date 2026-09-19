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

  /// Стрим практики по ID (D-16, I-1).
  ///
  /// Реактивный доступ к одной практике. Если практика удалена или не
  /// существует, стрим эмитит `null` — это лекарство от B-6 (вечный спиннер):
  /// экран получает явное состояние «не найдена» вместо неопределённого
  /// Future, который мог упасть с исключением.
  Stream<PracticeEntity?> watchById(int id) {
    return (_database.select(_database.practices)
          ..where((t) => t.id.equals(id)))
        .watchSingleOrNull()
        .map((row) => row == null ? null : PracticeEntity.fromRow(row));
  }

  /// Создать новую практику.
  ///
  /// `createdAt`/`updatedAt` из entity передаются явно (B-10): при массовой
  /// вставке из пресета порядок строк определяется именно ими (список
  /// отсортирован по createdAt), а будущий импорт бэкапа обязан сохранять
  /// чужие даты. Drift хранит DateTime с точностью до секунды (F-33).
  ///
  /// Пресетные строки здесь не создаются: [PracticeEntity.presetId] обязан
  /// быть `null` (см. ниже). Причина — инвариант C4/D-45.
  Future<int> create(PracticeEntity practice) async {
    // Инвариант C4 (D-45): пресетную строку создаёт только материализация
    // `PresetManager._materializePractices` — она одна пишет и `preset_id`, и
    // `preset_practice_id`. Строка с `preset_id` без `preset_practice_id`
    // невидима upsert-ключу (tradition_tag, preset_practice_id), а уникальный
    // индекс SQLite на NULL не конфликтует → первый же applyPreset кладёт к
    // ней двойника и счёт рассепляется. Держать границу на слое записи
    // дешевле, чем лечить веткой v5 состояние, которого код породить не может:
    // за всю историю репозитория (21ef531) вызывающий экран (796e5c8) presetId
    // не передавал, а материализация (5805f5d) пишет обе колонки с первого
    // коммита.
    if (practice.presetId != null) {
      throw ArgumentError.value(
        practice.presetId,
        'practice.presetId',
        'практики из пресета создаёт PresetManager.applyPreset — только он '
            'проставляет preset_practice_id; прямой create оставил бы строку '
            'без стабильного id (C4, D-45)',
      );
    }

    return await _database.into(_database.practices).insert(
          PracticesCompanion.insert(
            presetId: Value(practice.presetId),
            name: practice.name,
            type: practice.type,
            target: Value(practice.target),
            unit: Value(practice.unit),
            traditionTag: practice.traditionTag,
            currentCount: Value(practice.currentCount),
            createdAt: Value(practice.createdAt),
            updatedAt: Value(practice.updatedAt),
          ),
        );
  }

  /// Атомарно увеличить счётчик практики на [amount] (I-2, B-8).
  ///
  /// Один `UPDATE ... SET current_count = current_count + ?` вместо
  /// read-modify-write: нет гонки при быстром тапе (B-8), нет лишнего
  /// чтения. Запись в историю — в той же транзакции.
  ///
  /// [amount] обязан быть строго положительным: отрицательный инкремент —
  /// это не «ошибочный тап», а тихая потеря счёта, и запись «−50000» в
  /// историю выглядит легальной (R-23). Гард живёт на слое репозитория, а не
  /// только в экране (урок 3): любой будущий вызывающий — импорт бэкапа,
  /// синк, новый виджет — получает исключение вместо порчи данных.
  ///
  /// Бросает [ArgumentError], если [amount] <= 0. Проверка стоит до открытия
  /// транзакции: невалидный вызов не должен оставлять следов в БД.
  Future<void> incrementCount(int practiceId, int amount) async {
    if (amount <= 0) {
      throw ArgumentError.value(amount, 'amount', 'must be positive');
    }

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
