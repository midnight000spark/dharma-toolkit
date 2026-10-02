import 'package:flutter/foundation.dart';

import '../module/module_registry.dart';

/// Модули, без которых приложение не может работать с локальными данными
/// (B-5). Отказ любого — аварийный экран, а не чёрный экран и не работа
/// «на честном слове»: offline-first без бэкенда локальное состояние —
/// единственное (D-6).
const Set<String> kCriticalModuleIds = {
  'database',
  'storage',
  'config',
  'preset_manager',
};

/// Итог старта: фатальные отказы критичных модулей и деградировавшие
/// некритичные (5.4: модули деградируют поодиночке, а не валят процесс).
class StartupOutcome {
  final List<ModuleInitFailure> fatalFailures;
  final List<ModuleInitFailure> degradedModules;

  const StartupOutcome({
    required this.fatalFailures,
    required this.degradedModules,
  });

  bool get ok => fatalFailures.isEmpty;

  /// Есть ли о чём сказать пользователю, кроме «приложение не запустилось»
  /// (S12-min): ограниченный режим — не то же самое, что отказ старта.
  bool get degraded => degradedModules.isNotEmpty;
}

/// Инициализация реестра с классификацией отказов.
///
/// Чистая функция над [registry]: реестр наполняет вызывающий (main/tests),
/// здесь решается только «фатально или деградация».
///
/// В `degradedModules` попадают два рода записей (C1(1)):
/// - некритичный модуль, бросивший в `initAll`;
/// - отказ, который критичный модуль пережил внутри себя и доложил через
///   [ReportsOwnFailures] — «битый один элемент», а не «подсистема легла».
/// Второе не может остаться молчащим: без строки на экране пользователь
/// видит «всё пропало» там, где приложение работает в ограниченном режиме,
/// и наоборот — не замечает потери активной традиции.
Future<StartupOutcome> bootstrapModules(
  ModuleRegistry registry, {
  Set<String> criticalIds = kCriticalModuleIds,
}) async {
  final report = await registry.initAll();
  final fatal = <ModuleInitFailure>[];
  final degraded = <ModuleInitFailure>[];
  for (final failure in report.failures) {
    if (criticalIds.contains(failure.moduleId)) {
      fatal.add(failure);
    } else {
      degraded.add(failure);
      debugPrint('Деградация модуля: $failure');
    }
  }
  // whereType вместо `is`-проверки: петлевая переменная Iterable<AppModule>
  // у analyzer не промотится в пересечение несвязанных интерфейсов.
  for (final reporter in registry.all.whereType<ReportsOwnFailures>()) {
    for (final failure in reporter.ownFailures) {
      degraded.add(failure);
      debugPrint('Деградация внутри модуля: $failure (${failure.kind.label})');
    }
  }
  return StartupOutcome(fatalFailures: fatal, degradedModules: degraded);
}

/// Что сейчас в корне приложения (C3).
///
/// Прежний флаг был булевым «корень смонтирован» — а [RecoveryApp] тоже
/// смонтированный корень, и для него «чинить нечего» оказывалось верным
/// ответом, из-за чего каждая попытка после первой уходила только в лог.
enum MountedRoot { none, recovery, app }

/// Граница ожидания старта (W19): bootstrap, не ответивший за это время, не
/// держит пользователя у пустого экрана — монтируется восстановление.
///
/// Первый кадр не может зависеть от того, ответит ли платформа вообще:
/// подвисший `opener` ленивой базы или молчащий плагин — это тот же чёрный
/// экран, от которого уходили в B-5, только по причине «никто не ответил», а
/// не «ответил отказом». Значение — компромисс: холодный старт с миграциями
/// (F-31, ~81 с build_runner — не рантайм) укладывается заметно ниже, а
/// человек не ждёт дольше, чем готов воспринимать пустоту.
const Duration kStartupTimeout = Duration(seconds: 3);

/// Один полный цикл старта (C3).
///
/// Вынесено из `main`, потому что контроль потока обязан ловиться тестом, а
/// тестировать `main` — значит `runApp` всё приложение. Правила:
/// - отказ bootstrap (в том числе на повторной попытке, где он исторически и
///   случался: `disposeAll` переподнимает ошибку ленивой базы) НЕ уходит
///   наружу — восстановление монтируется принудительно, с причиной;
/// - **зависший** bootstrap (W19) не блокирует первый кадр бесконечно: ожидание
///   ограничено [bootstrapTimeout], таймаут уходит тем же путём — в
///   восстановление с причиной, а не в тишину;
/// - бросок из [mountApp] — тоже;
/// - возвращается то, что теперь в корне: вызывающий хранит это как условие
///   «корень не рабочий» для обработчика асинхронных отказов.
///
/// [bootstrapTimeout] — параметр (не константа внутри), чтобы граница
/// проверялась детерминированным тестом за миллисекунды, а не за 3 секунды.
Future<MountedRoot> runStartupCycle<T>({
  required Future<(T?, StartupOutcome)> Function() bootstrap,
  required Future<void> Function(T services) mountApp,
  required void Function(Object error, StartupOutcome outcome) mountRecovery,
  Duration bootstrapTimeout = kStartupTimeout,
}) async {
  const noOutcome =
      StartupOutcome(fatalFailures: [], degradedModules: []);
  try {
    final (services, outcome) = await bootstrap().timeout(bootstrapTimeout);
    if (services == null || !outcome.ok) {
      mountRecovery(
        outcome.fatalFailures.isNotEmpty
            ? outcome.fatalFailures.first.error
            : StateError('Инициализация не завершена'),
        outcome,
      );
      return MountedRoot.recovery;
    }
    await mountApp(services);
    return MountedRoot.app;
  } catch (error, stack) {
    debugPrint('Старт не удался: $error\n$stack');
    mountRecovery(error, noOutcome);
    return MountedRoot.recovery;
  }
}
