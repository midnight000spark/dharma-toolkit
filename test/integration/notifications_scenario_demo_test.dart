/// Демонстрируемый сценарий уведомлений на уровне данных (6.3, блок B; урок 2,
/// прецедент 5b.6).
///
/// Прогон идёт через **живую композицию приложения**: shipping-пресеты из
/// `presets/` (ConfigModule + rootBundle), PresetManager на in-memory БД, шина
/// событий и те же портовые оверрайды, что ставит composition root
/// (`platformPortOverrides`) — единственная подмена это планировщик и часы
/// (детерминизм, урок 5: ни виджетов, ни таймеров, ни fake-async).
///
/// Показывает и ассертит:
///  1. план Ньингмы на горизонте 60 дней: полоса id D-36, ascending, только
///     будущие моменты — и что те же пункты реально лежат в планировщике;
///  2. дедуп «одна минута — один показ»: две записи ленты об одном дне
///     (календарь + пак) дают один показ;
///  3. потолок 64 pending (F-57) — превышение не молчит, а поясняется;
///  4. прошедший момент дня не планируется;
///  5. деградация Linux-стиля (F-57): отказ платформы планировать — честная
///     пометка в лог, а не краш и не молчаливый немедленный показ;
///  6. перепланирование по `PresetChanged` и смене настроек, идемпотентное
///     (cancelRange своей полосы + schedule заново), с честным пустым планом
///     при выключенных уведомлениях.
///
/// Вывод шагов печатается в stdout — секции прогона идут в отчёт пакета
/// дословно (урок 2: критерий — предъявляемый прогон). Поэтому print здесь
/// продукт файла, а не отладочный шум.
// ignore_for_file: avoid_print
library;

import 'package:dharma_toolkit/core/calendar/special_day.dart';
import 'package:dharma_toolkit/core/calendar/special_days_source.dart';
import 'package:dharma_toolkit/core/config/config_module.dart';
import 'package:dharma_toolkit/core/config/preset_manager.dart';
import 'package:dharma_toolkit/core/db/app_database.dart';
import 'package:dharma_toolkit/core/events/event_bus.dart';
import 'package:dharma_toolkit/core/events/event_bus_provider.dart';
import 'package:dharma_toolkit/core/storage/storage_module.dart';
import 'package:dharma_toolkit/features/events/domain/event_feed.dart';
import 'package:dharma_toolkit/features/events/domain/event_feed_service.dart';
import 'package:dharma_toolkit/features/events/domain/event_pack.dart';
import 'package:dharma_toolkit/features/events/domain/notification_plan.dart';
import 'package:dharma_toolkit/features/events/domain/notification_settings.dart';
import 'package:dharma_toolkit/features/events/platform/notification_service.dart';
import 'package:dharma_toolkit/features/events/presentation/providers/event_providers.dart';
import 'package:dharma_toolkit/main.dart';
import 'package:dharma_toolkit/shared/providers/app_providers.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/events/in_memory_notification_scheduler.dart';
import '../features/events/platform_fakes.dart';

/// Источник особых дней с заданным содержимым (в живом контейнере он
/// подменяет календарную реализацию — порт остаётся тем же, D-37).
class _StubSource implements SpecialDaysSource {
  _StubSource(this.traditionTag, {this.days = const [], this.tibetanDates});

  @override
  final String traditionTag;
  final List<SpecialDay> days;
  final List<DateTime>? tibetanDates;

  @override
  List<SpecialDay> getSpecialDays(DateTime from, DateTime to) => [
        for (final d in days)
          if (!d.date.isBefore(from) && !d.date.isAfter(to)) d,
      ];

  @override
  List<DateTime>? resolveTibetanMonthDay({
    required int month,
    required int day,
    required DateTime from,
    required DateTime to,
  }) =>
      tibetanDates;
}

String _fmt(DateTime d) => '${d.year}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

String _hm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

void _printPlan(String title, NotificationPlan plan) {
  print('--- $title: ${plan.items.length} показов ---');
  for (final item in plan.items) {
    print('  #${item.id} ${_fmt(item.scheduledAt)} ${_hm(item.scheduledAt)} '
        '| ${item.title} | ${item.body}');
  }
  for (final note in plan.notes) {
    print('  примечание: $note');
  }
}

void _printFeed(String title, EventFeed feed) {
  print('--- $title: ${feed.entries.length} записей ---');
  for (final e in feed.entries) {
    print('  ${_fmt(e.date)} | ${e.title} ← ${e.attribution} '
        '(${e.isVerified ? 'проверено' : 'не проверено'})');
  }
}

