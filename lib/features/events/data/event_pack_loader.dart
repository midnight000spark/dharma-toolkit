/// Загрузчик паков событий из ассетов (D-35, FR-EVT-1).
///
/// **Честный сбой вместо краха (SCR-12):** отсутствующий ассет, битый JSON и
/// невалидная схема — не исключение наружу, а запись в [EventPackLoadResult.failures]
/// с названной причиной. Пак, который не удалось прочитать, не должен ни
/// валить приложение, ни незаметно исчезать: UI обязан показать «событий по
/// этому паку нет» / «дата пока не проверена» (UX-A-4), а не пустоту без
/// объяснения.
///
/// **Список паков приходит данными** — из `preset.eventPacks` активного
/// пресета (как `modules`/`practices`), а не из хардкода и не из «магического»
/// пути. Пустой список легален: в сборке может не быть ни одного пака, пока
/// проверенные даты не собраны человеком-треком; это честное пустое состояние,
/// а не ошибка.
///
/// Читатель ассетов инъектируется: тесты не трогают `rootBundle` (F-58 —
/// реальный I/O внутри fake-async зоны), а продовый дефолт остаётся
/// `rootBundle.loadString`.
library;

import 'dart:convert';

import 'package:flutter/services.dart';

import '../domain/event_pack.dart';
import 'event_pack_parser.dart';

/// Читатель ассета по ключу (продовый дефолт — `rootBundle.loadString`).
typedef EventPackAssetReader = Future<String> Function(String assetKey);

/// Почему конкретный пак не доехал до модели.
class EventPackFailure {
  /// Ключ ассета, на котором споткнулись.
  final String assetKey;

  /// Причина для человека (ассет/JSON/схема — с путём поля).
  final String reason;

  const EventPackFailure(this.assetKey, this.reason);

  @override
  String toString() => '$assetKey: $reason';
}

/// Итог загрузки: то, что доехало, и то, что сломалось (с причинами).
class EventPackLoadResult {
  /// Успешно разобранные паки в порядке объявления.
  final List<EventPack> packs;

  /// Сбои — по одной записи на пак; порядок соответствует списку ассетов.
  final List<EventPackFailure> failures;

  const EventPackLoadResult({required this.packs, required this.failures});

  /// Есть ли хоть один сбой (UI показывает честную плашку, не «всё тихо»).
  bool get hasFailures => failures.isNotEmpty;

  /// Пустой итог: паков нет, сбоев нет — легальное «событий пока нет».
  static const EventPackLoadResult empty =
      EventPackLoadResult(packs: [], failures: []);
}

/// Загружает паки по списку ключей ассетов; сбои не прерывают остальные.
class EventPackLoader {
  EventPackLoader({EventPackAssetReader? readAsset})
      : _readAsset = readAsset ?? rootBundle.loadString;

  final EventPackAssetReader _readAsset;

  /// Прочитать паки по [assetKeys].
  ///
  /// Никогда не бросает: каждый ключ либо даёт [EventPack] в [EventPackLoadResult.packs],
  /// либо [EventPackFailure] в [EventPackLoadResult.failures]. Повтор
  /// `packId` во втором паке — сбой: ключ пака обязан быть уникальным,
  /// иначе атрибуция записи неоднозначна; первый пак при этом сохраняется.
  Future<EventPackLoadResult> load(List<String> assetKeys) async {
    final packs = <EventPack>[];
    final failures = <EventPackFailure>[];
    final seenPackIds = <String>{};

    for (final assetKey in assetKeys) {
      String raw;
      try {
        raw = await _readAsset(assetKey);
      } catch (e) {
        failures.add(
            EventPackFailure(assetKey, 'ассет не прочитан: $e'));
        continue;
      }

      Object? decoded;
      try {
        decoded = jsonDecode(raw);
      } catch (e) {
        failures.add(EventPackFailure(assetKey, 'битый JSON: $e'));
        continue;
      }
      if (decoded is! Map) {
        failures.add(EventPackFailure(
            assetKey, 'ожидался объект пака, получен ${decoded.runtimeType}'));
        continue;
      }

      final EventPack pack;
      try {
        pack = EventPackParser.parse(Map<String, dynamic>.from(decoded));
      } on EventPackFormatException catch (e) {
        failures.add(EventPackFailure(assetKey, e.toString()));
        continue;
      }

      if (!seenPackIds.add(pack.packId)) {
        failures.add(EventPackFailure(
          assetKey,
          'дубль packId "${pack.packId}": пак с таким id уже загружен '
              '(атрибуция стала бы неоднозначной)',
        ));
        continue;
      }
      packs.add(pack);
    }

    return EventPackLoadResult(packs: packs, failures: failures);
  }
}
