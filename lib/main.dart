import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_router.dart';
import 'core/calendar/special_days_source.dart';
import 'core/config/config_module.dart';
import 'core/config/preset_manager.dart';
import 'core/db/app_database.dart';
import 'core/db/database_module.dart';
import 'core/db/dev_seeder.dart';
import 'core/events/event_bus.dart';
import 'core/module/module_registry.dart';
import 'core/recovery/recovery_screen.dart';
import 'core/recovery/startup.dart';
import 'core/storage/storage_module.dart';
import 'features/calendar/presentation/providers/calendar_providers.dart';
import 'features/events/application/notification_replanner.dart';
import 'features/events/domain/notification_plan.dart' show NotificationPlanItem;
import 'features/events/domain/notification_scheduler.dart';
import 'features/events/platform/degraded_notification_scheduler.dart';
import 'features/events/platform/notification_gateway.dart';
import 'features/events/platform/notification_scheduler_adapter.dart';
import 'features/events/platform/notification_service.dart';
import 'features/events/presentation/dev/debug_notification_button.dart';
import 'features/events/presentation/notification_permission_banner.dart';
import 'features/events/presentation/providers/event_providers.dart';
import 'shared/l10n/l10n.dart';
import 'shared/providers/app_providers.dart';

/// Готовые сервисы, без которых не собрать ProviderScope.
class AppServices {
  final ConfigModule config;
  final PresetManager presetManager;

  /// Единственный экземпляр БД в приложении (D-22): создан [DatabaseModule]
  /// при инициализации; уходит в `appDatabaseProvider.overrideWithValue`.
  final AppDatabase database;

  const AppServices({
    required this.config,
    required this.presetManager,
    required this.database,
  });
}

/// Точка входа (B-5).
///
/// Порядок инициализации — контракт (6.6):
///   1. binding → 2. глобальные обработчики ошибок → 3. модули реестра
///      (database → storage → config → preset_manager, см. [bootstrapServices])
///   → 4. посев (только debug, некритично) → 5. runApp.
/// Сбой инициализации НЕ валит процесс в чёрный экран: критичные модули
/// уводят на [RecoveryApp], некритичные деградируют с логом (5.4).
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 5.3: красный экран фреймворка — не интерфейс пользователя.
  ErrorWidget.builder = humanErrorWidget;
  // Ошибки фреймворка логируются, не убивая процесс; зона (runZonedGuarded)
  // перехватывает асинхронные отказы.
  FlutterError.onError = FlutterError.presentError;

  /// Что сейчас смонтировано в корне (C3): условие «корень не рабочий», а не
  /// «что-нибудь смонтировано».
  var mountedRoot = MountedRoot.none;

  /// Контроль потока старта живёт в `runStartupCycle` (C3) — здесь только
  /// монтирование конкретных корней.
  // Объявление наперед: `start` и `mountRecoveryRoot` ссылаются друг на друга
  // (кнопка «Попробовать снова» вызывает цикл, а цикл монтирует экран).
  late final Future<void> Function() start;

  void mountRecoveryRoot(Object error, StartupOutcome outcome) {
    mountedRoot = MountedRoot.recovery;
    runApp(RecoveryApp(
      error: error,
      // S12-min: ограниченный режим виден и при фатальном отказе — что именно
      // приложение пережило, до того как пользователь решит стирать данные.
      degradations: outcome.degradedModules,
      onRetry: start,
      onReset: start,
      // C1(3): стирание закрывает соединения ДО файловых операций и
      // переименовывает файл базы вместо удаления; отчёт о неполноте
      // показывает сам экран.
      wipe: () => wipeLocalState(closeDatabase: _closeModulesForWipe),
    ));
  }

  /// Полный цикл старта; повтор вызывается и кнопкой «Попробовать снова»,
  /// и после аварийного стирания (экран сам затирает до [onReset]).
  start = () async {
    mountedRoot = await runStartupCycle<AppServices>(
      bootstrap: bootstrapServices,
      mountApp: (services) async {
        // W19: платформенный планировщик (база таймзон `initializeTimeZones`,
        // плагин, запрос зоны устройства) подключается ПОСЛЕ первого кадра.
        // Раньше `await initNotifications()` стоял до `runApp`: молчащая
        // платформа держала пустой экран до собственного ответа, и таймаут
        // старта его бы не спас — кадр ещё не был отрисован. Порт обязан быть
        // привязан к моменту создания `ProviderScope` (DI-гард W20), поэтому
        // привязывается отложенная связь, а не заглушка: методы честно ждут
        // реальный планировщик и не теряют напоминания молча.
        final scheduler = DeferredNotificationScheduler(initNotifications);
        runApp(ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(services.database),
            configModuleProvider.overrideWithValue(services.config),
            presetManagerProvider.overrideWithValue(services.presetManager),
            ...platformPortOverrides(scheduler: scheduler),
          ],
          child: const DharmaToolkitApp(),
        ));
        WidgetsBinding.instance.addPostFrameCallback((_) => scheduler.connect());
      },
      mountRecovery: mountRecoveryRoot,
    );
  };

  runZonedGuarded<void>(
    () async {
      await start();
    },
    (error, stack) {
      debugPrint('Необработанная ошибка: $error\n$stack');
      // Пока в корне нет РАБОЧЕГО приложения, асинхронный отказ = всё ещё
      // чёрный экран: показываем восстановление (принудительно, повторно —
      // C3). После — только лог (один сбойный виджет не должен уносить
      // приложение).
      if (mountedRoot != MountedRoot.app) {
        mountRecoveryRoot(
          error,
          const StartupOutcome(fatalFailures: [], degradedModules: []),
        );
      }
    },
  );
}

