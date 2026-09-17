/// Хелпер тестов фичи контента: пресет с объявленными паками (не сюит).
///
/// Паки объявляются **данными пресета** (`contentPacks`), а не хардкодом фичи:
/// тесты проводки проверяют именно этот путь (B-4 — состав из данных).
library;

import 'package:dharma_toolkit/core/config/preset_schema.dart';

/// Пресет с тегом `nyingma` и объявленными ключами ассетов контент-паков.
PresetSchema presetWithContentPacks(List<String> packAssets) => PresetSchema(
      id: 'nyingma',
      name: 'Ньингма',
      version: '1.0.0',
      modules: const ['calendar', 'tracker'],
      tradition: 'vajrayana',
      practices: const [],
      eventPacks: const [],
      contentPacks: packAssets,
    );
