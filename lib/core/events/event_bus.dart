import 'dart:async';

import 'app_event.dart';

/// Event bus: модули публикуют и принимают события, не зная друг о друге —
/// ключ к модульности (D-5).
///
/// Реализуема напрямую ([EventBus]) — независимые инстансы для тестов и
/// локальной проводки (R-12). [EventBus.instance] — предсозданный глобальный
/// автобус на будущее (Этап 6, D-21: реального потребителя в приложении пока
/// нет); в тестах его НЕ диспозят — иначе следующий тест молча получает
/// пустоту.
///
/// Публикация в закрытый автобус — ошибка разработчика, а не тишина:
/// [publish] после [dispose] бросает [StateError] (R-12: проверка isClosed
/// превращала баг проводки в недиагностируемое «событие не пришло»).
class EventBus {
  /// Новый независимый автобус (тесты, локальная композиция).
  EventBus();

  /// Глобальный автобус приложения. Создаётся заранее; подключение потребителя
  /// — Этап 6 (D-21).
  static final EventBus instance = EventBus();

  final _controller = StreamController<AppEvent>.broadcast();
  bool _disposed = false;

  /// Автобус закрыт [dispose]?
  bool get isDisposed => _disposed;

  /// Publish an event. All subscribers will receive it asynchronously.
  ///
  /// Throws [StateError] if the bus was disposed — публиковать в мёртвую шину
  /// бессмысленно, и молча глотать событие запрещено (R-12).
  void publish(AppEvent event) {
    if (_disposed) {
      throw StateError(
        'EventBus опубликовал событие после dispose: проводка обращается к '
        'закрытому автобусу. Проверьте, не диспозится ли шина раньше времени '
        '(глобальный EventBus.instance в тестах не диспозят — создайте '
        'локальный EventBus()).',
      );
    }
    _controller.add(event);
  }

  /// Subscribe to events of a specific type T.
  ///
  /// Returns a Stream — the subscriber manages the subscription themselves.
  Stream<T> on<T extends AppEvent>() {
    return _controller.stream.where((e) => e is T).cast<T>();
  }

  /// Close the bus. Повторный вызов — no-op (закрытие идемпотентно, ошибки
  /// нет; ошибка — только на публикацию в закрытый автобус).
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _controller.close();
  }
}