/// Закрытие модулей перед аварийным стиранием (C1(3)).
///
/// Отказ диспоза не отменяет стирание: `wipeLocalState` занесёт его в отчёт, и
/// экран покажет, что стирание было неполным. Модули закрываются все — база
/// первая по важности (`SQLite дописывает файл при close`), а `disposeAll`
/// очищает реестр в `finally`, так что следующий bootstrap поднимет заново.
Future<void> _closeModulesForWipe() async {
  await ModuleRegistry.instance.disposeAll();
}

/// Портовые оверрайды composition root (D-22/D-34/D-37, пакет 6.2).
///
/// Календарь и планировщик приходят в приложение **только** через порты ядра
/// (`core/calendar`, `features/events/domain`), а связываются с реализациями
/// фич здесь — в единственном месте, которому позволено знать обе стороны
/// (принцип №1: фича не импортирует фичу, composition root — может).
///
/// **Зачем функция, а не инлайн в `ProviderScope`:** проводку портов нужно
/// предъявлять тестом («убрал оверрайд — тест красный», урок 1), а поднять
/// ради этого всё приложение нельзя. Тест вызывает ту же функцию, что и
/// `start()`.
List<Override> platformPortOverrides({
  required NotificationScheduler scheduler,
}) =>
    [
      // Особые дни активной традиции — для UI-пути (лента, SCR-12).
      specialDaysSourceProvider.overrideWith(
          (ref) => ref.watch(activeSpecialDaysSourceProvider)),
      // Особые дни по явному тегу — для перепланирования уведомлений: событие
      // смены пресета приходит раньше, чем реактивная проводка обновит тег, и
      // план обязан строиться по уже активной традиции (см. репланер).
      specialDaysSourceForTagProvider.overrideWith((ref, traditionTag) =>
          ref.watch(calendarSpecialDaysSourceForTagProvider(traditionTag))),
      notificationSchedulerProvider.overrideWithValue(scheduler),
    ];

/// Планировщик, подключаемый после первого кадра (W19).
///
/// Экземпляр отдаётся в `notificationSchedulerProvider` **синхронно** (порт
/// обязан быть привязан — DI-гард W20), а реальный платформенный планировщик
/// приходит асинхронно, когда приложение уже показало первый кадр.
///
/// Почему не заглушка: `DegradedNotificationScheduler` на время старта был бы
/// ложью — напоминания терялись бы молча. Методы здесь ждут реальный
/// планировщик; отказ инициализации домен получает честно (его возвращает
/// [initNotifications] как деградацию с причиной).
class DeferredNotificationScheduler implements NotificationScheduler {
  DeferredNotificationScheduler(this._resolve);

