/// Чтение дня из контент-паков активной традиции (FR-CNT-1/3, блок B пакета 7.0).
///
/// Сервис — чистая доменная функция над уже загруженными данными: паки приходят
/// моделями (загрузчик, блок A), календарь — через порт ядра
/// ([SpecialDaysSource], D-37 — он нужен правилу `tibetan`). Ни платформы, ни
/// БД, ни UI внутри нет: «сегодня» приходит аргументом, поэтому результат
/// детерминирован и проверяем без fake-async и без виджетов (урок 5).
///
/// **Порядок чтений дня** — не деталь оформления, а правило честности:
///  1. **привязанные к дате** (`dateRule`) — первыми: если пак объявил текст на
///     этот день, именно он и есть чтение дня, а не то, что выпало ротацией;
///  2. **ротация пула** (записи без `dateRule`) — альтернатива для кнопки
///     «Другое чтение» (SCR-13): контент ротируется ежедневно;
///  3. **фолбэк FR-CNT-3** — единственное чтение, когда контента нет вовсе.
///
/// Ротация детерминирована ([ContentRotation]) — «случайность» чтения дня не
/// имеет права зависеть от раннера.
///
/// **Изоляция данных (принцип №3):** пак чужой традиции не берётся вовсе, даже
/// если он объявлен в пресете по ошибке, — и об этом сообщается в [notes], а не
/// молчанием.
library;

import '../../../core/calendar/special_days_source.dart';
import '../../../../core/content/daily_reading.dart';
import 'content_fallbacks.dart';
import 'content_pack.dart';
import 'content_rotation.dart';
import 'daily_readings.dart';

/// Собирает чтения конкретного дня из паков активной традиции.
class DailyReadingService {
  const DailyReadingService({
    required this.traditionTag,
    required this.packs,
    this.source,
  });

  /// Тег активного пресета (принцип №3): по нему отбираются паки. Ни одного
  /// литерала традиции внутри — значение приходит данными (B-4).
  final String traditionTag;

  /// Ранее загруженные паки (в порядке объявления в пресете).
  final List<ContentPack> packs;

  /// Источник тибетских дат активной традиции; `null` — календаря в сборке нет
  /// (тогда правило `tibetan` неразрешимо, и это честно сообщается).
  final SpecialDaysSource? source;

  /// Чтения дня [day] (время аргумента не значимо).
  DailyReadings readingsFor(DateTime day) {
    final date = DateTime(day.year, day.month, day.day);
    final notes = <String>[];
    final readings = <ContentReading>[];

    final active = _activePacks(notes);
    _addDateBound(date, active, readings, notes);
    _addRotated(date, active, readings);

    if (readings.isEmpty) {
      readings.add(_fallback(date));
      notes.add(ContentFallbacks.note);
    }

    return DailyReadings(date: date, readings: readings, notes: notes);
  }

  /// Паки активной традиции; чужой тег — пропуск с причиной (изоляция, №3).
  List<ContentPack> _activePacks(List<String> notes) {
    final active = <ContentPack>[];
    for (final pack in packs) {
      if (pack.traditionTag != traditionTag) {
        notes.add('Контент-пак «${pack.packId}» относится к традиции '
            '«${pack.traditionTag}» — пропущен (изоляция данных).');
        continue;
      }
      if (!pack.verified) {
        notes.add('Контент-пак «${pack.packId}» не подтверждён: его тексты '
            'помечены как непроверенные.');
      }
      active.add(pack);
    }
    return active;
  }

  void _addDateBound(DateTime date, List<ContentPack> active,
      List<ContentReading> readings, List<String> notes) {
    for (final pack in active) {
      for (final entry in pack.entries) {
        final rule = entry.dateRule;
        if (rule == null) continue;
        if (_matches(rule, date, notes, pack, entry)) {
          readings.add(_readingOf(pack, entry, date, isDateBound: true));
        }
      }
    }
  }

  /// Выпадает ли правило [rule] на день [date]; неразрешимость — в [notes],
  /// а не молчаливый пропуск (SCR-13 показывает причину, см. FR-CNT-3).
  bool _matches(ContentDateRule rule, DateTime date, List<String> notes,
      ContentPack pack, ContentEntry entry) {
    switch (rule) {
      case GregorianYearlyContentDateRule(:final month, :final day):
        return date.month == month && date.day == day;

      case TibetanContentDateRule(:final month, :final day):
        final calendar = source;
        if (calendar == null) {
          notes.add('Чтение «${entry.title}» пака «${pack.packId}» пропущено: '
              'правило tibetan требует календаря традиции, а его в сборке нет.');
          return false;
        }
        final resolved = calendar.resolveTibetanMonthDay(
          month: month,
          day: day,
          from: date,
          to: date,
        );
        if (resolved == null) {
          notes.add('Чтение «${entry.title}» пака «${pack.packId}» пропущено: '
              'календарь традиции «$traditionTag» тибетских дат не знает.');
          return false;
        }
        return resolved.contains(date);
    }
  }

  /// Одна запись ротации из пула записей без правила даты.
  void _addRotated(DateTime date, List<ContentPack> active,
      List<ContentReading> readings) {
    final pool = <(ContentPack, ContentEntry)>[];
    for (final pack in active) {
      for (final entry in pack.entries) {
        if (entry.dateRule == null) pool.add((pack, entry));
      }
    }
    if (pool.isEmpty) return;

    final (pack, entry) = pool[ContentRotation.indexForDay(date, pool.length)];
    readings.add(_readingOf(pack, entry, date, isDateBound: false));
  }

  ContentReading _readingOf(ContentPack pack, ContentEntry entry, DateTime date,
          {required bool isDateBound}) =>
      ContentReading(
        date: date,
        title: entry.title,
        body: entry.body,
        // Атрибуция обязательна: `packId` отвечает на «откуда текст», `source`
        // записи — на «чья это редакция/перевод» (FR-CNT-4).
        attribution: 'пак «${pack.packId}» · ${entry.source}',
        isVerified: pack.verified,
        source: ContentReadingSource.pack,
        isDateBound: isDateBound,
        packId: pack.packId,
        entryId: entry.id,
      );

  ContentReading _fallback(DateTime date) => ContentReading(
        date: date,
        title: ContentFallbacks.title,
        body: ContentFallbacks.forDay(date),
        attribution: ContentFallbacks.attribution,
        isVerified: false,
        source: ContentReadingSource.fallback,
      );
}
