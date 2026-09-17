/// Лента контента на окно дней (FR-CNT-1…4, блок B пакета 7.0).
///
/// Слияние здесь ровно одно: **день окна → чтения дня**. Логика выбора текста
/// живёт в [DailyReadingService] и не дублируется — иначе «чтение дня» на
/// дашборде и в ленте разошлось бы (класс дефектов «два источника истины»,
/// B-4/R-20). Сервис лишь разворачивает день-функцию на окно и собирает
/// пояснения.
///
/// Список паков приходит **данными** — из `preset.contentPacks` активного
/// пресета (поле уже в схеме пресета, D-9); загрузка ассетов — дело загрузчика
/// (блок A), не домена. Пустой список легален: это честное «контента пока нет»,
/// на которое отвечает фолбэк FR-CNT-3.
library;

import '../../../core/calendar/special_days_source.dart';
import '../data/content_pack_loader.dart';
import 'content_feed.dart';
import 'content_pack.dart';
import 'content_reading.dart';
import 'daily_reading_service.dart';

/// Разворачивает чтения дня на окно «сегодня + N дней».
class ContentFeedService {
  const ContentFeedService({
    required this.traditionTag,
    required this.packs,
    this.source,
    this.packFailures = const [],
  });

  /// Тег активного пресета (принцип №3) — отбор паков и атрибуция.
  final String traditionTag;

  /// Ранее загруженные паки (в порядке объявления в пресете).
  final List<ContentPack> packs;

  /// Источник тибетских дат активной традиции (для правила `tibetan`).
  final SpecialDaysSource? source;

  /// Сбои загрузки паков (блок A) — попадают в [ContentFeed.notes] как есть:
  /// пользователь видит «пак не прочитан», а не тихую пустоту.
  final List<ContentPackFailure> packFailures;

  /// Окно по умолчанию: сегодня + 7 дней **включительно** (8 календарных дней) —
  /// та же граница, что у ленты событий (сегодня + 30 включительно), только
  /// короче: контент ротируется ежедневно.
  static const Duration defaultWindow = Duration(days: 7);

  /// Построить ленту на [today] (время аргумента не значимо).
  ContentFeed build({required DateTime today, Duration window = defaultWindow}) {
    final service = DailyReadingService(
      traditionTag: traditionTag,
      packs: packs,
      source: source,
    );

    final from = DateTime(today.year, today.month, today.day);
    final to = DateTime(from.year, from.month, from.day + window.inDays);

    final days = <DailyReadings>[];
    final notes = <String>[];

    // Идём по календарю, а не по «дню + Duration(days: 1)»: при переходе на
    // летнее время сутки бывают не 24 часа, и приращение длительностью
    // пропустило бы день или повторило его (класс B-17).
    for (var date = from;
        !date.isAfter(to);
        date = DateTime(date.year, date.month, date.day + 1)) {
      final day = service.readingsFor(date);
      days.add(day);
      _mergeNotes(notes, day.notes);
    }

    for (final failure in packFailures) {
      _mergeNotes(notes, ['Пак не загружен (${failure.assetKey}): ${failure.reason}']);
    }

    return ContentFeed(days: days, notes: notes);
  }

  /// Пояснения без дублей: одна и та же причина (например, «пак не подтверждён»)
  /// звучит для каждого дня окна, но пользователю нужна один раз.
  static void _mergeNotes(List<String> target, List<String> source) {
    for (final note in source) {
      if (!target.contains(note)) target.add(note);
    }
  }
}
