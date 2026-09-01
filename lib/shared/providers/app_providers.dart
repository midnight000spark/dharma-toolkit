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

/// Активный пресет как поток (D-16-подход, R-21): единственный реактивный
/// источник «какой пресет выбран». Все производные провайдеры (тег традиции,
/// активный календарь) подписаны на [PresetManager.activePresetStream], а не
/// читают plain-поле `activePreset` — иначе смена пресета из настроек
/// (Этап 8, FR-ONB-4) оставит UI на старых данных (существо R-21).
/// Первый эвент — текущее значение сразу.
final activePresetStreamProvider = StreamProvider<PresetSchema?>(
  (ref) => ref.watch(presetManagerProvider).activePresetStream,
);

/// Тег традиции активного пресета — единственный источник для фильтрации
/// списков (I-4/B-4: захардкоженных тегов традиций в lib/ быть не должно).
///
/// **Реактивен (R-21, 5b.4):** StreamProvider поверх потока пресетов;
/// `applyPreset`/`switchPreset`/`resetPreset` меняют тег без перезапуска.
/// До первого эвента и при сброшенном пресете — пустая строка.
final activeTraditionTagProvider = StreamProvider<String>(
  (ref) => ref
      .watch(presetManagerProvider)
      .activePresetStream
      .map((preset) => preset?.id ?? ''),
);
