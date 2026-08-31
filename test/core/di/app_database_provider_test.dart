import 'package:dharma_toolkit/core/db/app_database.dart';
import 'package:dharma_toolkit/core/db/database_module.dart';
import 'package:dharma_toolkit/features/tracker/data/practice_repository.dart';
import 'package:dharma_toolkit/features/tracker/domain/practice.dart';
import 'package:dharma_toolkit/features/tracker/presentation/providers/practice_provider.dart';
import 'package:dharma_toolkit/shared/providers/app_providers.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// DI по D-22 (R-11, R-13): репозиторий получает БД только через
/// appDatabaseProvider с оверрайдом в composition root. Service locator
/// (`ModuleRegistry.instance.get`) в провайдерах отсутствует — эти тесты
/// падают, если его вернут (мутационная проверка 1.4).
/// disposeAll() here не нужен: реестр модулей в этих тестах не участвует.
void main() {
  late AppDatabase db;
  late ProviderContainer container;

  Future<PracticeEntity> seedPractice(AppDatabase database) {
    final repository = PracticeRepository(database);
    final now = DateTime(2026, 9, 1, 12);
    return repository
        .create(
          PracticeEntity(
            name: 'Простирания',
            type: 'counter',
            target: 100000,
            traditionTag: 'nyingma',
            createdAt: now,
            updatedAt: now,
          ),
        )
        .then((_) => repository.getByTradition('nyingma'))
        .then((rows) => rows.single);
  }

  setUp(() async {
    db = AppDatabase.forTesting(
      NativeDatabase.memory(setup: enableForeignKeys),
    );
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    await container.pump();
    await db.close();
  });

  test('провайдер репозитория видит данные оверрайда appDatabaseProvider',
      () async {
    // Сид — напрямую в memory-БД (минует провайдеры).
    final seeded = await seedPractice(db);

    // Провайдер (через репозиторий) обязан вернуть ровно эту строку:
    // значит репозиторий собран поверх оверрайда, а не service locator'а.
    final repository = container.read(practiceRepositoryProvider);
    final rows = await repository.getByTradition('nyingma');

    expect(rows, hasLength(1));
    expect(rows.single.id, seeded.id);
    expect(rows.single.name, 'Простирания');
  });

  test('репозиторий — один экземпляр на контейнер (кэш провайдера)', () {
    final a = container.read(practiceRepositoryProvider);
    final b = container.read(practiceRepositoryProvider);
    expect(identical(a, b), isTrue);
  });

  test('список практик через StreamProvider видит данные оверрайда',
      () async {
    await seedPractice(db);

    final sub = container.listen(
      practiceListProvider('nyingma'),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(sub.close);

    final value = await container.read(
      practiceListProvider('nyingma').future,
    );
    expect(value.map((p) => p.name), contains('Простирания'));
  });

  test('без оверрайда репозиторий падает явно (service locator запрещён)',
      () async {
    // Пустой реестр ModuleRegistry — если провайдер снова дотянет БД через
    // `ModuleRegistry.instance.get`, он молча вернёт репозиторий или упадёт
    // не той ошибкой. Явный UnimplementedError доказывает составной корень.
    final bare = ProviderContainer();
    addTearDown(bare.dispose);

    expect(
      () => bare.read(practiceRepositoryProvider),
      throwsUnimplementedError,
    );
  });

  test('DatabaseModule инъектируем: memory-исполнитель без обращения к ФС '
      '(R-13)', () async {
    final module = DatabaseModule(
      executor: NativeDatabase.memory(setup: enableForeignKeys),
    );
    addTearDown(module.dispose);

    await module.init();

    // Запись и чтение через БД модуля работают — соединение тестовое,
    // path_provider не требуется (иначе этот вызов упал бы без binding).
    final seeded = await seedPractice(module.database);
    expect(seeded.name, 'Простирания');

    // Инстанс ровно один на весь жизненный цикл модуля.
    expect(identical(module.database, module.database), isTrue);
  });
}
