import 'package:drift/drift.dart';

/// Таблица практик (трекеров)
///
/// Уникальный индекс по паре `(tradition_tag, preset_practice_id)` гарантирует,
/// что повторное применение пресета не плодит дубли (B-3): upsert идёт по этой
/// паре. Для кастомных практик `preset_practice_id` равен NULL, а NULL-значения
/// в уникальном индексе SQLite не конфликтуют — кастомные трекеры индексу
/// не подчиняются.
@TableIndex(
  name: 'idx_practices_tradition_preset',
  columns: {#traditionTag, #presetPracticeId},
  unique: true,
)
class Practices extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get presetId => text().nullable()(); // ID пресета (для пресетных трекеров)
  TextColumn get presetPracticeId => text().nullable()(); // стабильный id практики из пресета (B-3)
  TextColumn get name => text()();               // "Простирания", "Мантра Ваджрасаттвы"
  TextColumn get type => text()();               // 'counter' или 'timer'
  IntColumn get target => integer().nullable()(); // целевое количество
  TextColumn get unit => text().nullable()();    // "повторений", "минут"
  TextColumn get traditionTag => text()();       // тег традиции для изоляции
  IntColumn get currentCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// Таблица истории счёта (для графиков и статистики)
///
/// `onDelete: KeyAction.cascade` — каскадное удаление истории вместе с
/// практикой (B-11). Работает только при включённом `PRAGMA foreign_keys`
/// (включается в `_openConnection`, см. I-2 пакета 5.0.2).
class CountHistory extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get practiceId =>
      integer().references(Practices, #id, onDelete: KeyAction.cascade)();
  IntColumn get count => integer()();            // сколько добавили
  DateTimeColumn get timestamp => dateTime().withDefault(currentDateAndTime)();
  TextColumn get note => text().nullable()();    // опциональная заметка
}
