import '../module/app_module.dart';
import 'app_database.dart';

/// Module wrapping the Drift database.
///
/// Provides [AppDatabase] instance to other modules after initialization.
/// The database is created on [init] and closed on [dispose].
class DatabaseModule implements AppModule {
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
    _database = AppDatabase();
  }

  @override
  Future<void> dispose() async {
    await _database?.close();
    _database = null;
  }
}
