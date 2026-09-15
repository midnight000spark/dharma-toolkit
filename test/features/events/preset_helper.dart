/// Хелпер тестов фичи событий: пресет с объявленными паками (не `*_test.dart`,
/// не запускается как сюит).
///
/// Пак объявляется **данными пресета** (`eventPacks`), а не хардкодом фичи:
/// тесты проводки проверяют именно этот путь (B-4 — тег/состав из данных).
library;

import 'package:dharma_toolkit/core/config/preset_schema.dart';

/// Пресет с тегом `nyingma` и объявленными ключами ассетов паков.
PresetSchema presetWithEventPacks(List<String> packAssets) => PresetSchema(
      id: 'nyingma',
      name: 'Ньингма',
      version: '1.0.0',
      modules: const ['calendar', 'tracker'],
      tradition: 'vajrayana',
      practices: const [],
      eventPacks: packAssets,
      contentPacks: const [],
    );