/// Полдень — «сейчас» во всех шагах: до 08:00 напоминаний дня ещё есть время,
/// после — уже нет (границу проверяем шагом 4).
final _now = DateTime(2026, 9, 17, 12);

/// Два события в один день: горизонт D-36 — 60 дней, поэтому однодневных
/// событий в окне помещается меньше 64, и потолок pending на них не проверить.
/// Несколько событий на день — реальность паков поверх календаря (D-35), так
/// что проверка идёт на том же входе, что даёт продакшен.
List<SpecialDay> _twiceDailyDays(DateTime from, int days) => [
      for (var i = 0; i < days; i++) ...[
        SpecialDay(
          date: DateTime(from.year, from.month, from.day + i),
          type: SpecialDayType.tibetan10,
          name: 'День $i · событие A',
        ),
        SpecialDay(
          date: DateTime(from.year, from.month, from.day + i),
          type: SpecialDayType.tibetan25,
          name: 'День $i · событие B',
        ),
      ],
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late StorageModule storage;
  late ConfigModule config;
  late PresetManager manager;
  late EventBus bus;
  late InMemoryNotificationScheduler scheduler;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    database = AppDatabase.forTesting(
      NativeDatabase.memory(setup: enableForeignKeys),
    );
    storage = StorageModule();
    await storage.init();
    config = ConfigModule();
    await config.init(); // реальные shipping-пресеты (presets/*.json)
    bus = EventBus();
    manager = PresetManager(() => database, storage, eventBus: bus);
    await manager.init();
    scheduler = InMemoryNotificationScheduler();

    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        presetManagerProvider.overrideWithValue(manager),
        eventBusProvider.overrideWithValue(bus),
        eventsClockProvider.overrideWithValue(() => _now),
        // Та же функция проводки портов, что в composition root: план читает
        // особые дни активной традиции и планировщик — через порты ядра.
        ...platformPortOverrides(scheduler: scheduler),
      ],
    );
    // Потоковые провайдеры живут между read-вызовами (паттерн 5b.6).
    container.listen(activeTraditionTagProvider, (_, _) {});
    container.listen(activePresetStreamProvider, (_, _) {});
  });

  tearDown(() async {
    container.dispose();
    await database.close();
    try {
      await storage.dispose();
    } catch (_) {}
    bus.dispose();
  });

  test('SCR-12: живой план Ньингмы на 60 дней — полоса id, порядок, pending',
      () async {
    final replanner = container.read(notificationReplannerProvider);
    replanner.start();
    await manager.applyPreset(config.getPreset('nyingma')!);
    // Событие шины доезжает подписчику микротаском: `settled` ждёт уже
    // накопленную очередь, поэтому без этого шага проверка гоняла бы пустой
    // план (гонка, а не дефект планировщика).
    await pumpEventQueue();
    await replanner.settled;

    final plan = container.read(notificationPlanProvider);
    _printPlan('Ньингма (часы ${_fmt(_now)} ${_hm(_now)}, горизонт 60 дней)',
        plan);

    // Пункты — в полосе приложения и строго по возрастанию (D-36).
    expect(plan.items, isNotEmpty, reason: 'план живой композиции не должен пустовать');
    expect(plan.items.map((i) => i.id).toList(),
        [for (var i = 0; i < plan.items.length; i++) 100000 + i]);
    expect(plan.items.length, lessThanOrEqualTo(NotificationPlan.maxPending));
    // Горизонт: ничего позже «сегодня + 60 дней» и ничего раньше «сейчас».
    final horizonEnd = _now.add(NotificationPlanBuilder.defaultHorizon);
    for (final item in plan.items) {
      expect(item.scheduledAt.isBefore(_now), isFalse,
          reason: 'прошедший момент не планируется (шаг 4)');
      expect(item.scheduledAt.isAfter(horizonEnd), isFalse,
          reason: 'горизонт D-36 — 60 дней');
      expect(NotificationPlan.idRangeStart <= item.id &&
          item.id <= NotificationPlan.idRangeEnd, isTrue);
    }
    // Все пункты действительно поставлены планировщику (не «план на бумаге»).
    expect(await scheduler.pendingIds(), plan.items.map((i) => i.id).toList());
    print('  pending в планировщике: ${await scheduler.pendingIds()}');
  });

  test('SCR-12: дедуп «одна минута — один показ» — календарь и пак об одном дне',
      () async {
    const sharedName = '10-й день тибетского месяца';
    final day = SpecialDay(
      date: DateTime(2026, 9, 21),
      type: SpecialDayType.tibetan10,
      name: sharedName,
    );
    final service = EventFeedService(
      traditionTag: 'nyingma',
      source: _StubSource('nyingma', days: [day], tibetanDates: [
        DateTime(2026, 9, 21)
      ]),
      packs: [
        EventPack(
          packId: 'синтетический',
          traditionTag: 'nyingma',
          version: '1',
          verified: true,
          entries: const [
            EventPackEntry(
              id: 'e1',
              type: 'festival',
              name: sharedName,
              source: 'синтетическая фикстура теста',
              dateRule: TibetanDateRule(month: 8, day: 10),
            ),
          ],
        ),
      ],
    );
    final builder = NotificationPlanBuilder(feedService: service);

    _printFeed('Лента до планирования (календарь + пак об одном дне)',
        service.build(today: _now, window: NotificationPlanBuilder.defaultHorizon));
    final plan = builder.build(now: _now, settings: NotificationSettings.defaults);
    _printPlan('План после дедупа', plan);

    expect(service.build(today: _now, window: NotificationPlanBuilder.defaultHorizon)
        .entries.length, 2,
        reason: 'в ленте обязаны быть обе записи — дедуп живёт в плане, а не в ленте');
    expect(plan.items, hasLength(1),
        reason: 'две записи об одной минуте с одним названием дают один показ');
    expect(plan.items.single.title, sharedName);
  });

  test('SCR-12: потолок 64 pending (F-57) не молчит, а поясняется', () {
    // 40 дней × 2 события = 80 записей в 60-дневном окне (все — будущие).
    const days = 40;
    const overflow = days * 2;
    final plan = NotificationPlanBuilder(
      feedService: EventFeedService(
        traditionTag: 'nyingma',
        source: _StubSource('nyingma',
            days: _twiceDailyDays(_now.add(const Duration(days: 1)), days)),
        packs: const [],
      ),
    ).build(now: _now, settings: NotificationSettings.defaults);

    print('--- Потолок pending: подали $overflow событий за $days дней, '
        'в план попало ${plan.items.length} ---');
    for (final note in plan.notes) {
      print('  примечание: $note');
    }

    expect(plan.items, hasLength(NotificationPlan.maxPending));
    expect(plan.hasNotes, isTrue,
        reason: 'усечение плана обязано быть видимым, а не тихим');
    expect(
        plan.notes.any((n) => n.contains('лимит 64')), isTrue,
        reason: 'пояснение должно называть лимит, а не просто «часть отброшена»');
    expect(
        plan.notes.any((n) =>
            n.contains('${overflow - NotificationPlan.maxPending}')), isTrue,
        reason: 'пояснение обязано называть число отброшенных событий');
  });

  test('SCR-12: прошедший момент того же дня не планируется', () {
    final today = SpecialDay(
      date: DateTime(2026, 9, 17),
      type: SpecialDayType.tibetan10,
      name: 'Сегодняшний день (08:00 уже прошло)',
    );
    final tomorrow = SpecialDay(
      date: DateTime(2026, 9, 18),
      type: SpecialDayType.tibetan25,
      name: 'Завтрашний день',
    );
    final plan = NotificationPlanBuilder(
      feedService: EventFeedService(
        traditionTag: 'nyingma',
        source: _StubSource('nyingma', days: [today, tomorrow]),
        packs: const [],
      ),
    ).build(now: _now, settings: NotificationSettings.defaults);
    _printPlan('Прошедший момент (часы ${_hm(_now)})', plan);

    expect(plan.items, hasLength(1));
    expect(plan.items.single.title, 'Завтрашний день');
    expect(plan.notes.any((n) => n.contains('прошедших')), isTrue,
        reason: 'пропуск прошедшего дня обязан быть объяснён');
  });

  test('SCR-12: деградация Linux-стиля — честная пометка, не краш и не показ',
      () async {
    final gateway = FakeNotificationGateway()
      ..zonedScheduleError = UnimplementedError('планирование не поддержано')
      ..pendingIdsError = UnimplementedError('перечисление не поддержано');
    final warnings = <String>[];
    final degradation = RecordingScheduleDegradation();
    final service = NotificationService(
      gateway: gateway,
      timeZoneSource: FakeLocalTimeZoneSource('Europe/Moscow'),
      degradation: degradation,
      warn: warnings.add,
    );
    await service.initialize();

    final item = NotificationPlanItem(
      id: NotificationPlan.idRangeStart,
      scheduledAt: DateTime(2026, 9, 21, 8),
      title: 'Особый день',
      body: 'Тело',
      payload: '{}',
    );

    await service.schedule(item); // не должно бросить (F-57)
    print('--- Деградация Linux-стиля ---');
    print('  отказ записан: ${degradation.unsupported.length}; '
        'немедленных показов: ${gateway.shown.length}');
    print('  pendingIds → ${await service.pendingIds()} (предупреждений: '
        '${warnings.length})');
    for (final w in warnings) {
      print('  лог: $w');
    }

    expect(degradation.unsupported, hasLength(1),
        reason: 'отказ платформы обязан дойти до слоя деградации');
    expect(degradation.unsupported.single.title, 'Особый день');
    expect(gateway.shown, isEmpty,
        reason: 'молчаливый немедленный показ в обход даты — нарушение FR-EVT-4');
    expect(await service.pendingIds(), isEmpty);
    expect(warnings, isNotEmpty, reason: '«тишина на Linux» неотличима от успеха');
  });

  test('SCR-12: переплан по PresetChanged и настройкам — идемпотентно',
      () async {
    final replanner = container.read(notificationReplannerProvider);
    replanner.start();
    await manager.applyPreset(config.getPreset('nyingma')!);
    await pumpEventQueue();
    await replanner.settled;
    final nyingmaIds = await scheduler.pendingIds();
    print('--- Переплан ---');
    print('  шаг 1: Ньингма → pending $nyingmaIds '
        '(cancelRange вызван ${scheduler.cancelRangeCalls}×)');

    // Смена традиции: событие шины, план строится по НОВОМУ пресету.
    await manager.switchPreset(config.getPreset('theravada_default')!);
    await pumpEventQueue();
    await replanner.settled;
    final theravadaIds = await scheduler.pendingIds();
    final theravadaPlan = container.read(notificationPlanProvider);
    _printPlan('шаг 2: Тхеравада (тот же контейнер)', theravadaPlan);
    print('  шаг 2: pending $theravadaIds '
        '(cancelRange вызван ${scheduler.cancelRangeCalls}×)');
    expect(theravadaIds, isNotEmpty);
    expect(theravadaIds, theravadaPlan.items.map((i) => i.id).toList(),
        reason: 'после переплана в планировщике ровно пункты плана — без дублей');

    // Повторное применение настроек без изменения значения: переплан обязан
    // остаться идемпотентным (cancelRange своей полосы + schedule заново).
    final store = container.read(notificationSettingsStoreProvider);
    await store.write('theravada_default', NotificationSettings.defaults);
    await pumpEventQueue();
    await replanner.settled;
    print('  шаг 3: те же настройки записаны повторно → pending '
        '${await scheduler.pendingIds()} '
        '(cancelRange вызван ${scheduler.cancelRangeCalls}×)');
    expect(await scheduler.pendingIds(), theravadaIds,
        reason: 'повторный переплан не должен плодить дубли');

    // Выключение уведомлений: план пуст, полоса снята (FR-EVT-3/FR-EVT-4).
    await store.write('theravada_default',
        NotificationSettings.defaults.copyWith(enabled: false));
    await pumpEventQueue();
    await replanner.settled;
    final offPlan = container.read(notificationPlanProvider);
    _printPlan('шаг 4: уведомления выключены', offPlan);
    print('  шаг 4: pending ${await scheduler.pendingIds()}');
    expect(offPlan.items, isEmpty);
    expect(await scheduler.pendingIds(), isEmpty);
    expect(offPlan.notes.join(' '), contains('выключены'));

    // Обратно: включение возвращает ровно тот же набор.
    await store.write('theravada_default', NotificationSettings.defaults);
    await pumpEventQueue();
    await replanner.settled;
    print('  шаг 5: включены снова → pending ${await scheduler.pendingIds()}');
    expect(await scheduler.pendingIds(), theravadaIds,
        reason: 'включение обязано вернуть тот же набор (чистота переплана)');

    // Возврат на традицию с МЕНЬШИМ числом пунктов (Тхеравада 8 → Ньингма 4):
    // без снятия своей полосы перед постановкой здесь остались бы чужие id —
    // это и есть проверяемое поведение D-36, а не деталь реализации.
    await manager.switchPreset(config.getPreset('nyingma')!);
    await pumpEventQueue();
    await replanner.settled;
    final backIds = await scheduler.pendingIds();
    print('  шаг 6: возврат на Ньингму (8 → 4 пункта) → pending $backIds '
        '(cancelRange вызван ${scheduler.cancelRangeCalls}×)');
    expect(backIds, nyingmaIds,
        reason: 'переплан обязан заменять полосу целиком, а не дополнять её');
    expect(scheduler.cancelRangeCalls, greaterThanOrEqualTo(6),
        reason: 'каждое применение плана сначала снимает свою полосу (D-36)');
  });
}
