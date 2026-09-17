/// Доменная модель контент-пака (FR-CNT-1/2/4).
///
/// Пак — **данные, не код** (принцип №2): JSON-ассет, объявленный в пресете
/// (`contentPacks` пресета, поле уже есть в схеме — D-9), а не таблица БД и не
/// хардкод. Схема v1 минимальна по прецеденту пака событий (D-35): расширение —
/// next-version, не мутирование схемы.
///
/// Схема v1:
/// ```json
/// {
///   "packId": "synthetic_example",
///   "traditionTag": "nyingma",
///   "version": "1",
///   "verified": false,
///   "entries": [
///     {"id": "c1", "type": "daily_reading", "title": "…", "body": "…",
///      "source": "…",
///      "dateRule": {"kind": "gregorian_yearly", "month": 1, "day": 1}}
///   ]
/// }
/// ```
///
/// **Атрибуция — обязательная часть модели, а не украшение.** [ContentEntry.source]
/// — не «опциональное поле на будущее», а механизм соблюдения авторских прав
/// (FR-CNT-4, P0) и честности перед пользователем (UX-A-4): текст без
/// происхождения неотличим от выдуманного, а для текстовой практики это тот же
/// класс вранья, что непроверенная дата. Поэтому `source` обязателен и непуст;
/// [ContentPack.verified] несёт второй уровень честности — подтверждён ли пак
/// эталоном/первоисточником целиком.
///
/// При этом **текст — не дата**: отсутствие `dateRule` у записи легально и
/// осмысленно (ротация по пулу, FR-CNT-1), тогда как отсутствие `dateRule` у
/// события бессмысленно. Поэтому `dateRule` здесь опционален, а не обязателен,
/// как в паке событий.
library;

/// Вид правила даты контент-записи — закрытое перечисление на v1.
///
/// Закрытость намеренная (как `EventDateRuleKind` в D-35): неизвестный `kind` —
/// не «проглотим молча», а ошибка формата. Иначе опечатка в правиле превратила
/// бы привязанное чтение в запись, которая никогда не покажется (класс дефектов
/// B-4/R-14 — «данные есть, но недостижимы»).
enum ContentDateRuleKind {
  /// Тибетский день месяца по активному календарю (например, 10-й день).
  tibetan,

  /// Фиксированная дата григорианского года (месяц/день, год вычисляется).
  gregorianYearly,
}

/// Правило привязки контент-записи к дате.
///
/// Разрешение правила в конкретный день делается не здесь, а через контракт
/// календаря ядра: пак описывает **намерение** («показать 10-го числа тибетского
/// месяца»), а не вычисляет дату сам.
sealed class ContentDateRule {
  const ContentDateRule();

  /// Вид правила (ключ схемы).
  ContentDateRuleKind get kind;
}

/// `{"kind": "tibetan", "month": M, "day": D}` — M/D тибетского месяца.
class TibetanContentDateRule extends ContentDateRule {
  /// Месяц тибетского календаря, 1..12.
  final int month;

  /// День тибетского месяца, 1..30.
  final int day;

  const TibetanContentDateRule({required this.month, required this.day});

  @override
  ContentDateRuleKind get kind => ContentDateRuleKind.tibetan;

  @override
  bool operator ==(Object other) =>
      other is TibetanContentDateRule &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(kind, month, day);

  @override
  String toString() => 'TibetanContentDateRule($month/$day)';
}

/// `{"kind": "gregorian_yearly", "month": M, "day": D}` — фиксированная дата
/// григорианского года (год не хранится: правило повторяется ежегодно).
class GregorianYearlyContentDateRule extends ContentDateRule {
  /// Месяц, 1..12.
  final int month;

  /// День месяца, 1..31 (проверяется по длине месяца).
  final int day;

  const GregorianYearlyContentDateRule({
    required this.month,
    required this.day,
  });

  @override
  ContentDateRuleKind get kind => ContentDateRuleKind.gregorianYearly;

  @override
  bool operator ==(Object other) =>
      other is GregorianYearlyContentDateRule &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(kind, month, day);

  @override
  String toString() => 'GregorianYearlyContentDateRule($month/$day)';
}

/// Одна запись пака: текст с атрибуцией и необязательной привязкой к дате.
class ContentEntry {
  /// Уникальный идентификатор внутри пака (ключ записи).
  final String id;

  /// Категория записи — **открытая строка на v1**: D-35 закрывает перечислением
  /// только `dateRule.kind`, поэтому закрывать категорию здесь значило бы
  /// доизобретать схему. Валидируется как непустая строка; закрытый перечень
  /// (`daily_reading` | `quote` | `sutra`) — вопрос следующей версии схемы, а
  /// не мутации v1.
  final String type;

  /// Заголовок записи (русский — единственный язык продукта, D-28: заголовок
  /// есть данные пака, не ключ локализации).
  final String title;

  /// Текст записи — то, что видит пользователь.
  final String body;

  /// Происхождение текста: издание, перевод, лицензия (FR-CNT-4, UX-A-4).
  ///
  /// Обязательно и непусто: текст без источника неотличим от выдуманного.
  final String source;

  /// Необязательная привязка к дате. `null` — запись живёт в пуле ротации.
  final ContentDateRule? dateRule;

  const ContentEntry({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.source,
    this.dateRule,
  });

  @override
  bool operator ==(Object other) =>
      other is ContentEntry &&
      other.id == id &&
      other.type == type &&
      other.title == title &&
      other.body == body &&
      other.source == source &&
      other.dateRule == dateRule;

  @override
  int get hashCode => Object.hash(id, type, title, body, source, dateRule);
}

/// Контент-пак: набор записей одной традиции с признаком подтверждённости.
class ContentPack {
  /// Идентификатор пака (ключ: два пака с одним `packId` создают
  /// двусмысленность атрибуции — загрузчик такие отвергает).
  final String packId;

  /// Тег традиции привязки (принцип №3): значение — из данных пака, в коде
  /// не захардкожено.
  final String traditionTag;

  /// Версия схемы/данных пака (строка — как `version` пресета и пака событий:
  /// три схемы в одном репозитории обязаны читаться одинаково).
  final String version;

  /// Честный флаг: пак подтверждён первоисточником/эталоном. `false` — UI обязан
  /// показать «источник не проверен», а не подавать запись как проверенную.
  final bool verified;

  /// Записи пака (может быть пустым: пак-заготовка с `verified: false` легален —
  /// он честно ничего не обещает).
  final List<ContentEntry> entries;

  const ContentPack({
    required this.packId,
    required this.traditionTag,
    required this.version,
    required this.verified,
    required this.entries,
  });

  @override
  String toString() =>
      'ContentPack($packId, ${entries.length} записей, verified=$verified)';
}
