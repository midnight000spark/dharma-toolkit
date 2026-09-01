/// Доменная модель особого календарного дня (FR-CAL-1).
///
/// Чистая доменная сущность: не Drift-таблица, не завязана на слой данных.
/// Персистентность (если понадобится) — отдельная таблица и маппинг,
/// см. решение блока 5 пакета 5b.
library;

/// Тип особого дня.
///
/// Замечание об extensibility: новый тип = значение enum + обработчики;
/// бонские праздники (будущее, D-30) попадают в [festival], специальные
/// бонские типы при необходимости добавляются — ядро о них не узнаёт.
enum SpecialDayType {
  /// Упосатха — день обета по фазе Луны (Тхеравада, FR-CAL-2).
  uposatha,

  /// 10-й день тибетского месяца (полусамоцветный день, FR-CAL-3).
  tibetan10,

  /// 25-й день тибетского месяца (полусамоцветный день, FR-CAL-3).
  tibetan25,

  /// Праздник (Лосар, Сага Дава и т.п.; для любой традиции).
  festival,
}

/// Особый день: конкретная григорианская дата с типом и человекочитаемым
/// описанием. Имя и описание — данные традиции (русский — единственный
/// язык продукта, D-28), а не ключи локализации: экраны Этапа 8 могут
/// переопределить вывод, домен остаётся источником канонических имён.
class SpecialDay {
  /// Григорианская дата (полночь локального календарного дня; время не
  /// значимо и нормализуется провайдером).
  final DateTime date;

  /// Тип особого дня.
  final SpecialDayType type;

  /// Отображаемое имя («Упосатха (полнолуние)», «Лосар — тибетский Новый год»).
  final String name;

  /// Пояснение для детали дня; может быть пустым.
  final String description;

  const SpecialDay({
    required this.date,
    required this.type,
    required this.name,
    this.description = '',
  });

  @override
  bool operator ==(Object other) =>
      other is SpecialDay &&
      other.date == date &&
      other.type == type &&
      other.name == name &&
      other.description == description;

  @override
  int get hashCode => Object.hash(date, type, name, description);

  @override
  String toString() =>
      'SpecialDay(${date.toIso8601String().substring(0, 10)} $type $name)';
}
