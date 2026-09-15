import 'package:drift/drift.dart';

/// Настройки уведомлений по традициям (FR-EVT-3, D-36; схема v4).
///
/// **Ключ — `tradition_tag`** (принцип №3, изоляция данных): у каждой традиции
/// своё «включено» и своё время. Строка создаётся при первом изменении
/// настроек; отсутствие строки означает «пользователь не настраивал» и
/// читается как дефолт D-36 (включено, 08:00) — см.
/// `NotificationSettingsStore.read`.
///
/// Значения хранятся «как есть»: диапазоны (0..23 / 0..59) проверяет домен
/// ([NotificationSettings]) на чтении и записи, а не CHECK-констрейнт: ошибка
/// обязана быть видимой (R-23), а не «тихо отклонённой вставкой».
@TableIndex(name: 'idx_notification_settings_tradition', columns: {#traditionTag})
class NotificationSettingsRows extends Table {
  /// Имя SQL-таблицы задано явно: Drift по умолчанию вывел бы его из имени
  /// класса (`notification_settings_rows`), а BFT/D-36 называют таблицу
  /// `notification_settings`. Переопределение геттера — поддерживаемый способ
  /// (drift 2.34.3, `lib/src/dsl/table.dart`).
  @override
  String get tableName => 'notification_settings';

  /// Тег традиции активного пресета (`preset.id`) — ключ строки.
  TextColumn get traditionTag => text()();

  /// Показывать ли уведомления (FR-EVT-3).
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();

  /// Час срабатывания, 0..23 (локальное время).
  IntColumn get hour => integer().withDefault(const Constant(8))();

  /// Минута срабатывания, 0..59.
  IntColumn get minute => integer().withDefault(const Constant(0))();

  /// Когда настройки последний раз менялись (для диагностики).
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {traditionTag};
}
