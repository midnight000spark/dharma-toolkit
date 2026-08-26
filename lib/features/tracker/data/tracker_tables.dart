import 'package:drift/drift.dart';

/// Таблица практик (трекеров)
class Practices extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get presetId => text().nullable()(); // ID пресета (для пресетных трекеров)
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
class CountHistory extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get practiceId => integer().references(Practices, #id)();
  IntColumn get count => integer()();            // сколько добавили
  DateTimeColumn get timestamp => dateTime().withDefault(currentDateAndTime)();
  TextColumn get note => text().nullable()();    // опциональная заметка
}
