/// Первый потребитель шины событий (D-21) — перепланирование напоминаний
/// (блок E пакета 6.2).
///
/// До этого пакета `EventBus` был реализован и протестирован, но в `lib/` его
/// никто не слушал (D-21: «шина ждёт реального потребителя»). Потребитель —
/// этот класс: смена активного пресета и правка настроек уведомлений меняют
/// план напоминаний (D-36), а знать о фиче событий ни менеджер пресетов, ни
/// хранилище настроек не должны — ровно та развязка, ради которой шина
/// существует (D-5).
///
/// **Почему триггер, а не поток.** Событие приходит **раньше**, чем реактивная
/// проводка UI доедет до новых значений: `PresetManager` публикует его сразу
/// после присвоения активного пресета, а цепочка потоковых провайдеров
/// (пресет → тег → настройки) проходит ещё несколько асинхронных шагов. Если
/// строить план «из провайдеров», после смены традиции уведомления оказались бы
/// поставлены по **старой** — это видимая ошибка (напоминания чужой традиции).
/// Поэтому [buildPlan] обязана читать состояние самой (текущий пресет напрямую
/// и настройки из хранилища по её тегу), а не реактивный слой UI.
///
/// **Честность отказов.** Ошибка построения плана или планирования не валит
/// приложение и не молчит: она идёт в лог с причиной. Напоминания — не то,
/// ради чего стоит падать, но и не то, о чём можно промолчать.
library;

import 'dart:async';

import '../../../core/events/event_bus.dart';
import '../../../core/events/notification_events.dart';
import '../../../core/events/preset_events.dart';
import '../domain/notification_plan.dart';
import '../domain/notification_scheduler.dart';

/// Слушает шину и применяет план напоминаний идемпотентно.
class NotificationReplanner {
  NotificationReplanner({
    required this.bus,
    required this.scheduler,
    required this.buildPlan,
    this.warn,
  });

  /// Шина, события которой меняют план напоминаний (D-21).
  final EventBus bus;

  /// Куда применяется план (порт 6.1; платформенный адаптер — 6.2).
  final NotificationScheduler scheduler;

  /// Сборка плана по состоянию **на момент вызова** (см. doc-комментарий
  /// библиотеки: реактивный слой к этому моменту ещё не переключился).
  final Future<NotificationPlan> Function() buildPlan;

  /// Куда писать отказы (в приложении — `debugPrint`).
  final void Function(String message)? warn;

  StreamSubscription<PresetChanged>? _presetSubscription;
  StreamSubscription<NotificationSettingsChanged>? _settingsSubscription;

  /// Очередь перепланирований: события не должны накладываться друг на друга
  /// (два применения плана одновременно дали бы дубли уведомлений — существо
  /// гонки B-8, только на слое планирования).
  Future<void> _queue = Future<void>.value();

  /// Журнал последнего применения плана (C7): снимок плана + исход по
  /// пунктам. Фундамент W2 — снятие показанного по журналу последнего плана.
  NotificationApplicationJournal? get lastJournal => _lastJournal;
  NotificationApplicationJournal? _lastJournal;

  /// Сколько применений плана завершилось без единого отказа (диагностика).
  int get appliedPlans => _appliedPlans;
  int _appliedPlans = 0;

  /// Сколько применений деградировало (часть пунктов не поставлена; C7).
  int get degradedPlans => _degradedPlans;
  int _degradedPlans = 0;

  /// Сколько перепланирований не удалось **собрать** (W3): сборка плана (в том
  /// числе чтение настроек) отказала после ограниченного повтора. Отличие от
  /// [degradedPlans]: там план собран, но часть пунктов платформа не приняла;
  /// здесь плана нет вовсе — полоса снимается пустым применением.
  int get replanFailures => _replanFailures;
  int _replanFailures = 0;

  /// Сколько попыток сборки плана делается за один проход (W3): первичная плюс
  /// один ограниченный retry. Транзиентный отказ чтения (занятая БД, гонка
  /// смены пресета) успевает уйти, бесконечного цикла нет.
  static const int buildAttempts = 2;

  /// Отработали ли все полученные события (тесты ждут это, а не таймеры).
  Future<void> get settled => _queue;

  /// Слушаем шину?
  bool get isListening => _presetSubscription != null;

