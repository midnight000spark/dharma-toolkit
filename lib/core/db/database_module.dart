import 'package:drift/drift.dart' show QueryExecutor;
import 'package:flutter/foundation.dart';

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
    final db =
        executor == null ? AppDatabase() : AppDatabase.withExecutor(executor);
    _database = db;

    // C1(2): «критичный модуль, который не может упасть» — прежний init только
    // конструировал AppDatabase над LazyDatabase, файл не открывался, и
    // повреждение базы физически не могло попасть в fatalFailures: оно
    // всплывало текстом на экране списка практик вместо экрана восстановления.
    // Активный зонд обязан открывать соединение здесь.
    //
    // Выбор `PRAGMA quick_check`, а не `SELECT count(*) FROM sqlite_master`:
    // второй ловит только «это вообще не база», а обрезанный/битостраничный
    // файл проходит. Цена — обход страниц (стоимость растёт с размером базы);
    // вопрос таймаута и выноса зонда за критический путь — W19, не этот пакет.
    try {
      await db.customSelect('PRAGMA quick_check').get();
    } catch (error, stack) {
      debugPrint('Зонд целостности БД не прошёл: $error\n$stack');
      _database = null;
      // Соединение закрываем в любом случае: у LazyDatabase, у которого opener
      // упал, ошибка кешируется, и close() пере-бросит её сюда второй раз.
      try {
        await db.close();
      } catch (closeError) {
        debugPrint('Закрытие после отказа зонда: $closeError');
      }
      // Отказ наружу: `database` входит в kCriticalModuleIds, и теперь это
      // действительно фатал с причиной, а не тихая работа «на честном слове».
      Error.throwWithStackTrace(error, stack);
    }
  }

  @override
  Future<void> dispose() async {
    await _database?.close();
    _database = null;
  }
}
