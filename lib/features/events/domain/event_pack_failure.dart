/// Причина, по которой пак событий не доехал до модели (W24).
///
/// Тип живёт в домене, а не в `data`-загрузчике: потребитель сбоев —
/// доменный [EventFeedService] (`packFailures` → `EventFeed.notes`), а слой
/// domain не вправе зависеть от data. Загрузчик (`data/event_pack_loader.dart`)
/// создаёт записи и реэкспортирует тип для совместимости публичного API.
library;

/// Почему конкретный пак не доехал до модели.
class EventPackFailure {
  /// Ключ ассета, на котором споткнулись.
  final String assetKey;

  /// Причина для человека (ассет/JSON/схема — с путём поля).
  final String reason;

  const EventPackFailure(this.assetKey, this.reason);

  @override
  String toString() => '$assetKey: $reason';
}
