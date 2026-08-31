import '../config/config_module.dart';
import '../config/preset_manager.dart';

/// Dev-сидер: в отладочных сборках, если активный пресет ещё не выбран,
/// применяет пресет «Ньингма» через реальный путь `PresetManager.applyPreset`
/// (замена хардкода практик, 5.0.2).
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

    final nyingma = config.getPreset('nyingma');
    if (nyingma == null) return; // пресета нет в сборке — не выдумываем

    await presets.applyPreset(nyingma);
  }
}
