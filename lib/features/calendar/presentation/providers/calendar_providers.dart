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

/// Тибетский календарь (Пхугпа) для тега пресета [String].
///
/// Ключ — тег пресета (`preset.id`; принцип №3/B-4); сам провайдер тег не
/// выбирает и ни о каких школах не знает — только конструирует реализацию
/// (имя параметра `traditionTag` у класса-реализации историческое: значение —
/// тег пресета). Значения стабильны по ключу (не autoDispose): порт без
/// состояния на инстанс, перевычисление дешёвое; кэш месяцев по инстансу
/// реализации (B-16, перенесён из статики в 5b.4).
final tibetanCalendarProviderProvider =
    Provider.family<CalendarProvider, String>(
  (ref, presetTag) => TibetanCalendarProvider(traditionTag: presetTag),
);

/// Календарь упосатх (лунные фазы) для тега пресета [String].
///
/// DI-регистрация по тому же контракту, что и тибетский: ключ — тег пресета
/// (`preset.id`), реализация о школах не знает (I-6: сам
/// `UposathaCalendarProvider` не тронут — только подключение).
final uposathaCalendarProviderProvider =
    Provider.family<CalendarProvider, String>(
  (ref, presetTag) => UposathaCalendarProvider(traditionTag: presetTag),
);

/// Реестр «тег пресета → реализация календаря» (5b.4, D-32) —
/// в [calendarProviderForTagProvider], единственном месте, где связь
/// пресета и календаря выражена явно. Ключи — теги пресетов (`preset.id`)
/// из манифеста `presets/index.json`; ключи школ живут только здесь (фича
/// календаря знает свои реализации — ядро и навигация по-прежнему нет,
/// guard-тесты импортов это берегут). Инвариант «ключи реестра = теги
/// пресетов манифеста (с модулем `calendar`)» держит архитектурный сторож
/// `test/architecture/calendar_registry_manifest_guard_test.dart` (W4/S6).
final calendarProviderForTagProvider =
    Provider.family<CalendarProvider?, String>(
  (ref, presetTag) => switch (presetTag) {
    'nyingma' => ref.watch(tibetanCalendarProviderProvider(presetTag)),
    'theravada_default' =>
      ref.watch(uposathaCalendarProviderProvider(presetTag)),
    // Неизвестный тег — честная деградация: календарного модуля для такого
    // пресета в сборке нет; UI обязан показать «нет календаря для традиции»
    // (SCR-11), а не пустой список «всё тихо».
    _ => null,
  },
);

/// Календарь активного пресета (R-21): реактивная связка «тег → реализация».
///
/// Меняется без перезапуска вместе с `applyPreset`/`resetPreset`
/// (покрывается потоком [activeTraditionTagProvider]).
/// `null` — активного пресета нет или для него нет календаря в реестре.
final activeCalendarProviderProvider = Provider<CalendarProvider?>((ref) {
  // C9: явные состояния вместо `.value`. Ошибка потока тегов выходит наружу
  // (при `hasValue` `.value` молча отдавал устаревший тег); до первого эвента
  // тега — «нет данных» (`null`), как и раньше, но ветвью, а не схлопыванием.
  final tag = ref.watch(activeTraditionTagProvider).when(
        data: (value) => value,
        loading: () => '',
        error: (error, stackTrace) =>
            Error.throwWithStackTrace(error, stackTrace),
        skipLoadingOnReload: true,
      );
  if (tag.isEmpty) return null;
  return ref.watch(calendarProviderForTagProvider(tag));
});

/// Источник особых дней для тега пресета (D-37, пакет 6.2).
///
/// Реализация порта ядра `specialDaysSourceForTagProvider`: фича календаря —
/// единственное место, где известно соответствие «пресет → движок», поэтому
/// адаптер [CalendarSpecialDaysSource] поднимается здесь, а ядро и события
/// видят только контракт. `null` — календаря для такого тега в сборке нет.
final calendarSpecialDaysSourceForTagProvider =
    Provider.family<SpecialDaysSource?, String>((ref, presetTag) {
  final calendar = ref.watch(calendarProviderForTagProvider(presetTag));
  return calendar == null ? null : CalendarSpecialDaysSource(calendar);
});

/// Источник особых дней активной традиции — то, что composition root отдаёт в
/// порт ядра `specialDaysSourceProvider` (пакет 6.2).
///
/// Реактивен, как и [activeCalendarProviderProvider]: смена пресета без
/// перезапуска переключает и источник дней.
final activeSpecialDaysSourceProvider = Provider<SpecialDaysSource?>((ref) {
  // C9: явные состояния вместо `.value` — см. activeCalendarProviderProvider.
  final tag = ref.watch(activeTraditionTagProvider).when(
        data: (value) => value,
        loading: () => '',
        error: (error, stackTrace) =>
            Error.throwWithStackTrace(error, stackTrace),
        skipLoadingOnReload: true,
      );
  if (tag.isEmpty) return null;
  return ref.watch(calendarSpecialDaysSourceForTagProvider(tag));
});