  final Future<NotificationScheduler> Function() _resolve;

  Future<NotificationScheduler>? _pending;

  /// Запустить подключение реального планировщика (post-frame из `main`).
  void connect() {
    _pending ??= _resolve();
  }

  /// Реальный планировщик. `connect()` — основной путь; ленивое разрешение —
  /// страховка для вызова порта до первого кадра (например, в тесте или на
  /// retry), чтобы метод не ждал подключения, которого не будет.
  Future<NotificationScheduler> get _delegate => _pending ??= _resolve();

  @override
  Future<void> schedule(NotificationPlanItem item) async =>
      (await _delegate).schedule(item);

  @override
  Future<void> cancel(int id) async => (await _delegate).cancel(id);

  @override
  Future<void> cancelRange({required int fromId, required int toId}) async =>
      (await _delegate).cancelRange(fromId: fromId, toId: toId);

  @override
  Future<List<int>> pendingIds() async => (await _delegate).pendingIds();

  @override
  Future<bool> canScheduleExact() async => (await _delegate).canScheduleExact();

  @override
  Future<NotificationPermission> requestNotificationsPermission() async =>
      (await _delegate).requestNotificationsPermission();
}

/// Подготовить планировщик уведомлений (пакет 6.2).
///
/// Платформенный сервис требует асинхронной инициализации (база таймзон +
/// плагин), поэтому живёт в composition root, а не в провайдере (D-22).
/// Отказ **не валит старт**: приложение работает без напоминаний, а причина
/// уходит в лог — тишина вместо уведомлений была бы неотличима от «всё
/// запланировано» (урок 1).
///
/// W19: сама инициализация ограничена [kStartupTimeout] — подвисший плагин
/// или база таймзон не оставляет порт в вечном ожидании (напоминания не
/// сработают, и это видно как честная деградация с причиной).
Future<NotificationScheduler> initNotifications() async {
  try {
    final service = NotificationService(
      gateway: FlutterLocalNotificationsGateway(),
      timeZoneSource: const FlutterTimeZoneSource(),
      warn: debugPrint,
    );
    await service.initialize().timeout(kStartupTimeout);
    return NotificationSchedulerAdapter(service);
  } catch (error, stack) {
    debugPrint('Уведомления недоступны: $error\n$stack');
    return DegradedNotificationScheduler(reason: '$error', warn: debugPrint);
  }
}

/// Регистрирует и инициализирует модули приложения.
///
/// Порядок регистрации = порядок инициализации (контракт 6.6):
///   database (ленивое соединение, disk-free на старте) →
///   storage (нужен preset_manager для чтения активного id) →
///   config (загрузка пресетов) → preset_manager (читает БД+storage).
/// Повторный вызов (retry с экрана восстановления) сначала корректно
/// диспопит прошлую попытку — disposeAll гарантирует очистку (6.2).
///
/// Возвращает сервисы (null при фатальном отказе) и вердикт старта.
Future<(AppServices?, StartupOutcome)> bootstrapServices() async {
  final registry = ModuleRegistry.instance;
  // C3: очистка прошлой попытки обязана состояться при любом исходе и не
  // имеет права отменить пересоздание реестра. `disposeAll` намеренно
  // переподнимает первую ошибку диспоза (строгая семантика для тестов) — но
  // здесь вызов идёт с экрана восстановления, где отказ диспоза ленивой базы
  // превращал «Попробовать снова» в вечный отказ. Лог + продолжение.
  try {
    await registry.disposeAll();
  } catch (error, stack) {
    debugPrint('Реестр очистился с ошибкой, пересоздаём всё равно: '
        '$error\n$stack');
  }

  final databaseModule = DatabaseModule();
  final storageModule = StorageModule();
  final configModule = ConfigModule();
  // PresetManager uses lazy access to database via callback
  final presetManager = PresetManager(
    () => databaseModule.database,
    storageModule,
    // Шина: смена пресета — триггер перепланирования напоминаний (D-36).
    eventBus: EventBus.instance,
  );

  registry.register(databaseModule);
  registry.register(storageModule);
  registry.register(configModule);
  registry.register(presetManager);

  final outcome = await bootstrapModules(registry);
  if (!outcome.ok) {
    return (null, outcome);
  }

  // Dev-посев: вместо хардкода практик — применение реального пресета
  // через реальный путь (B-3/3.4). Только debug и только если традиция ещё
  // не выбрана; отказ seeding — деградация, не катастрофа (5.4).
  if (kDebugMode) {
    try {
      await DevSeeder.seedIfEmpty(
        presets: presetManager,
        config: configModule,
      );
    } catch (error) {
      debugPrint('Dev-посев пропущен: $error');
    }
  }

  return (
    AppServices(
      config: configModule,
      presetManager: presetManager,
      database: databaseModule.database,
    ),
    outcome,
  );
}

