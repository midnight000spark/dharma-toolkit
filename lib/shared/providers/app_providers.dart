import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/config_module.dart';
import '../../core/config/preset_manager.dart';

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
/// списков (I-4/B-4: литералов 'sample' в lib/ быть не должно).
final activeTraditionTagProvider = Provider<String>((ref) {
  final preset = ref.watch(presetManagerProvider).activePreset;
  return preset?.id ?? '';
});
