import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/config_module.dart';
import '../../core/config/preset_manager.dart';
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

/// Тег традиции активного пресета — единственный источник для фильтрации
/// списков (I-4/B-4: захардкоженных тегов традиций в lib/ быть не должно).
final activeTraditionTagProvider = Provider<String>((ref) {
  final preset = ref.watch(presetManagerProvider).activePreset;
  return preset?.id ?? '';
});
