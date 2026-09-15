/// Доменная модель пака событий (FR-EVT-1, D-35).
///
/// Пак — **данные, не код** (принцип №2): JSON-ассет, объявленный в пресете
/// (`eventPacks`), а не таблица БД и не хардкод. Схема v1 минимальна, как D-9
/// для пресетов; расширение — next-version, не мутирование схемы.
///
/// Схема v1 (D-35):
/// ```json
/// {
///   "packId": "synthetic_example",
///   "traditionTag": "nyingma",
///   "version": "1",
///   "verified": false,
///   "entries": [
///     {"id": "e1", "type": "festival", "name": "…",
///      "dateRule": {"kind": "tibetan", "month": 1, "day": 1},
///      "source": "…"}
///   ]
/// }
/// ```
///
/// **Атрибуция — обязательная часть модели, а не украшение:** [EventPackEntry.source]
/// хранит происхождение даты, [EventPack.traditionTag] — тег привязки (тот же
/// механизм изоляции, что у практик пресета — принцип №3), [EventPack.verified] —
/// честный флаг полноты/подтверждённости пака (UX-A-4/I-3: «непроверенный» пак
/// обязан говорить об этом в UI, а не выглядеть «красиво»).
library;

/// Вид правила даты — закрытое перечисление на v1 (D-35).
///
/// Закрытость намеренная: неизвестный `kind` — не «проглотим молча», а ошибка
/// формата. Иначе опечатка в правиле превратилась бы в тихо пропущенный
/// праздник (ровно тот класс дефектов, что закрывали B-4/R-14).
enum EventDateRuleKind {
  /// Тибетский день месяца по активному календарю (например, 1/1 — Лосар).
  tibetan,

  /// Фиксированная дата григорианского года (месяц/день, год вычисляется).
  gregorianYearly,
}

/// Правило вычисления даты события.
sealed class EventDateRule {
  const EventDateRule();

  /// Вид правила (ключ схемы).
  EventDateRuleKind get kind;
}

/// `{"kind": "tibetan", "month": M, "day": D}` — M/D тибетского месяца.
class TibetanDateRule extends EventDateRule {
  /// Месяц тибетского календаря, 1..12.
  final int month;

  /// День тибетского месяца, 1..30.
  final int day;

  const TibetanDateRule({required this.month, required this.day});

  @override
  EventDateRuleKind get kind => EventDateRuleKind.tibetan;

  @override
  bool operator ==(Object other) =>
      other is TibetanDateRule && other.month == month && other.day == day;

  @override
  int get hashCode => Object.hash(kind, month, day);

  @override
  String toString() => 'TibetanDateRule($month/$day)';
}

/// `{"kind": "gregorian_yearly", "month": M, "day": D}` — фиксированная дата
/// григорианского года (год не хранится: правило повторяется ежегодно).
class GregorianYearlyDateRule extends EventDateRule {
  /// Месяц, 1..12.
  final int month;

  /// День месяца, 1..31 (проверяется по длине месяца).
  final int day;

  const GregorianYearlyDateRule({required this.month, required this.day});

  @override
  EventDateRuleKind get kind => EventDateRuleKind.gregorianYearly;

  @override
  bool operator ==(Object other) =>
      other is GregorianYearlyDateRule &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(kind, month, day);

  @override
  String toString() => 'GregorianYearlyDateRule($month/$day)';
}

/// Одна запись пака: событие с правилом даты и атрибуцией источника.
class EventPackEntry {
  /// Уникальный идентификатор внутри пака (ключ записи).
  final String id;

  /// Категория события — **открытая строка на v1**: D-35 закрывает перечислением
  /// только `dateRule.kind`, поэтому закрывать категорию здесь значило бы
  /// доизобретать схему. Валидируется как непустая строка; закрытый перечень —
  /// вопрос следующей версии схемы, а не мутации v1.
  final String type;

  /// Человекочитаемое русское имя события (D-28: русский — единственный язык
  /// продукта; имя — данные пака, не ключ локализации).
  final String name;

  /// Правило вычисления даты.
  final EventDateRule dateRule;

  /// Происхождение даты (атрибуция эталонов) — обязательна: дата без
  /// источника неотличима от выдуманной (UX-A-4).
  final String source;

  const EventPackEntry({
    required this.id,
    required this.type,
    required this.name,
    required this.dateRule,
    required this.source,
  });

  @override
  bool operator ==(Object other) =>
      other is EventPackEntry &&
      other.id == id &&
      other.type == type &&
      other.name == name &&
      other.dateRule == dateRule &&
      other.source == source;

  @override
  int get hashCode => Object.hash(id, type, name, dateRule, source);
}

/// Пак событий: набор записей одной традиции с признаком подтверждённости.
class EventPack {
  /// Идентификатор пака (ключ: два пака с одним `packId` создают двусмысленность
  /// атрибуции — загрузчик такие отвергает).
  final String packId;

  /// Тег традиции привязки (принцип №3): значение — из данных пака, в коде
  /// не захардкожено.
  final String traditionTag;

  /// Версия схемы/данных пака (строка, как `version` пресета).
  final String version;

  /// Честный флаг: даты пака подтверждены эталоном. `false` — UI обязан
  /// показать «дата пока не проверена», а не выдавать запись за проверенную.
  final bool verified;

  /// Записи пака (может быть пустым: пак-заготовка с `verified: false`
  /// легален — он честно ничего не обещает).
  final List<EventPackEntry> entries;

  const EventPack({
    required this.packId,
    required this.traditionTag,
    required this.version,
    required this.verified,
    required this.entries,
  });

  @override
  String toString() =>
      'EventPack($packId, ${entries.length} записей, verified=$verified)';
}
