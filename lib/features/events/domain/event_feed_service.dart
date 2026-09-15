/// Слияние календаря и паков событий в ленту (FR-EVT-1, блок C пакета 6.1).
///
/// Сервис — чистая доменная функция над уже загруженными данными: календарь
/// приходит через порт ядра ([SpecialDaysSource], D-37), паки — моделями
/// (загрузчик, блок B). Ни платформы, ни БД, ни UI внутри нет: «сегодня»
/// передаётся аргументом, поэтому результат детерминирован и проверяем без
/// fake-async и без виджетов (урок 5).
///
/// **Окно выдачи:** по умолчанию сегодня + 30 дней **включительно** (то есть
/// записи с сегодняшнего дня по день `today + 30`). D-35/D-36 другого окна
/// ленты не предписывают: 60 дней в D-36 — горизонт *уведомлений*, а не ленты,
/// поэтому это отдельная ручка с общим механизмом (планировщик в блоке D
/// использует свою). Окно параметризуемо — UI/планировщик задают своё.
///
/// **Совпадения дня не схлопываются:** упосатха и праздник пака в один день —
/// две записи с разными источниками. Схлопывание потеряло бы атрибуцию
/// (какая из них проверена?), а группировка по дню — задача UI (лента уже
/// отдаёт [EventFeed.on]).
library;

import '../../../core/calendar/special_days_source.dart';
import '../data/event_pack_loader.dart';
import 'event_feed.dart';
import 'event_pack.dart';
import 'feed_entry.dart';

/// Строит ленту из особых дней календаря и записей паков.
class EventFeedService {
  const EventFeedService({
    required this.traditionTag,
    required this.source,
    required this.packs,
    this.packFailures = const [],
  });

  /// Тег активного пресета (принцип №3): по нему отбираются паки и строится
  /// атрибуция. Ни одного литерала традиции внутри — значение приходит данными.
  final String traditionTag;

  /// Источник особых дней активной традиции; `null` — календаря в сборке нет
  /// (деградация 4.1: лента покажет паки и скажет, чего нет).
  final SpecialDaysSource? source;

  /// Ранее загруженные паки (в порядке объявления в пресете).
  final List<EventPack> packs;

  /// Сбои загрузки паков (блок B) — попадают в [EventFeed.notes] как есть:
  /// пользователь видит «пак не прочитан», а не тихую пустоту.
  final List<EventPackFailure> packFailures;

  /// Окно по умолчанию: сегодня + 30 дней включительно.
  static const Duration defaultWindow = Duration(days: 30);

  /// Построить ленту на [today] (время аргумента не значимо).
  EventFeed build({required DateTime today, Duration window = defaultWindow}) {
    final from = DateTime(today.year, today.month, today.day);
    final to = DateTime(from.year, from.month, from.day + window.inDays);

    final notes = <String>[];
    final entries = <FeedEntry>[];

    _addCalendarDays(from, to, entries, notes);
    _addPackEntries(from, to, entries, notes);
    _addPackFailures(notes);

    entries.sort((a, b) {
      final byDate = a.date.compareTo(b.date);
      if (byDate != 0) return byDate;
      final bySource = a.source.index.compareTo(b.source.index);
      if (bySource != 0) return bySource;
      return a.title.compareTo(b.title);
    });

    return EventFeed(entries: entries, notes: notes);
  }

  void _addCalendarDays(DateTime from, DateTime to, List<FeedEntry> entries,
      List<String> notes) {
    final calendar = source;
    if (calendar == null) {
      notes.add('Календаря для активной традиции в сборке нет — '
          'показаны только события паков.');
      return;
    }
    for (final day in calendar.getSpecialDays(from, to)) {
      // Окно — обещание ленты: запись вне него не показывается, даже если
      // источник вернул шире своего контракта (лента не полагается на это
      // молча — урок «тихих» расхождений B-4/R-14).
      if (!_within(day.date, from, to)) continue;
      entries.add(FeedEntry(
        date: day.date,
        title: day.name,
        description: day.description,
        source: FeedEntrySource.calendar,
        attribution: 'календарь традиции «${calendar.traditionTag}»',
        // Дни движка сверены векторами (F-45); непроверенные даты обязаны
        // приходить паком с verified=false, а не выдаваться за вычисленные.
        isVerified: true,
        specialDayType: day.type,
      ));
    }
  }

  void _addPackEntries(DateTime from, DateTime to, List<FeedEntry> entries,
      List<String> notes) {
    for (final pack in packs) {
      if (pack.traditionTag != traditionTag) {
        notes.add('Пак «${pack.packId}» относится к традиции '
            '«${pack.traditionTag}» — пропущен (изоляция данных).');
        continue;
      }
      if (!pack.verified) {
        notes.add('Пак «${pack.packId}» не подтверждён: его даты помечены '
            'как непроверенные.');
      }
      for (final entry in pack.entries) {
        final dates = _datesFor(entry, from, to, notes, pack);
        for (final date in dates) {
          entries.add(FeedEntry(
            date: date,
            title: entry.name,
            description: entry.type,
            source: FeedEntrySource.pack,
            attribution: 'пак «${pack.packId}» · ${entry.source}',
            isVerified: pack.verified,
            packId: pack.packId,
            packEntryId: entry.id,
          ));
        }
      }
    }
  }

  /// Даты записи пака внутри окна; невозможность разрешить правило — [notes],
  /// не молчаливый пропуск (SCR-12).
  List<DateTime> _datesFor(EventPackEntry entry, DateTime from, DateTime to,
      List<String> notes, EventPack pack) {
    switch (entry.dateRule) {
      case GregorianYearlyDateRule(:final month, :final day):
        final result = <DateTime>[];
        // Годы, перекрывающие окно: обычно один, на стыке года — два.
        for (var year = from.year; year <= to.year; year++) {
          final date = DateTime(year, month, day);
          if (_within(date, from, to)) result.add(date);
        }
        return result;

      case TibetanDateRule(:final month, :final day):
        final calendar = source;
        if (calendar == null) {
          notes.add('Событие «${entry.name}» пака «${pack.packId}» пропущено: '
              'правило tibetan требует календаря традиции, а его в сборке нет.');
          return const [];
        }
        final resolved = calendar.resolveTibetanMonthDay(
          month: month,
          day: day,
          from: from,
          to: to,
        );
        if (resolved == null) {
          notes.add('Событие «${entry.name}» пака «${pack.packId}» пропущено: '
              'календарь традиции «$traditionTag» тибетских дат не знает.');
          return const [];
        }
        return [
          for (final date in resolved)
            if (_within(date, from, to)) date,
        ];
    }
  }

  void _addPackFailures(List<String> notes) {
    for (final failure in packFailures) {
      notes.add('Пак не загружен (${failure.assetKey}): ${failure.reason}');
    }
  }

  static bool _within(DateTime date, DateTime from, DateTime to) =>
      !date.isBefore(from) && !date.isAfter(to);
}
