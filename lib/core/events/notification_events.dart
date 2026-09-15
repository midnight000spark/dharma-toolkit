/// События изменения настроек уведомлений (D-21, пакет 6.2).
///
/// Второй триггер перепланирования по D-36: правка «включено»/времени меняет
/// весь план напоминаний. Публикует событие хранилище настроек в момент
/// записи, принимает перепланировщик фичи событий.
library;

import 'app_event.dart';

/// Настройки уведомлений традиции записаны или сброшены.
class NotificationSettingsChanged extends AppEvent {
  /// [traditionTag] — чья традиция затронута (ключ изоляции данных,
  /// принцип №3).
  NotificationSettingsChanged({required this.traditionTag, DateTime? timestamp})
      : timestamp = timestamp ?? DateTime.now();

  /// Тег традиции, к настройкам которой обратились.
  final String traditionTag;

  @override
  final DateTime timestamp;

  @override
  String toString() => 'NotificationSettingsChanged("$traditionTag")';
}
