/// DI-регистрация календарей традиции (D-22; пакеты 5b.3 блок 5, 5b.4 блок 2).
///
/// Реализации живут как чистые классы (конструктор с traditionTag); этот
/// файл поднимает их в Riverpod — единственную DI-систему проекта.
///
/// Выбор реализации (5b.4, R-20 (a) → решение D-32): **только по тегу
/// активного пресета** (`preset.id`, принцип №3). Полей `moduleConfigs`
/// в схеме больше нет — второго источника истины о выборе не существует.
/// Расширение скоупа (Этап 8, D-30) = новая строка в этом реестре и новый
/// пресет-файл; будущие школы переиспользуют тот же движок с другими
/// конвенциями и своим паком дней (параметризация по D-30) — новая
/// математика не требуется.
///
/// Неизвестный тег (пользовательский пресет без зарегистрированной
/// реализации) — **честная деградация**: [activeCalendarProviderProvider]
/// отдаёт `null` («календаря для этой традиции пока нет»), а не падает
/// и не подменяет чужой календарь (контракт 4.1).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/providers/app_providers.dart';
import '../../data/calendar_special_days_source.dart';
import '../../data/tibetan/tibetan_calendar_provider.dart';
import '../../data/uposatha/uposatha_calendar_provider.dart';
import '../../../../core/calendar/calendar_provider.dart';
import '../../../../core/calendar/special_days_source.dart';

/// Тибетский календарь (Пхугпа) для тега традиции [String].
///
/// Ключ — `preset.id` активного пресета (принцип №3/B-4); сам провайдер
/// тег не выбирает и ни о каких школах не знает — только конструирует
/// реализацию. Значения стабильны по ключу (не autoDispose): порт
/// без состояния на инстанс, перевычисление дешёвое; кэш месяцев
/// по инстансу реализации (B-16, перенесён из статики в 5b.4).
final tibetanCalendarProviderProvider =
    Provider.family<CalendarProvider, String>(
  (ref, traditionTag) => TibetanCalendarProvider(traditionTag: traditionTag),
);

/// Календарь упосатх (лунные фазы) для тега традиции [String].
///
/// DI-регистрация по тому же контракту, что и тибетский: ключ — `preset.id`,
/// реализация о школах не знает (I-6: сам `UposathaCalendarProvider` не
/// тронут — только подключение).
final uposathaCalendarProviderProvider =
    Provider.family<CalendarProvider, String>(
  (ref, traditionTag) => UposathaCalendarProvider(traditionTag: traditionTag),
);

/// Реестр «тег активного пресета → реализация календаря» (5b.4, D-32) —
/// в [calendarProviderForTagProvider], единственном месте, где связь
/// традиции и календаря выражена явно. Ключи — `preset.id` из манифеста
/// `presets/index.json`; ключи традиций живут только здесь (фича календаря
/// знает свои реализации — ядро и навигация по-прежнему нет, guard-тесты
/// импортов это берегут).
final calendarProviderForTagProvider =
    Provider.family<CalendarProvider?, String>(
  (ref, traditionTag) => switch (traditionTag) {
    'nyingma' => ref.watch(tibetanCalendarProviderProvider(traditionTag)),
    'theravada_default' =>
      ref.watch(uposathaCalendarProviderProvider(traditionTag)),
    // Неизвестный тег — честная деградация: календарного модуля для такой
    // традиции в сборке нет; UI обязан показать «нет календаря для традиции»
    // (SCR-11), а не пустой список «всё тихо».
    _ => null,
  },
);

/// Календарь активного пресета (R-21): реактивная связка «тег → реализация».
///
/// Меняется без перезапуска вместе с `applyPreset`/`switchPreset`/
/// `resetPreset` (покрывается потоком [activeTraditionTagProvider]).
/// `null` — активного пресета нет или для него нет календаря в реестре.
final activeCalendarProviderProvider = Provider<CalendarProvider?>((ref) {
  final tag = ref.watch(activeTraditionTagProvider).value ?? '';
  if (tag.isEmpty) return null;
  return ref.watch(calendarProviderForTagProvider(tag));
});

/// Источник особых дней для тега [traditionTag] (D-37, пакет 6.2).
///
/// Реализация порта ядра `specialDaysSourceForTagProvider`: фича календаря —
/// единственное место, где известно соответствие «традиция → движок», поэтому
/// адаптер [CalendarSpecialDaysSource] поднимается здесь, а ядро и события
/// видят только контракт. `null` — календаря для такого тега в сборке нет.
final calendarSpecialDaysSourceForTagProvider =
    Provider.family<SpecialDaysSource?, String>((ref, traditionTag) {
  final calendar = ref.watch(calendarProviderForTagProvider(traditionTag));
  return calendar == null ? null : CalendarSpecialDaysSource(calendar);
});

/// Источник особых дней активной традиции — то, что composition root отдаёт в
/// порт ядра `specialDaysSourceProvider` (пакет 6.2).
///
/// Реактивен, как и [activeCalendarProviderProvider]: смена пресета без
/// перезапуска переключает и источник дней.
final activeSpecialDaysSourceProvider = Provider<SpecialDaysSource?>((ref) {
  final tag = ref.watch(activeTraditionTagProvider).value ?? '';
  if (tag.isEmpty) return null;
  return ref.watch(calendarSpecialDaysSourceForTagProvider(tag));
});
