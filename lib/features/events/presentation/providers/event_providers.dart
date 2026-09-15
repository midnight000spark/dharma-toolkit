/// DI-регистрация фичи событий (D-22, блок E пакета 6.1).
///
/// Все зависимости фичи приходят через провайдеры и оверрайдятся в тестах —
/// service locator запрещён (D-4/D-22). Особые дни календаря фича получает
/// **только** через порт ядра [specialDaysSourceProvider] (D-37): прямых
/// импортов фичи календаря здесь нет и быть не должно.
///
/// **Биндинга в `main.dart` нет намеренно** — это пакет 6.2 (composition root
/// привязывает порт особыми днями активного пресета и ставит платформенный
/// адаптер планировщика). До 6.2 фича живёт в тестах и в готовых провайдерах.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/calendar/special_days_source.dart';
import '../../../../core/config/preset_schema.dart';
import '../../../../core/events/event_bus_provider.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../application/notification_replanner.dart';
import '../../data/event_pack_loader.dart';
import '../../data/notification_settings_store.dart';
import '../../domain/event_feed.dart';
import '../../domain/event_feed_service.dart';
import '../../domain/notification_plan.dart';
import '../../domain/notification_scheduler.dart';
import '../../domain/notification_settings.dart';

/// Часы фичи: домен принимает «сегодня»/«сейчас» аргументом, поэтому
/// единственная точка, где читается реальное время, — этот провайдер.
/// Тесты оверрайдят его фиксированным значением (детерминизм, урок 5).
final eventsClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Загрузчик паков; читатель ассетов инъектируется (тесты не трогают
/// `rootBundle` — F-58).
final eventPackLoaderProvider =
    Provider<EventPackLoader>((ref) => EventPackLoader());

/// Ключи ассетов паков, объявленные активным пресетом (`preset.eventPacks`).
///
/// Список приходит **данными из пресета**, а не из хардкода: пустой список —
/// легальное «в сборке нет паков» (продукт честно молчит, SCR-12).
final activeEventPackAssetsProvider = Provider<List<String>>((ref) {
  final preset = ref.watch(activePresetStreamProvider).value;
  return preset?.eventPacks ?? const [];
});

/// Загруженные паки активного пресета (сбои — в результате, не исключением).
///
/// Список берётся **из самого пресета, дождавшись потока**: до первого эвента
/// «активного пресета ещё нет» — это не то же самое, что «пресет без паков»,
/// и загружать в этот момент нечего (иначе лента на миг показывала бы пустоту
/// там, где паки есть).
final eventPacksProvider = FutureProvider<EventPackLoadResult>((ref) async {
  final preset = await ref.watch(activePresetStreamProvider.future);
  final assets = preset?.eventPacks ?? const [];
  if (assets.isEmpty) return EventPackLoadResult.empty;
  return ref.watch(eventPackLoaderProvider).load(assets);
});

/// Сервис ленты: календарь через порт ядра + паки активного пресета.
final eventFeedServiceProvider = Provider<EventFeedService>((ref) {
  final tag = ref.watch(activeTraditionTagProvider).value ?? '';
  final loaded = ref.watch(eventPacksProvider).value;
  return EventFeedService(
    traditionTag: tag,
    source: ref.watch(specialDaysSourceProvider),
    packs: loaded?.packs ?? const [],
    packFailures: loaded?.failures ?? const [],
  );
});

/// Лента событий активной традиции на текущий день (окно по умолчанию).
final eventFeedProvider = Provider<EventFeed>((ref) {
  final service = ref.watch(eventFeedServiceProvider);
  return service.build(today: ref.watch(eventsClockProvider)());
});

/// Хранилище настроек уведомлений (таблица схемы v4, FR-EVT-3/D-36).
///
/// Пишущее хранилище получает шину: запись настроек публикует
/// `NotificationSettingsChanged` — второй триггер перепланирования (D-36).
final notificationSettingsStoreProvider =
    Provider<NotificationSettingsStore>((ref) {
  return NotificationSettingsStore(
    ref.watch(appDatabaseProvider),
    eventBus: ref.watch(eventBusProvider),
  );
});

/// Настройки уведомлений активной традиции как поток: смена настроек —
/// триггер перепланирования (D-36), поэтому именно поток, а не разовое чтение.
final notificationSettingsProvider =
    StreamProvider<NotificationSettings>((ref) {
  final tag = ref.watch(activeTraditionTagProvider).value ?? '';
  if (tag.isEmpty) {
    // Традиции нет — настраивать нечего; дефолт D-36 честнее «пустоты».
    return Stream.value(NotificationSettings.defaults);
  }
  return ref.watch(notificationSettingsStoreProvider).watch(tag);
});

/// Строитель плана уведомлений (горизонт D-36 — 60 дней).
final notificationPlanBuilderProvider =
    Provider<NotificationPlanBuilder>((ref) {
  return NotificationPlanBuilder(
      feedService: ref.watch(eventFeedServiceProvider));
});

/// План уведомлений активной традиции на текущий момент.
final notificationPlanProvider = Provider<NotificationPlan>((ref) {
  final settings =
      ref.watch(notificationSettingsProvider).value ??
          NotificationSettings.defaults;
  return ref.watch(notificationPlanBuilderProvider).build(
        now: ref.watch(eventsClockProvider)(),
        settings: settings,
      );
});

/// Порт планировщика: платформенный адаптер подключается пакетом 6.2 (D-34).
///
/// Без оверрайда провайдер падает явно — молчаливая подмена «планировщика»
/// заглушкой недопустима (паттерн `appDatabaseProvider`, D-22/R-13).
final notificationSchedulerProvider = Provider<NotificationScheduler>((ref) {
  throw StateError(
    'notificationSchedulerProvider не привязан: composition root обязан '
    'передать платформенный адаптер планировщика (пакет 6.2, D-34)',
  );
});

/// План по активному **на момент вызова** пресету (пакет 6.2).
///
/// Единственный путь сборки плана для перепланирования: активный пресет
/// читается напрямую (первое значение его потока — текущее состояние),
/// настройки — из хранилища по тегу этого пресета, дни — через порт ядра по
/// тому же тегу. Реактивные провайдеры здесь намеренно не используются:
/// событие шины приходит раньше, чем UI-проводка переключит тег, и план по
/// «текущему значению провайдера» построился бы по покинутой традиции.
Future<NotificationPlan> buildNotificationPlan(Ref ref) async {
  final PresetSchema? preset =
      await ref.read(presetManagerProvider).activePresetStream.first;
  final tag = preset?.id ?? '';
  final settings = tag.isEmpty
      ? NotificationSettings.defaults
      : await ref.read(notificationSettingsStoreProvider).read(tag);
  final loaded = await ref
      .read(eventPackLoaderProvider)
      .load(preset?.eventPacks ?? const <String>[]);

  return NotificationPlanBuilder(
    feedService: EventFeedService(
      traditionTag: tag,
      source:
          tag.isEmpty ? null : ref.read(specialDaysSourceForTagProvider(tag)),
      packs: loaded.packs,
      packFailures: loaded.failures,
    ),
  ).build(now: ref.read(eventsClockProvider)(), settings: settings);
}

/// Перепланировщик напоминаний — первый потребитель шины (D-21, блок E 6.2).
///
/// Читается корнем приложения: он перепланирует на старте и подписывается на
/// смену пресета и настроек (триггеры D-36).
final notificationReplannerProvider = Provider<NotificationReplanner>((ref) {
  final replanner = NotificationReplanner(
    bus: ref.watch(eventBusProvider),
    scheduler: ref.watch(notificationSchedulerProvider),
    buildPlan: () => buildNotificationPlan(ref),
    warn: (message) => debugPrint(message),
  );
  ref.onDispose(replanner.stop);
  return replanner;
});
