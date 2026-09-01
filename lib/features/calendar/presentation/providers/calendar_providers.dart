/// DI-регистрация календарей традиции (D-22, пакет 5b.3 блок 5).
///
/// Реализации живут как чистые классы (конструктор с traditionTag); этот
/// файл поднимает их в Riverpod — единственную DI-систему проекта.
/// Выбор реализации по активному пресету (какой тег какому календарю) —
/// НЕ здесь: это контракт 5b.4 со явным решением по R-20. Здесь —
/// только конструирование по переданному тегу (family), чтобы слой UI
/// получал провайдер через ref.watch, а не new-ом (R-11 service locator
/// запрещён и здесь тоже).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/tibetan/tibetan_calendar_provider.dart';
import '../../domain/calendar_provider.dart';

/// Тибетский календарь (Пхугпа) для тега традиции [String].
///
/// Ключ — `preset.id` активного пресета (принцип №3/B-4); сам провайдер
/// тег не выбирает и ни о каких школах не знает — только конструирует
/// реализацию. Значения стабильны по ключу (не autoDispose): порт
/// без состояния на инстанс, перевычисление дешёвое, кэш месяцев
/// общий на приложение (B-16 осознанно до 5b.4).
final tibetanCalendarProviderProvider =
    Provider.family<CalendarProvider, String>(
  (ref, traditionTag) => TibetanCalendarProvider(traditionTag: traditionTag),
);
