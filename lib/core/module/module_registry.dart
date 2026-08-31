import 'app_module.dart';

/// Отказ инициализации одного модуля (B-5: деградация поодиночке, а не
/// падение процесса).
class ModuleInitFailure {
  final String moduleId;
  final Object error;
  final StackTrace stackTrace;

  const ModuleInitFailure(this.moduleId, this.error, this.stackTrace);

  @override
  String toString() => 'Модуль "$moduleId" не инициализирован: $error';
}

/// Итог [ModuleRegistry.initAll]: какие модули не поднялись.
class ModuleInitReport {
  final List<ModuleInitFailure> failures;

  const ModuleInitReport(this.failures);

  bool get allOk => failures.isEmpty;
}

/// Application module registry. Singleton at runtime.
///
/// Stores all registered [AppModule] instances and manages their lifecycle.
/// Modules must be registered before [initAll] is called.
class ModuleRegistry {
  ModuleRegistry._();
  static final ModuleRegistry instance = ModuleRegistry._();

  final Map<String, AppModule> _modules = {};
  bool _initialized = false;

  /// Registers a module. Must be called before [initAll].
  ///
  /// Throws [StateError] if registry is already initialized.
  /// Throws [ArgumentError] if module with same id already registered.
  void register(AppModule module) {
    if (_initialized) {
      throw StateError('Cannot register module after registry is initialized');
    }
    if (_modules.containsKey(module.id)) {
      throw ArgumentError('Module with id "${module.id}" already registered');
    }
    _modules[module.id] = module;
  }

  /// Returns module by id, or null if not found.
  AppModule? get(String id) => _modules[id];

  /// Инициализирует все модули в порядке регистрации (B-5).
  ///
  /// Ошибки модулей собираются в [ModuleInitReport] и не прерывают запуск
  /// остальных: решение о фатальности принимает вызывающий (см.
  /// `core/recovery/startup.dart`), а процесс валится не сразу и не молча.
  ///
  /// Safe to call multiple times — subsequent calls are no-ops.
  Future<ModuleInitReport> initAll() async {
    if (_initialized) return const ModuleInitReport([]);
    final failures = <ModuleInitFailure>[];
    for (final module in _modules.values) {
      try {
        await module.init();
      } catch (error, stack) {
        failures.add(ModuleInitFailure(module.id, error, stack));
      }
    }
    _initialized = true;
    return ModuleInitReport(failures);
  }

  /// Disposes all modules in reverse registration order.
  ///
  /// Clears the registry and resets initialization state. Отказ [dispose]
  /// одного модуля не мешает диспозиться остальным (6.2): реестр обязан
  /// очищаться всегда, иначе повторный bootstrap невозможен. Первая ошибка
  /// переподнимается после полной очистки.
  Future<void> disposeAll() async {
    Object? firstError;
    StackTrace? firstStack;
    try {
      for (final module in _modules.values.toList().reversed) {
        try {
          await module.dispose();
        } catch (error, stack) {
          firstError ??= error;
          firstStack ??= stack;
        }
      }
    } finally {
      _modules.clear();
      _initialized = false;
    }
    if (firstError != null) {
      // ignore: only_throw_errors — пробрасываем исходный объект ошибки.
      Error.throwWithStackTrace(firstError, firstStack!);
    }
  }

  /// All registered modules (for testing and debugging).
  Iterable<AppModule> get all => _modules.values;
}
