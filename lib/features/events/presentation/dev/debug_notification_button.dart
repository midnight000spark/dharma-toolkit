/// Dev-хук быстрого показа напоминания (блок A пакета 6.3).
///
/// **Зачем.** Приёмочный контур (а) доказывает живое срабатывание **планового**
/// будильника, но требует перевода часов эмулятора и минуты ожидания у границы
/// расписания. Для повседневной разработки (и для будущих пакетов) нужен
/// дешёвый прогон всего конвейера: «порт планировщика → платформа → показ».
/// Этот хук ставит напоминание на `now + 1 мин` **через настоящий порт**
/// ([NotificationScheduler], D-36/D-34) — тем же путём, которым идёт план, а не
/// через `show()` в обход планирования.
///
/// **Видимость.** Действие существует только под гейтом [debugDemoEnabled]
/// (в приложении — `kDebugMode`): в release кнопка не рисуется вовсе, а вызов
/// планирования гейтом не проходит. Гейт — **параметр**, а не только константа,
/// поэтому поведение «гейт выключен → действия нет» проверяется тестом, и
/// подмена дефолта обязана красить тест (урок 1: непроверяемое «выключено
/// в релизе» — не гарантия).
///
/// **Полоса id.** Демо живёт на верхней границе полосы приложения
/// ([NotificationPlan.idRangeEnd]): внутри полосы — значит перепланирование
/// своей отменой по диапазону снимет и его (D-36), наружу выходить нельзя.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/notification_plan.dart';
import '../../domain/notification_scheduler.dart';
import '../providers/event_providers.dart';

/// Включено ли dev-действие.
///
/// `gate` — точка подмены для тестов; `null` означает «решение приложения»,
/// то есть `kDebugMode`. Дефолт намеренно читает константу фреймворка, а не
/// литерал: литерал пришлось бы синхронизировать с режимом сборки вручную.
bool debugDemoEnabled({bool? gate}) => gate ?? kDebugMode;

/// Идентификатор демо-напоминания — верх полосы приложения (D-36).
const int debugDemoNotificationId = NotificationPlan.idRangeEnd;

/// Задержка демо-напоминания: минута — достаточно, чтобы успеть увидеть
/// показ в `dumpsys notification`, и мало, чтобы ждать руками.
const Duration debugDemoDelay = Duration(minutes: 1);

/// Пункт демо-напоминания на момент `now + delay`.
NotificationPlanItem buildDebugDemoItem({
  required DateTime now,
  Duration delay = debugDemoDelay,
}) =>
    NotificationPlanItem(
      id: debugDemoNotificationId,
      scheduledAt: now.add(delay),
      title: 'Демо: проверка напоминаний',
      body: 'Тестовое напоминание через минуту (dev-хук 6.3).',
      payload: '{"source":"debugDemo"}',
    );

/// Поставить демо-напоминание через реальный порт планировщика.
///
/// Возвращает `false`, если гейт выключен: вызывающий видит честное «действия
/// не было», а не «запланировано» (иначе молчаливый no-op выглядел бы как
/// успех — урок 1).
Future<bool> scheduleDebugDemoNotification({
  required NotificationScheduler scheduler,
  required DateTime now,
  bool? gate,
  Duration delay = debugDemoDelay,
}) async {
  if (!debugDemoEnabled(gate: gate)) return false;
  await scheduler.schedule(buildDebugDemoItem(now: now, delay: delay));
  return true;
}

/// Кнопка dev-действия: видна и работает только под гейтом.
///
/// Собирается из `Directionality`/`Material` собственных, чтобы её можно было
/// поставить в `MaterialApp.builder` (composition root) и в тест без
/// Scaffold-обвязки.
class DebugNotificationButton extends ConsumerStatefulWidget {
  const DebugNotificationButton({super.key, this.gate});

  /// Явное состояние гейта для тестов; `null` — как в приложении.
  final bool? gate;

  @override
  ConsumerState<DebugNotificationButton> createState() =>
      _DebugNotificationButtonState();
}

class _DebugNotificationButtonState
    extends ConsumerState<DebugNotificationButton> {
  String _label = 'demo +1 мин';
  bool _busy = false;

  Future<void> _fire() async {
    setState(() => _busy = true);
    try {
      final scheduled = await scheduleDebugDemoNotification(
        scheduler: ref.read(notificationSchedulerProvider),
        now: ref.read(eventsClockProvider)(),
        gate: widget.gate,
      );
      if (!mounted) return;
      setState(() => _label = scheduled ? 'запланировано' : 'гейт выключен');
    } catch (error) {
      // Отказ планирования виден на кнопке: молчаливая кнопка неотличима от
      // «нажатие не дошло».
      if (!mounted) return;
      setState(() => _label = 'отказ: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!debugDemoEnabled(gate: widget.gate)) return const SizedBox.shrink();
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _busy ? null : _fire,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              _label,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ),
      ),
    );
  }
}
