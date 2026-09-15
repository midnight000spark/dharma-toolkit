/// Хранилище настроек уведомлений (FR-EVT-3, D-36; таблица схемы v4).
///
/// Хранилище — тонкая обёртка над Drift: домен настроек берётся из
/// [NotificationSettings] (с проверкой диапазонов времени), строки читаются и
/// пишутся по тегу традиции (изоляция данных, принцип №3).
///
/// **Устойчивость к расхождению версий:** строка, записанная более новым
/// приложением, может содержать неизвестные значения. Такие значения обязаны
/// быть видимой ошибкой ([InvalidNotificationSettingsException]), а не молча
/// «исправленными» к ближайшей границе: скрытый клампинг — это тихая потеря
/// пользовательского выбора (R-23, урок 3).
///
/// Пустая таблица — штатное состояние: `read` отдаёт дефолт D-36
/// (включено, 08:00), а не ошибку.
library;

import 'package:drift/drift.dart';

import '../../../core/db/app_database.dart';
import '../../../core/events/event_bus.dart';
import '../../../core/events/notification_events.dart';
import '../domain/notification_settings.dart';

/// Чтение и запись настроек уведомлений по традициям.
class NotificationSettingsStore {
  NotificationSettingsStore(this._db, {this.eventBus});

  final AppDatabase _db;

  /// Шина для события «настройки изменились» (D-21/D-36).
  ///
  /// Необязательна: хранилище остаётся рабочим и без шины (тесты, утилитарное
  /// чтение), но тогда перепланирование на смену настроек не среагирует —
  /// поэтому в приложении шина передаётся composition root'ом.
  final EventBus? eventBus;

  /// Настройки традиции [traditionTag]; строки нет — дефолт D-36.
  Future<NotificationSettings> read(String traditionTag) async {
    final row = await (_db.select(_db.notificationSettingsRows)
          ..where((t) => t.traditionTag.equals(traditionTag)))
        .getSingleOrNull();
    if (row == null) return NotificationSettings.defaults;
    return _fromRow(row, traditionTag);
  }

  /// Поток настроек: перепланирование подписывается на него (D-36 — «смена
  /// настроек» один из триггеров). Первый эвент — текущее состояние
  /// (включая дефолт при отсутствии строки).
  Stream<NotificationSettings> watch(String traditionTag) => _db
      .select(_db.notificationSettingsRows)
      .watch()
      .map((rows) {
        final row = rows
            .where((r) => r.traditionTag == traditionTag)
            .firstOrNull;
        if (row == null) return NotificationSettings.defaults;
        return _fromRow(row, traditionTag);
      })
      .distinct();

  /// Записать настройки традиции (upsert по ключу-тегу).
  ///
  /// Значения уже проверены доменом: [NotificationSettings] невозможно
  /// сконструировать с часом/минутой вне диапазона.
  Future<void> write(String traditionTag, NotificationSettings settings) async {
    if (traditionTag.trim().isEmpty) {
      throw ArgumentError.value(
          traditionTag, 'traditionTag', 'тег традиции не может быть пустым');
    }
    await _db.into(_db.notificationSettingsRows).insertOnConflictUpdate(
          NotificationSettingsRowsCompanion.insert(
            traditionTag: traditionTag,
            enabled: Value(settings.enabled),
            hour: Value(settings.hour),
            minute: Value(settings.minute),
            updatedAt: Value(DateTime.now()),
          ),
        );
    eventBus?.publish(
        NotificationSettingsChanged(traditionTag: traditionTag));
  }

  /// Вернуть настройки традиции к дефолту (удаление строки).
  Future<void> reset(String traditionTag) async {
    await (_db.delete(_db.notificationSettingsRows)
          ..where((t) => t.traditionTag.equals(traditionTag)))
        .go();
    eventBus?.publish(
        NotificationSettingsChanged(traditionTag: traditionTag));
  }

  NotificationSettings _fromRow(
      NotificationSettingsRow row, String traditionTag) {
    try {
      return NotificationSettings(
        enabled: row.enabled,
        hour: row.hour,
        minute: row.minute,
      );
    } on InvalidNotificationSettingsException catch (e) {
      // Диагностика обязана называть традицию: иначе по логу не понять,
      // чья строка повреждена.
      throw InvalidNotificationSettingsException(
        e.field,
        '${e.reason} (традиция «$traditionTag», строка таблицы настроек)',
      );
    }
  }
}
