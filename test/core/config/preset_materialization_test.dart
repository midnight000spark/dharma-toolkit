import 'package:dharma_toolkit/core/config/preset_manager.dart';
import 'package:dharma_toolkit/core/config/preset_schema.dart';
import 'package:dharma_toolkit/core/db/app_database.dart';
import 'package:dharma_toolkit/core/storage/storage_module.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Тесты материализации пресета (B-3, B-11, D-26).
///
/// Проверяют ПОВЕДЕНИЕ пути сохранения, а не отрисовку (урок 4):
/// дубли при повторном apply, сохранность счёта, каскад истории,
/// неприкосновенность кастомных практик.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late StorageModule storageModule;
  late PresetManager presetManager;

  final ny = PresetSchema(
    id: 'nyingma',
    name: 'Ньингма',
    version: '1.0.0',
    tradition: 'vajrayana',
    modules: ['tracker'],
    practices: [
      PresetPractice(
        id: 'ngondro_prostrations',
        name: 'Простирания',
        type: 'counter',
        target: 100000,
        unit: 'повторений',
      ),
      PresetPractice(
        id: 'ngondro_vajrasattva',
        name: 'Мантра Ваджрасаттвы',
        type: 'counter',
        target: 100000,
        unit: 'повторений',
      ),
      PresetPractice(
        id: 'ngondro_mandala',
        name: 'Подношение мандал',
        type: 'counter',
        target: 100000,
        unit: 'повторений',
      ),
      PresetPractice(
        id: 'ngondro_guru_yoga',
        name: 'Гуру-йога',
        type: 'counter',
        target: 100000,
        unit: 'повторений',
      ),
    ],
    eventPacks: [],
    contentPacks: [],
  );

  final th = PresetSchema(
    id: 'theravada_default',
    name: 'Тхеравада',
    version: '1.0.0',
    tradition: 'theravada',
    modules: ['tracker'],
    practices: [],
    eventPacks: [],
    contentPacks: [],
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // FK включаем как в проде (I-2): каскад без PRAGMA — бумага.
    database = AppDatabase.forTesting(
      NativeDatabase.memory(setup: enableForeignKeys),
    );
    storageModule = StorageModule();
    await storageModule.init();
    presetManager = PresetManager(() => database, storageModule);
    await presetManager.init();
  });

  tearDown(() async {
    await presetManager.dispose();
    await storageModule.dispose();
    await database.close();
  });

  Future<List<Practice>> nyPractices() =>
      (database.select(database.practices)
            ..where((t) => t.traditionTag.equals('nyingma'))
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
          .get();

  group('applyPreset материализует практики (B-3)', () {
    test('применение Ньингма создаёт четыре практики в порядке пресета',
        () async {
      await presetManager.applyPreset(ny);

      final rows = await nyPractices();
      expect(rows, hasLength(4));
      expect(
        rows.map((r) => r.name),
        ['Простирания', 'Мантра Ваджрасаттвы', 'Подношение мандал', 'Гуру-йога'],
      );
      expect(rows.every((r) => r.target == 100000), isTrue);
      expect(rows.every((r) => r.presetPracticeId != null), isTrue);
      expect(rows.every((r) => r.currentCount == 0), isTrue);
    });

    test('apply дважды — строк не прибавилось (регрессия на дубли B-3)',
        () async {
      await presetManager.applyPreset(ny);
      await presetManager.applyPreset(ny);

      final rows = await nyPractices();
      expect(rows, hasLength(4));
    });

    test('повторный apply сохраняет насчитанный счёт и не трогает кастомные',
        () async {
      await presetManager.applyPreset(ny);

      // Насчитали простираниям.
      final first = (await nyPractices()).first;
      await (database.update(database.practices)
            ..where((t) => t.id.equals(first.id)))
          .write(const PracticesCompanion(currentCount: Value(108)));

      // Кастомная практика (без presetPracticeId) рядом с пресетными.
      await database.into(database.practices).insert(
            PracticesCompanion.insert(
              name: 'Моя личная практика',
              type: 'counter',
              traditionTag: 'nyingma',
            ),
          );

      await presetManager.applyPreset(ny);

      final rows = await nyPractices();
      expect(rows, hasLength(5),
          reason: 'кастомная не удалена и не задвоена');
      final prostrations =
          rows.firstWhere((r) => r.presetPracticeId == 'ngondro_prostrations');
      expect(prostrations.currentCount, 108,
          reason: 'счёт практикующего пережил повторное применение');
    });

    test('пресетные строки переживают смену традиции и возврат (D-26)',
        () async {
      await presetManager.applyPreset(ny);
      final first = (await nyPractices()).first;
      await (database.update(database.practices)
            ..where((t) => t.id.equals(first.id)))
          .write(const PracticesCompanion(currentCount: Value(21000)));

      //Switch туда: Тхеравада — свой тег, пустой список своих практик.
      await presetManager.switchPreset(th);
      final tag = presetManager.activePreset!.id;
      final thRows = await (database.select(database.practices)
            ..where((t) => t.traditionTag.equals(tag)))
          .get();
      expect(thRows, isEmpty);
      // Данные Ньингма НЕ удалены при смене (FR-ONB-4).
      expect(await nyPractices(), hasLength(4));

      // Switch обратно: те же строки с сохранённым счётом.
      await presetManager.switchPreset(ny);
      final back = await nyPractices();
      expect(back, hasLength(4));
      final restored =
          back.firstWhere((r) => r.presetPracticeId == 'ngondro_prostrations');
      expect(restored.currentCount, 21000);
      expect(restored.id, first.id, reason: 'та же строка, не новая');
    });

    test('reset не удаляет данные; повторный apply восстанавливает счёт (D-26)',
        () async {
      await presetManager.applyPreset(ny);
      final first = (await nyPractices()).first;
      await (database.update(database.practices)
            ..where((t) => t.id.equals(first.id)))
          .write(const PracticesCompanion(currentCount: Value(777)));

      await presetManager.resetPreset();
      expect(presetManager.activePreset, isNull);
      expect(await nyPractices(), hasLength(4),
          reason: 'reset — только снятие активного пресета, не удаление');

      await presetManager.applyPreset(ny);
      final again = await nyPractices();
      expect(again, hasLength(4));
      expect(
        again.firstWhere((r) => r.id == first.id).currentCount,
        777,
      );
    });

    test('удаление практики каскадом убирает историю (B-11)', () async {
      await presetManager.applyPreset(ny);
      final first = (await nyPractices()).first;

      await database.into(database.countHistory).insert(
            CountHistoryCompanion.insert(practiceId: first.id, count: 7),
          );
      expect(await (database.select(database.countHistory)).get(),
          hasLength(1));

      await (database.delete(database.practices)
            ..where((t) => t.id.equals(first.id)))
          .go();

      final history = await database.select(database.countHistory).get();
      expect(history, isEmpty,
          reason: 'FK ON DELETE CASCADE + PRAGMA foreign_keys = ON');
    });

    test('activePresetStream отдаёт текущий пресет и изменения', () async {
      expect(await presetManager.activePresetStream.first, isNull);

      final seen = <String?>[];
      final sub =
          presetManager.activePresetStream.listen((p) => seen.add(p?.id));

      await presetManager.applyPreset(ny);
      await presetManager.resetPreset();
      await Future<void>.delayed(Duration.zero);

      // Первый элемент — текущее значение при подписке (null),
      // далее — применения/сбросы.
      expect(seen, [null, 'nyingma', null]);
      await sub.cancel();
    });
  });
}
