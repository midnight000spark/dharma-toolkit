import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/config_module.dart';
import '../../core/config/preset_manager.dart';
import '../../core/config/preset_schema.dart';
import '../../core/db/app_database.dart';
import '../../core/db/database_module.dart';

/// Единственный экземпляр [AppDatabase] в приложении (D-22, R-11).
///
/// Production-инстанс создаётся один раз в composition root (bootstrap,
/// [DatabaseModule.init]) и передаётся в дерево виджетов через
/// `overrideWithValue` в [ProviderScope]. Провайдеры фич
/// (`practiceRepositoryProvider`) смотрят сюда вместо
/// `ModuleRegistry.instance.get('database')` — service locator со строковым
/// ключом в провайдерах запрещён (D-4/D-22).
/// Без оверрайда провайдер падает явно — молча дотягивать синглтон из реестра
/// нельзя.
final appDatabaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError(
    'appDatabaseProvider требует overrideWithValue в ProviderScope '
    '(см. main.dart)',
  ),
);

/// Провайдеры конфигурации и пресет-менеджера (шаг к D-22).
///
/// Инстанци создаются в `main.dart` (composition root) и передаются через
/// оверрайды `ProviderScope`. Без оверрайда провайдер падает явно — молча
/// доставать синглтон из реестра (service locator, R-11) запрещено.
final configModuleProvider = Provider<ConfigModule>(
  (ref) => throw UnimplementedError(
    'configModuleProvider требует overrideWithValue в ProviderScope '
    '(см. main.dart)',
  ),
);

final presetManagerProvider = Provider<PresetManager>(
  (ref) => throw UnimplementedError(
    'presetManagerProvider требует overrideWithValue в ProviderScope '
    '(см. main.dart)',
  ),
);

/// Часы «сегодня» (W21): точка, где читается реальное локальное время.
///
/// Тесты оверрайдят её фиксированным моментом, поэтому вся арифметика суток
/// проверяется детерминированно (урок 5).
final todayClockProvider =
    Provider<DateTime Function()>((ref) => DateTime.now);

/// Следующая локальная полночь — момент смены суток (W21).
///
/// Именно `DateTime(y, m, d + 1)`, а не `+ Duration(days: 1)`: при переходе
/// на летнее время сутки бывают 23 или 25 часов, и «плюс 24 часа» дало бы
/// смену дня на час раньше или позже реальной полуночи. Нормализация
/// переполнения полей (день 32 → 1-е число следующего месяца) — гарантия
/// языка, поэтому и конец месяца, и конец года считаются корректно.
DateTime nextLocalMidnight(DateTime now) =>
    DateTime(now.year, now.month, now.day + 1);

/// Сегодняшняя дата (W21) — единственный источник «какой сейчас день» для
/// дневных экранов (чтение дня, лента событий, календарь).
///
/// **Живой:** на смену суток сам себя инвалидирует, поэтому экран, открытый
/// через полночь, не остаётся на вчерашнем дне. Смена суток в фоне и смена
/// часового пояса устройства приходят отдельным путём — обработчиком
/// жизненного цикла в composition root (он тоже инвалидирует этот провайдер).
final todayProvider = Provider<DateTime>((ref) {
  final now = ref.watch(todayClockProvider)();
  final untilMidnight = nextLocalMidnight(now).difference(now);
  // Таймер — до полуночи, не периодический: каждый пересчёт заводит следующий.
  final timer = Timer(untilMidnight, ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return DateTime(now.year, now.month, now.day);
});

/// Активный пресет как поток (D-16-подход, R-21): единственный реактивный
/// источник «какой пресет выбран». Все производные провайдеры (тег традиции,
/// активный календарь) подписаны на [PresetManager.activePresetStream], а не
/// читают plain-поле `activePreset` — иначе смена пресета из настроек
/// (Этап 8, FR-ONB-4) оставит UI на старых данных (существо R-21).
/// Первый эвент — текущее значение сразу.
final activePresetStreamProvider = StreamProvider<PresetSchema?>(
  (ref) => ref.watch(presetManagerProvider).activePresetStream,
);

/// Тег активного пресета (`preset.id`) — единственный источник для фильтрации
/// списков (I-4/B-4: захардкоженных тегов в lib/ быть не должно). Имя
/// провайдера/полей `traditionTag` историческое — значение всегда тег пресета
/// (W4/S6, п. 11.3), а поле схемы `tradition` — таксономия.
///
/// **Реактивен (R-21, 5b.4):** StreamProvider поверх потока пресетов;
/// `applyPreset`/`resetPreset` меняют тег без перезапуска.
/// До первого эвента и при сброшенном пресете — пустая строка.
final activeTraditionTagProvider = StreamProvider<String>(
  (ref) => ref
      .watch(presetManagerProvider)
      .activePresetStream
      .map((preset) => preset?.id ?? ''),
);
