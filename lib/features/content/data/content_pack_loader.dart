/// Загрузчик контент-паков из ассетов (FR-CNT-1/2, прецедент `EventPackLoader`).
///
/// **Честный сбой вместо краха:** отсутствующий ассет, битый JSON и невалидная
/// схема — не исключение наружу, а запись в [ContentPackLoadResult.failures] с
/// названной причиной. Пак, который не удалось прочитать, не должен ни валить
/// приложение, ни незаметно исчезать: пользователь обязан увидеть либо текст с
/// источником, либо честный фолбэк (FR-CNT-3), а не пустоту без объяснения
/// (UX-A-4).
///
/// **Список паков приходит данными** — из `preset.contentPacks` активного
/// пресета (поле уже в схеме пресета, D-9), а не из хардкода и не из
/// «магического» пути. Пустой список легален: в сборке может не быть ни одного
/// пака, пока тексты, прошедшие правовую проверку (FR-CNT-4), не собраны
/// человеком-треком; это честное пустое состояние, а не ошибка.
///
/// Читатель ассетов инъектируется: тесты не трогают `rootBundle` (F-58 —
/// реальный I/O внутри fake-async зоны), а продовый дефолт остаётся
/// `rootBundle.loadString`.
library;

import 'dart:convert';

import 'package:flutter/services.dart';

import '../domain/content_pack.dart';
import 'content_pack_parser.dart';

/// Читатель ассета по ключу (продовый дефолт — `rootBundle.loadString`).
typedef ContentPackAssetReader = Future<String> Function(String assetKey);

/// Почему конкретный пак не доехал до модели.
class ContentPackFailure {
  /// Ключ ассета, на котором споткнулись.
  final String assetKey;

  /// Причина для человека (ассет/JSON/схема — с путём поля).
  final String reason;

  const ContentPackFailure(this.assetKey, this.reason);

  @override
  String toString() => '$assetKey: $reason';
}

/// Итог загрузки: то, что доехало, и то, что сломалось (с причинами).
class ContentPackLoadResult {
  /// Успешно разобранные паки в порядке объявления.
  final List<ContentPack> packs;

  /// Сбои — по одной записи на пак; порядок соответствует списку ассетов.
  final List<ContentPackFailure> failures;

  const ContentPackLoadResult({required this.packs, required this.failures});

  /// Есть ли хоть один сбой (UI показывает честную плашку, не «всё тихо»).
  bool get hasFailures => failures.isNotEmpty;

  /// Пустой итог: паков нет, сбоев нет — легальное «контента пока нет».
  static const ContentPackLoadResult empty =
      ContentPackLoadResult(packs: [], failures: []);
}

/// Загружает паки по списку ключей ассетов; сбои не прерывают остальные.
class ContentPackLoader {
  ContentPackLoader({ContentPackAssetReader? readAsset})
      : _readAsset = readAsset ?? rootBundle.loadString;

  final ContentPackAssetReader _readAsset;

  /// Прочитать паки по [assetKeys].
  ///
  /// Никогда не бросает: каждый ключ либо даёт [ContentPack] в
  /// [ContentPackLoadResult.packs], либо [ContentPackFailure] в
  /// [ContentPackLoadResult.failures]. Повтор `packId` во втором паке — сбой:
  /// ключ пака обязан быть уникальным, иначе атрибуция записи неоднозначна;
  /// первый пак при этом сохраняется.
  Future<ContentPackLoadResult> load(List<String> assetKeys) async {
    final packs = <ContentPack>[];
    final failures = <ContentPackFailure>[];
    final seenPackIds = <String>{};

    for (final assetKey in assetKeys) {
      String raw;
      try {
        raw = await _readAsset(assetKey);
      } catch (e) {
        failures.add(ContentPackFailure(assetKey, 'ассет не прочитан: $e'));
        continue;
      }

      Object? decoded;
      try {
        decoded = jsonDecode(raw);
      } catch (e) {
        failures.add(ContentPackFailure(assetKey, 'битый JSON: $e'));
        continue;
      }
      if (decoded is! Map) {
        failures.add(ContentPackFailure(
            assetKey, 'ожидался объект пака, получен ${decoded.runtimeType}'));
        continue;
      }

      final ContentPack pack;
      try {
        pack = ContentPackParser.parse(Map<String, dynamic>.from(decoded));
      } on ContentPackFormatException catch (e) {
        failures.add(ContentPackFailure(assetKey, e.toString()));
        continue;
      }

      if (!seenPackIds.add(pack.packId)) {
        failures.add(ContentPackFailure(
          assetKey,
          'дубль packId "${pack.packId}": пак с таким id уже загружен '
              '(атрибуция стала бы неоднозначной)',
        ));
        continue;
      }
      packs.add(pack);
    }

    return ContentPackLoadResult(packs: packs, failures: failures);
  }
}