  /// Старт приложения: перепланировать сейчас (D-36 — «старт приложения»
  /// в списке триггеров) и встать на прослушивание.
  void start() {
    listen();
    unawaited(replanNow());
  }

  /// Подписаться на события, меняющие план. Повторный вызов — no-op
  /// (двойная подписка дала бы двойное перепланирование).
  void listen() {
    if (isListening) return;
    _presetSubscription =
        bus.on<PresetChanged>().listen((_) => replanNow());
    _settingsSubscription =
        bus.on<NotificationSettingsChanged>().listen((_) => replanNow());
  }

  /// Снять подписки (диспозиция провайдера-владельца).
  Future<void> stop() async {
    await _presetSubscription?.cancel();
    await _settingsSubscription?.cancel();
    _presetSubscription = null;
    _settingsSubscription = null;
  }

  /// Поставить перепланирование в очередь и вернуть его ожидание.
  Future<void> replanNow() {
    // Ошибки внутри _replan не рвут цепочку: следующий триггер обязан
    // сработать даже после неудачного (иначе одно падение планирования
    // выключило бы напоминания до перезапуска).
    _queue = _queue.then((_) => _replan());
    return _queue;
  }

  Future<void> _replan() async {
    final plan = await _buildPlanWithRetry();
    if (plan == null) {
      // W3: отказ сборки не оставляет прежнюю полосу жить. Пользователь мог
      // выключить уведомления или сменить традицию, а старая полоса осталась
      // бы звонить — поэтому пустое применение (снять полосу) обязательно, а
      // отказ — видимый: метрика [replanFailures] + запись в лог.
      _replanFailures++;
      warn?.call('Перепланирование уведомлений не выполнено: сборка плана '
          'отказала $buildAttempts раз(а); полоса снимается пустым планом. '
          '$_lastBuildError\n$_lastBuildStack');
      await _clearBandAfterFailure();
      return;
    }
    try {
      // W2: id прошлого плана снимаются отдельно — показанное уведомление не
      // числится ожидающим, и платформа может его не перечислить (журнал C7
      // помнит, что ставило приложение). Журнал берётся до применения: новый
      // снимок заменит его только после успешной постановки.
      final previousPlanIds =
          _lastJournal?.plan.items.map((i) => i.id) ?? const [];
      // Применение по пунктам (C7): одно упавшее уведомление не срывает
      // остальные; исход каждого пункта — в журнале.
      final journal = await applyNotificationPlan(
        scheduler,
        plan,
        previousPlanIds: previousPlanIds,
      );
      _lastJournal = journal;
      if (journal.isDegraded) {
        // Частичный отказ: деградация видима в логе и метрике, поставленное
        // не откатывается (часть напоминаний полезнее пустоты).
        _degradedPlans++;
        warn?.call('Перепланирование уведомлений деградировало: не поставлено '
            '${journal.failedIds.length} из ${plan.items.length} '
            '(ids: ${journal.failedIds.join(', ')})');
      } else {
        _appliedPlans++;
      }
    } catch (error, stack) {
      warn?.call('Перепланирование уведомлений не выполнено: $error\n$stack');
    }
  }

  Object? _lastBuildError;
  StackTrace? _lastBuildStack;

  /// Сборка плана с ограниченным повтором (W3): `null` — все попытки отказали.
  Future<NotificationPlan?> _buildPlanWithRetry() async {
    for (var attempt = 0; attempt < buildAttempts; attempt++) {
      try {
        return await buildPlan();
      } catch (error, stack) {
        _lastBuildError = error;
        _lastBuildStack = stack;
      }
    }
    return null;
  }

  /// Снять полосу после отказа сборки (W3), не подменяя журнал последнего
  /// **построенного** плана: журнал — фундамент W2, и неудачная пересборка не
  /// имеет права потерять знание о поставленном (см. тест «журнал не
  /// подменяет»). Снятие идёт с id прошлого журнала: доставленное тоже уходит.
  Future<void> _clearBandAfterFailure() async {
    final previousPlanIds =
        _lastJournal?.plan.items.map((i) => i.id) ?? const [];
    try {
      await applyNotificationPlan(
        scheduler,
        NotificationPlan.empty,
        previousPlanIds: previousPlanIds,
      );
    } catch (error, stack) {
      warn?.call('Полоса напоминаний не очищена после отказа сборки плана: '
          '$error\n$stack');
    }
  }
}