class DharmaToolkitApp extends ConsumerStatefulWidget {
  const DharmaToolkitApp({super.key});

  @override
  ConsumerState<DharmaToolkitApp> createState() => _DharmaToolkitAppState();
}

class _DharmaToolkitAppState extends ConsumerState<DharmaToolkitApp> {
  /// Ошибка проводки порта планировщика (DI-гард `notificationSchedulerProvider`
  /// сработал): напоминания не работают — состояние обязано быть видимым (W20).
  /// Прежний `try/catch` вокруг `ref.read` глушил ошибку проводки в лог, и
  /// корень без оверрайда портов «молчал».
  bool _notificationWiringFailed = false;

  ProviderSubscription<NotificationReplanner>? _replannerSubscription;

  @override
  void initState() {
    super.initState();
    // Первый потребитель шины (D-21): перепланирование напоминаний на старте
    // и на смену пресета/настроек (D-36). W20: `ref.listen` (в initState —
    // `listenManual`) + видимый флаг вместо catch: отказ приходит в `onError`
    // и поднимает баннер, а не растворяется в логе.
    _replannerSubscription = ref.listenManual<NotificationReplanner>(
      notificationReplannerProvider,
      (_, replanner) => replanner.start(),
      fireImmediately: true,
      onError: (error, stack) {
        debugPrint('Перепланирование уведомлений не запущено: $error\n$stack');
        if (mounted) {
          setState(() => _notificationWiringFailed = true);
        }
      },
    );
  }

  @override
  void dispose() {
    _replannerSubscription?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Дхарма-тулкит',
      // ru-локаль: русские системные строки Material (R-15, D-28).
      locale: appLocale,
      supportedLocales: appSupportedLocales,
      localizationsDelegates: appLocalizationsDelegates,
      routerConfig: ref.watch(routerProvider),
      // Dev-хук демо-напоминания (6.3, блок A): кнопка рисуется только под
      // гейтом `kDebugMode` (см. DebugNotificationButton) — в release здесь
      // остаётся пустой слой. Живёт в composition root, потому что только он
      // вправе связывать UI с портом фичи событий.
      builder: (context, child) => Stack(
        children: [
          ?child,
          const Positioned(
            right: 16,
            bottom: 96,
            child: DebugNotificationButton(),
          ),
          // W1: запрос рантайм-разрешения на уведомления при первом входе и
          // честный статус отказа на экране. Запрос идёт первым чтением
          // провайдера из баннера — это и есть UI-контекст (Activity).
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: NotificationPermissionBanner(),
          ),
          // W20: ошибка проводки порта планировщика видна, а не проглочена.
          if (_notificationWiringFailed)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _NotificationWiringBanner(),
            ),
        ],
      ),
    );
  }
}

/// Видимый флаг отказа проводки уведомлений (W20).
///
/// Показывается, когда DI-гард планировщика сработал: напоминаний не будет, и
/// пользователь (а в разработке — и автор проводки) видит причину на экране,
/// а не пустоту. В штатной сборке недостижим: composition root всегда даёт
/// оверрайд порта.
class _NotificationWiringBanner extends StatelessWidget {
  const _NotificationWiringBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Material(
        color: scheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            'Напоминания не подключены: планировщик уведомлений не '
            'сконфигурирован (ошибка проводки).',
            style: TextStyle(color: scheme.onErrorContainer),
          ),
        ),
      ),
    );
  }
}
