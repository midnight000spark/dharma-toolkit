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

  /// Сколько раз план успешно применён (диагностика и тесты).
  int get appliedPlans => _appliedPlans;
  int _appliedPlans = 0;

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
    try {
      final plan = await buildPlan();
      await applyNotificationPlan(scheduler, plan);
      _appliedPlans++;
    } catch (error, stack) {
      warn?.call('Перепланирование уведомлений не выполнено: $error\n$stack');
    }
  }
}
