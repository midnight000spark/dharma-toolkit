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
}

/// Инициализация реестра с классификацией отказов.
///
/// Чистая функция над [registry]: реестр наполняет вызывающий (main/tests),
/// здесь решается только «фатально или деградация».
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
  return StartupOutcome(fatalFailures: fatal, degradedModules: degraded);
}
