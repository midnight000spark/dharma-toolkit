import '../config/config_module.dart';
import '../config/preset_manager.dart';

/// Dev-сидер: в отладочных сборках, если активный пресет ещё не выбран,
/// применяет первый доступный пресет манифеста через реальный путь
/// `PresetManager.applyPreset` (замена хардкода практик, 5.0.2).
///
/// Ядро не знает о конкретных школах (принцип 1): прежний литерал `'nyingma'`
/// заменён на первый пресет манифеста (B-20) — порядок задаёт `presets/index.json`.
///
/// Практик раньше сеял тип `'timer'`, которого не существует (R-17) — убрано:
/// источник тестовых данных теперь сам продукт.
class DevSeeder {
  /// Идемпотентен: если пресет уже активен — ничего не делает.
  static Future<void> seedIfEmpty({
    required PresetManager presets,
    required ConfigModule config,
  }) async {
    if (presets.activePreset != null) return;

    final available = config.allPresets;
    if (available.isEmpty) return; // пресетов нет в сборке — не выдумываем

    await presets.applyPreset(available.first);
  }
}
