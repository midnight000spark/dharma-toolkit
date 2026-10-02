/// Обработчики жизненного цикла (W21): смена суток и часового пояса.
///
/// Приложение может висеть в фоне через полночь или пережить смену зоны
/// устройства. Без наблюдателя открытый экран показывает вчерашний день, а
/// план напоминаний остаётся собранным на вчера. Здесь проверяются обе
/// половины фикса:
/// - [todayProvider] — единственный источник «сегодня» с таймером полуночи,
///   от которого зависят дневные часы фич;
/// - [DayChangeWatcher] — реакция на возврат приложения из фона.
///
/// Часы инъектируемы: тест двигает их вручную (урок 5), а не спит до полуночи
/// и не зависит от часового пояса раннера.
library;

import 'package:dharma_toolkit/features/content/presentation/providers/content_providers.dart';
import 'package:dharma_toolkit/features/events/presentation/providers/event_providers.dart';
import 'package:dharma_toolkit/main.dart'
    show DayChangeWatcher, dayOrZoneChanged;
import 'package:dharma_toolkit/shared/providers/app_providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Полная последовательность возврата Android (inactive → hidden → paused →
/// hidden → inactive → resumed): `AppLifecycleListener` проверяет легальность
/// переходов, поэтому событие приходит из платформы именно так.
void _resumeApp(WidgetTester tester) {
  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('todayProvider — источник «сегодня» (W21)', () {
    test('nextLocalMidnight нормализует конец месяца и года', () {
      expect(
        nextLocalMidnight(DateTime(2026, 6, 1, 23, 59)),
        DateTime(2026, 6, 2),
      );
      expect(
        nextLocalMidnight(DateTime(2026, 6, 30, 12)),
        DateTime(2026, 7, 1),
      );
      expect(
        nextLocalMidnight(DateTime(2026, 12, 31, 23, 59)),
        DateTime(2027, 1, 1),
      );
    });

    test('инвалидация пересчитывает день от текущих часов — этим путём идут '
        'таймер полуночи и возврат приложения', () {
      var now = DateTime(2026, 6, 1, 23, 59);
      final container = ProviderContainer(
        overrides: [todayClockProvider.overrideWithValue(() => now)],
      );
      addTearDown(container.dispose);

      expect(container.read(todayProvider), DateTime(2026, 6, 1));

      // Полночь прошла. В бою провайдер инвалидирует таймер (foreground) или
      // обработчик возврата (background) — оба пути проверяются ниже.
      now = DateTime(2026, 6, 2, 0, 1);
      container.invalidate(todayProvider);

      expect(
        container.read(todayProvider),
        DateTime(2026, 6, 2),
        reason: 'день обязан пересчитаться, а не остаться вчерашним',
      );
    });

    test('дневные часы фич пересоздаются при смене суток', () async {
      var now = DateTime(2026, 6, 1, 23, 59);
      final container = ProviderContainer(
        overrides: [todayClockProvider.overrideWithValue(() => now)],
      );
      addTearDown(container.dispose);

      var contentRebuilds = 0;
      var eventsRebuilds = 0;
      // Часы — канонизированные tear-off'ы статических методов, поэтому
      // «пересоздались ли» проверяется уведомлением слушателя, а не identity.
      container.listen(
        contentClockProvider,
        (_, _) => contentRebuilds++,
        fireImmediately: true,
      );
      container.listen(
        eventsClockProvider,
        (_, _) => eventsRebuilds++,
        fireImmediately: true,
      );

      // Смена суток: часы ушли за полночь, затем инвалидация (в бою её делает
      // таймер полуночи или обработчик возврата). Часы фич обязаны
      // пересоздаться вместе с todayProvider, иначе дневные экраны останутся
      // на вчерашнем дне.
      now = DateTime(2026, 6, 2, 0, 1);
      container.invalidate(todayProvider);
      // Riverpod распространяет инвалидацию по зависимостям в конце витка
      // цикла событий — даём уведомлениям дойти.
      await pumpEventQueue();

      expect(
        contentRebuilds,
        2,
        reason: 'часы контента обязаны зависеть от сегодняшнего дня (W21)',
      );
      expect(
        eventsRebuilds,
        2,
        reason: 'часы событий обязаны зависеть от сегодняшнего дня (W21)',
      );
    });

    test('таймер полуночи сам пересчитывает день без перезапуска', () async {
      // «Сейчас» — за 200 мс до полуночи: таймер заводится на этот интервал,
      // поэтому проверка короткая и не спит до настоящей полуночи.
      var now = DateTime(2026, 6, 1, 23, 59, 59, 800);
      final container = ProviderContainer(
        overrides: [todayClockProvider.overrideWithValue(() => now)],
      );
      addTearDown(container.dispose);

      var notifies = 0;
      container.listen(
        todayProvider,
        (_, _) => notifies++,
        fireImmediately: true,
      );
      expect(container.read(todayProvider), DateTime(2026, 6, 1));

      // Полночь прошла: таймер обязан сам инвалидировать день.
      now = DateTime(2026, 6, 2, 0, 0, 0, 100);
      await Future<void>.delayed(const Duration(milliseconds: 500));

      expect(
        notifies,
        2,
        reason: 'экран, открытый через полночь, обязан пересчитаться сам',
      );
      expect(container.read(todayProvider), DateTime(2026, 6, 2));
    });
  });

  group('DayChangeWatcher — возврат приложения (W21)', () {
    test('dayOrZoneChanged сравнивает и сутки, и смещение зоны', () {
      final day = DateTime(2026, 6, 2);
      const offset = Duration(hours: 3);

      expect(
        dayOrZoneChanged(
          previousDay: day,
          previousOffset: offset,
          day: day,
          offset: offset,
        ),
        isFalse,
        reason: 'первый снимок ничего не «меняет»',
      );
      expect(
        dayOrZoneChanged(
          previousDay: DateTime(2026, 6, 1),
          previousOffset: offset,
          day: day,
          offset: offset,
        ),
        isTrue,
        reason: 'смена суток',
      );
      expect(
        dayOrZoneChanged(
          previousDay: day,
          previousOffset: offset,
          day: day,
          offset: const Duration(hours: 4),
        ),
        isTrue,
        reason: 'смена часового пояса',
      );
    });

    testWidgets('возврат после смены суток зовёт onChanged (onResume)', (
      tester,
    ) async {
      var now = DateTime(2026, 6, 1, 23, 59);
      var changes = 0;
      final watcher = DayChangeWatcher(
        onChanged: () => changes++,
        clock: () => now,
      );
      final listener = watcher.start();
      addTearDown(listener.dispose);

      // Возврат в те же сутки: пересборки нет — иначе каждый resume дёргал бы
      // экраны и перепланирование впустую.
      _resumeApp(tester);
      expect(changes, 0);

      now = DateTime(2026, 6, 2, 0, 1);
      _resumeApp(tester);

      expect(
        changes,
        1,
        reason: 'смена суток обязана разбудить дневные экраны и план',
      );
    });
  });
}
