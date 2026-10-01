/// Реализация порта ядра [ContentSource] поверх домена чтения дня (блок C 7.0).
///
/// Адаптер — то место, где контракт ядра встречается с логикой фичи. Логики
/// внутри нет намеренно: иначе «чтение дня» на дашборде (через порт) и в ленте
/// контента (напрямую) разошлись бы — класс дефектов «два источника истины»
/// (B-4/R-20). Гибридного состояния не бывает: оба пути идут через
/// [DailyReadingService].
///
/// **W22 (warning-3c):** порт получает результат дня целиком ([DailyReadings]),
/// а не проекцию «только список чтений»: проекция молча теряла
/// пользовательские пояснения (`notes`, C8г), и потребитель порта (SCR-7)
/// видел чтения без честности пустоты.
library;

import '../../../core/content/content_source.dart';
import '../../../core/content/daily_reading.dart';
import '../domain/daily_reading_service.dart';

/// Источник чтений дня для порта ядра.
class DailyReadingContentSource implements ContentSource {
  DailyReadingContentSource(this.service);

  /// Домен, которым порт отвечает (без собственных правил отбора текста).
  final DailyReadingService service;

  @override
  String get traditionTag => service.traditionTag;

  @override
  DailyReadings readingsFor(DateTime day) => service.readingsFor(day);
}
