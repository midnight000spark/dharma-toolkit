/// Настройки уведомлений традиции (FR-EVT-3, D-36).
///
/// Область действия — **традиция**: ключ изоляции — `traditionTag` активного
/// пресета (принцип №3), поэтому у каждой традиции своё «включено» и своё время.
///
/// Дефолт (D-36): **включено, 08:00 локального времени** — напоминание, а не
/// будильник (UX-A-2). Никаких «геймификационных» полей здесь нет: настройка
/// управляет только показом календарно значимых дней (FR-EVT-4).
///
/// **Валидация на слое причины** (урок 3, R-23): невалидное время — ошибка
/// здесь, а не клампинг в UI и не «молча 00:00» в хранилище. Значение вне
/// домена, прочитанное из БД (например, час 99 после порчи данных), обязано
/// всплыть ошибкой, а не превратиться в «какое-то» время.
library;

/// Настройки уведомлений невалидны: названо поле и причина.
class InvalidNotificationSettingsException implements Exception {
  /// Имя проблемного поля (`hour`, `minute`).
  final String field;

  /// Почему значение не принято.
  final String reason;

  const InvalidNotificationSettingsException(this.field, this.reason);

  @override
  String toString() =>
      'Настройки уведомлений невалидны: поле "$field" — $reason';
}

/// Настройки уведомлений одной традиции.
class NotificationSettings {
  /// Показывать ли уведомления вообще (FR-EVT-3).
  final bool enabled;

  /// Час срабатывания, 0..23 (локальное время устройства).
  final int hour;

  /// Минута срабатывания, 0..59.
  final int minute;

  /// Дефолт D-36: включено, 08:00.
  static const NotificationSettings defaults =
      NotificationSettings._(enabled: true, hour: 8, minute: 0);

  const NotificationSettings._({
    required this.enabled,
    required this.hour,
    required this.minute,
  });

  /// Создать настройки с проверкой домена.
  ///
  /// Бросает [InvalidNotificationSettingsException] при часе/минуте вне
  /// диапазона: молчаливое «привести к ближайшему» спрятало бы дефект данных.
  factory NotificationSettings({
    required bool enabled,
    required int hour,
    required int minute,
  }) {
    if (hour < 0 || hour > 23) {
      throw InvalidNotificationSettingsException(
          'hour', 'ожидался 0..23, получено $hour');
    }
    if (minute < 0 || minute > 59) {
      throw InvalidNotificationSettingsException(
          'minute', 'ожидался 0..59, получено $minute');
    }
    return NotificationSettings._(
        enabled: enabled, hour: hour, minute: minute);
  }

  /// Настройки с изменёнными полями (для UI-переключателей).
  NotificationSettings copyWith({bool? enabled, int? hour, int? minute}) =>
      NotificationSettings(
        enabled: enabled ?? this.enabled,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
      );

  @override
  bool operator ==(Object other) =>
      other is NotificationSettings &&
      other.enabled == enabled &&
      other.hour == hour &&
      other.minute == minute;

  @override
  int get hashCode => Object.hash(enabled, hour, minute);

  @override
  String toString() => enabled
      ? 'NotificationSettings(вкл, '
          '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')})'
      : 'NotificationSettings(выкл)';
}
