/// План уведомлений: платформо-независимое описание того, что нужно показать
/// (FR-EVT-2, D-36; блок D пакета 6.1).
///
/// План не знает ни о вендоре, ни о таймзонах (`TZDateTime`, `zonedSchedule`,
/// `androidScheduleMode` — забота адаптера 6.2): здесь только локальные
/// дата-время, идентификаторы в выделенном диапазоне и полезная нагрузка.
/// Такое разделение — слой причины (урок 3): адаптер заменяем, а правила
/// планирования проверяются без плагина, включая Linux-разработку (F-57).
///
/// **Диапазон id 100000–199999 (D-36)** — «своя» полоса приложения: отмена
/// планирования идёт по ней и не трогает чужие уведомления.
library;

import 'dart:convert';

import 'event_feed_service.dart';
import 'feed_entry.dart';
import 'notification_settings.dart';

/// Одно запланированное напоминание.
class NotificationPlanItem {
  /// Идентификатор в полосе приложения (см. [NotificationPlan.idRangeStart]).
  final int id;

  /// Момент срабатывания — локальное время устройства (таймзону и
  /// `TZDateTime` подставит адаптер 6.2).
  final DateTime scheduledAt;

  /// Заголовок (название события).
  final String title;

  /// Текст уведомления.
  final String body;

  /// Полезная нагрузка для обработчика нажатия (JSON-строка; пустая строка —
  /// легальное «без деталей»: плагин передаёт null как пустую строку, F-55).
  final String payload;

  const NotificationPlanItem({
    required this.id,
    required this.scheduledAt,
    required this.title,
    required this.body,
    required this.payload,
  });

  @override
  String toString() =>
      'NotificationPlanItem(#$id ${scheduledAt.toIso8601String()} "$title")';
}

/// План уведомлений + честные пояснения, почему чего-то в нём нет.
class NotificationPlan {
  /// Пункты в порядке возрастания времени.
  final List<NotificationPlanItem> items;

  /// Причины: уведомления выключены, лента пуста, лимит pending исчерпан.
  final List<String> notes;

  const NotificationPlan({required this.items, required this.notes});

  /// Пустой план без пояснений.
  static const NotificationPlan empty =
      NotificationPlan(items: [], notes: []);

  /// Начало полосы id приложения (D-36).
  static const int idRangeStart = 100000;

  /// Конец полосы id приложения включительно (D-36).
  static const int idRangeEnd = 199999;

  /// Потолок одновременных pending под iOS-лимит 64 (F-57): горизонт D-36
  /// (60 дней) укладывается в него с запасом, а превышение — не молчаливая
  /// потеря, а пояснение (см. [notes]).
  static const int maxPending = 64;

  bool get isEmpty => items.isEmpty;

  bool get hasNotes => notes.isNotEmpty;

  @override
  String toString() => 'NotificationPlan(${items.length} пунктов)';
}

/// Строит план из ленты событий и настроек традиции (FR-EVT-3, D-36).
///
/// Горизонт — **60 дней вперёд** (D-36), лента строится с тем же окном: одно
/// место задаёт окно, поэтому план и лента не могут разойтись.
class NotificationPlanBuilder {
  const NotificationPlanBuilder({required this.feedService});

  /// Источник событий (лента строится этим же сервисом, тем же окном).
  final EventFeedService feedService;

  /// Горизонт планирования D-36.
  static const Duration defaultHorizon = Duration(days: 60);

  /// Собрать план на момент [now].
  ///
  /// Возвращает пустой план с пояснением, если уведомления выключены: это
  /// не ошибка, а честное «тихо» (UX-A-2, FR-EVT-4 — никаких «подогревающих»
  /// пушей в обход настройки).
  NotificationPlan build({
    required DateTime now,
    required NotificationSettings settings,
    Duration horizon = defaultHorizon,
  }) {
    if (!settings.enabled) {
      return const NotificationPlan(
        items: [],
        notes: ['Уведомления выключены в настройках — напоминания не планируются.'],
      );
    }

    final feed = feedService.build(today: now, window: horizon);
    final notes = <String>[...feed.notes];
    final items = <NotificationPlanItem>[];
    final seen = <String>{};
    var droppedForLimit = 0;
    var pastCount = 0;

    for (final entry in feed.entries) {
      final scheduledAt = DateTime(
        entry.date.year,
        entry.date.month,
        entry.date.day,
        settings.hour,
        settings.minute,
      );
      if (scheduledAt.isBefore(now)) {
        pastCount++;
        continue;
      }
      // Одно и то же уведомление в одну минуту не дублируется: две записи
      // ленты об одном дне с одинаковым названием (календарь + пак) дают один
      // показ — иначе пользователь получает шум, а «тихий» режим нарушен
      // (UX-A-2). Источник первой записи сохраняется.
      if (!seen.add('${scheduledAt.toIso8601String()}|${entry.title}')) {
        continue;
      }
      if (items.length >= NotificationPlan.maxPending) {
        droppedForLimit++;
        continue;
      }
      items.add(NotificationPlanItem(
        id: NotificationPlan.idRangeStart + items.length,
        scheduledAt: scheduledAt,
        title: entry.title,
        body: _bodyFor(entry),
        payload: _payloadFor(entry),
      ));
    }

    if (pastCount > 0) {
      notes.add('Событий уже прошедших на момент планирования: $pastCount.');
    }
    if (droppedForLimit > 0) {
      notes.add('В план не влезло событий (лимит '
          '${NotificationPlan.maxPending} ожидающих, F-57): $droppedForLimit.');
    }
    return NotificationPlan(items: items, notes: notes);
  }

  static String _bodyFor(FeedEntry entry) {
    final base = entry.description.isEmpty
        ? 'Особый день · ${entry.attribution}'
        : entry.description;
    // Непроверенная дата честно помечается и в уведомлении (UX-A-4/I-3):
    // «красиво» и «проверено» — разные вещи.
    return entry.isVerified ? base : '$base · дата не подтверждена';
  }

  static String _payloadFor(FeedEntry entry) => jsonEncode({
        'date': entry.date.toIso8601String().substring(0, 10),
        'source': entry.source.name,
        if (entry.packId != null) 'packId': entry.packId,
        if (entry.packEntryId != null) 'packEntryId': entry.packEntryId,
      });
}
