import '../config/config_module.dart';
import '../config/preset_manager.dart';

/// Включён ли dev-посев (`--dart-define=SEED=true`, S13).
///
/// По умолчанию **выключен**: прежний посев в каждой debug-сборке применял
/// первый пресет на старте, и экран выбора традиции (`/pick`) становился
/// недостижим — онбординг нельзя было проверить руками в отладочной сборке.
/// Сценарии, которым нужен готовый пресет (эмулятор — `emu-verify`/`emu-fire`),
/// включают посев явно:
///   `flutter build apk --debug --dart-define=SEED=true`
const bool kDevSeedEnabled = bool.fromEnvironment('SEED');

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
  ///
  /// [enabled] — гейт (S13). По умолчанию берётся из сборки
  /// ([kDevSeedEnabled]); явный параметр существует, чтобы **оба режима**
  /// проверялись тестом, а не только константа времени компиляции.
  static Future<void> seedIfEmpty({
    required PresetManager presets,
    required ConfigModule config,
    bool enabled = kDevSeedEnabled,
  }) async {
    // S13: без явного гейта посев выключен — онбординг остаётся достижимым.
    if (!enabled) return;
    if (presets.activePreset != null) return;

    final available = config.allPresets;
    if (available.isEmpty) return; // пресетов нет в сборке — не выдумываем

    await presets.applyPreset(available.first);
  }
}
