/// События изменения настроек уведомлений (D-21, пакет 6.2).
///
/// Второй триггер перепланирования по D-36: правка «включено»/времени меняет
/// весь план напоминаний. Публикует событие хранилище настроек в момент
/// записи, принимает перепланировщик фичи событий.
library;

import 'app_event.dart';

/// Настройки уведомлений традиции записаны или сброшены.
class NotificationSettingsChanged extends AppEvent {
  /// [traditionTag] — чей пресет затронут (ключ изоляции данных,
  /// принцип №3; значение — тег пресета `preset.id`, W4/S6).
  NotificationSettingsChanged({required this.traditionTag, DateTime? timestamp})
      : timestamp = timestamp ?? DateTime.now();

  /// Тег пресета, к настройкам которого обратились (имя поля историческое;
  /// значение — `preset.id`, W4/S6).
  final String traditionTag;

  @override
  final DateTime timestamp;

  @override
  String toString() => 'NotificationSettingsChanged("$traditionTag")';
}
