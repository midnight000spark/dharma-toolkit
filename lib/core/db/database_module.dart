import 'package:drift/drift.dart' show QueryExecutor;

import '../module/app_module.dart';
import 'app_database.dart';

/// Module wrapping the Drift database.
///
/// Provides [AppDatabase] instance to other modules after initialization.
/// The database is created on [init] and closed on [dispose].
///
/// Инъекция [QueryExecutor] (R-13, D-22): без исполнителя модуль открывает
/// production-соединение (ленивый файл из path_provider); с исполнителем
/// (например, `NativeDatabase.memory()`) — тестовое соединение, и интеграционные
/// тесты не пишут в реальную ФС. Инстанс [AppDatabase] создаётся один раз в
/// [init] и живёт до [dispose].
class DatabaseModule implements AppModule {
  DatabaseModule({this._executor});

  final QueryExecutor? _executor;

  @override
  String get id => 'database';

  @override
  String get name => 'База данных';

  @override
  String get version => '1.0.0';

  AppDatabase? _database;

  /// Returns the initialized database.
  ///
  /// Throws [StateError] if accessed before [init] is called.
  AppDatabase get database {
    if (_database == null) {
      throw StateError('DatabaseModule not initialized');
    }
    return _database!;
  }

  @override
  Future<void> init() async {
    final executor = _executor;
    _database =
        executor == null ? AppDatabase() : AppDatabase.withExecutor(executor);
  }

  @override
  Future<void> dispose() async {
    await _database?.close();
    _database = null;
  }
}
