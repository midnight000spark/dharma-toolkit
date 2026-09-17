/// DI-регистрация фичи контента (D-22, блок C пакета 7.0).
///
/// Все зависимости фичи приходят через провайдеры и оверрайдятся в тестах —
/// service locator запрещён (D-4/D-22). Паки берутся **из данных пресета**
/// (`preset.contentPacks`, поле схемы с D-9), а не из хардкода; читатель
/// ассетов инъектируется бандлом, поэтому тесты не трогают `rootBundle`
/// (F-58 — реальный I/O внутри fake-async зоны).
///
/// **Биндинга в `main.dart` нет намеренно** — это 7.1/Этап 8 (composition root
/// привяжет порт [contentSourceProvider] и календарные особые дни для правила
/// `tibetan`). Здесь фича уже собрана целиком и живёт на контрактах — ровно так
/// фича событий ждала своего биндинга до 6.2.
library;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/calendar/special_days_source.dart';
import '../../../../core/content/content_source.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../data/content_pack_loader.dart';
import '../../data/daily_reading_content_source.dart';
import '../../domain/content_feed.dart';
import '../../domain/content_feed_service.dart';
import '../../domain/daily_reading_service.dart';
import '../../domain/daily_readings.dart';

/// Часы фичи: домен принимает «сегодня» аргументом, поэтому единственная точка,
/// где читается реальное время, — этот провайдер. Тесты оверрайдят его
/// фиксированным значением (детерминизм, урок 5).
final contentClockProvider =
    Provider<DateTime Function()>((ref) => DateTime.now);

/// Бандл ассетов для паков. Продовый дефолт — `rootBundle`; тесты подменяют его
/// (или сам загрузчик) и держат реальный I/O вне fake-async зоны (F-58).
final contentAssetBundleProvider =
    Provider<AssetBundle>((ref) => rootBundle);

/// Загрузчик контент-паков; читатель ассетов приходит из бандла.
final contentPackLoaderProvider = Provider<ContentPackLoader>((ref) {
  final bundle = ref.watch(contentAssetBundleProvider);
  return ContentPackLoader(readAsset: bundle.loadString);
});

/// Ключи ассетов паков, объявленные активным пресетом (`preset.contentPacks`).
///
/// Список приходит **данными из пресета**, а не из хардкода: пустой список —
/// легальное «в сборке нет паков» (тогда работает фолбэк FR-CNT-3, а не
/// молчаливая пустота).
final activeContentPackAssetsProvider = Provider<List<String>>((ref) {
  final preset = ref.watch(activePresetStreamProvider).value;
  return preset?.contentPacks ?? const [];
});

/// Загруженные паки активного пресета (сбои — в результате, не исключением).
///
/// Список берётся **из самого пресета, дождавшись потока**: до первого эвента
/// «активного пресета ещё нет» — это не то же самое, что «пресет без паков», и
/// загружать в этот момент нечего (иначе экран на миг показал бы фолбэк там,
/// где контент есть).
final contentPacksProvider = FutureProvider<ContentPackLoadResult>((ref) async {
  final preset = await ref.watch(activePresetStreamProvider.future);
  final assets = preset?.contentPacks ?? const [];
  if (assets.isEmpty) return ContentPackLoadResult.empty;
  return ref.watch(contentPackLoaderProvider).load(assets);
});

/// Сервис чтения дня: паки активного пресета + тибетские даты через порт ядра.
///
/// Календарь запрашивается **только** через [specialDaysSourceProvider] (D-37):
/// прямых импортов фичи календаря здесь нет и быть не должно. Непривязанный порт
/// ядра — **ошибка композиции, а не пользовательская ситуация**: он падает
/// громко (паттерн D-22/R-13), а не подменяется молча «календаря нет» —
/// молчаливая деградация неотличима от настоящей пустоты, и её ловили как
/// R-11/R-13/R-20. Деградация «календарь не знает тибетских дат» — это `null`
/// **значение** порта, и она обрабатывается доменом с пояснением.
final dailyReadingServiceProvider = Provider<DailyReadingService>((ref) {
  final tag = ref.watch(activeTraditionTagProvider).value ?? '';
  final loaded = ref.watch(contentPacksProvider).value;
  return DailyReadingService(
    traditionTag: tag,
    packs: loaded?.packs ?? const [],
    source: ref.watch(specialDaysSourceProvider),
  );
});

/// Чтения текущего дня активной традиции.
final dailyReadingProvider = Provider<DailyReadings>((ref) {
  return ref
      .watch(dailyReadingServiceProvider)
      .readingsFor(ref.watch(contentClockProvider)());
});

/// Лента контента активной традиции на текущий день (окно по умолчанию — 7 дней).
final contentFeedServiceProvider = Provider<ContentFeedService>((ref) {
  final tag = ref.watch(activeTraditionTagProvider).value ?? '';
  final loaded = ref.watch(contentPacksProvider).value;
  return ContentFeedService(
    traditionTag: tag,
    packs: loaded?.packs ?? const [],
    source: ref.watch(specialDaysSourceProvider),
    packFailures: loaded?.failures ?? const [],
  );
});

/// Лента контента на текущий день.
final contentFeedProvider = Provider<ContentFeed>((ref) {
  return ref
      .watch(contentFeedServiceProvider)
      .build(today: ref.watch(contentClockProvider)());
});

/// Реализация порта ядра [ContentSource] — то, чем composition root привяжет
/// [contentSourceProvider] (сам биндинг — 7.1/Этап 8).
final dailyReadingContentSourceProvider = Provider<DailyReadingContentSource>(
  (ref) => DailyReadingContentSource(ref.watch(dailyReadingServiceProvider)),
);
