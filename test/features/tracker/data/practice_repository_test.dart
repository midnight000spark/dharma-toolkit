import 'dart:io';

import 'package:dharma_toolkit/core/db/app_database.dart';
import 'package:dharma_toolkit/features/tracker/data/practice_repository.dart';
import 'package:dharma_toolkit/features/tracker/domain/practice.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PracticeRepository persistence', () {
    test('данные переживают перезапуск (файловая БД)', () async {
      // Создаём временный файл для БД
      final tempDir = await Directory.systemTemp.createTemp('dharma_test_');
      final dbPath = '${tempDir.path}/test.sqlite';

      // Первая сессия: создаём практику и инкрементим
      {
        final db = AppDatabase.forTesting(NativeDatabase(File(dbPath), setup: enableForeignKeys));
        final repo = PracticeRepository(db);

        final now = DateTime.now();
        final practiceId = await repo.create(PracticeEntity(
          name: 'Тестовая практика',
          type: 'counter',
          target: 100,
          traditionTag: 'test',
          createdAt: now,
          updatedAt: now,
        ));

        await repo.incrementCount(practiceId, 5);

        await db.close();
      }

      // Вторая сессия: открываем ту же БД и проверяем счёт
      {
        final db = AppDatabase.forTesting(NativeDatabase(File(dbPath), setup: enableForeignKeys));
        final repo = PracticeRepository(db);

        final practices = await repo.getByTradition('test');
        expect(practices.length, 1);
        expect(practices.first.currentCount, 5);
        expect(practices.first.name, 'Тестовая практика');

        await db.close();
      }

      // Очищаем
      await tempDir.delete(recursive: true);
    });

    test('изоляция по traditionTag', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
      final repo = PracticeRepository(db);

      final now = DateTime.now();

      // Создаём практики для разных традиций
      await repo.create(PracticeEntity(
        name: 'Sample практика',
        type: 'counter',
        traditionTag: 'sample',
        createdAt: now,
        updatedAt: now,
      ));

      await repo.create(PracticeEntity(
        name: 'Nyingma практика',
        type: 'counter',
        traditionTag: 'nyingma',
        createdAt: now,
        updatedAt: now,
      ));

      // Проверяем изоляцию
      final samplePractices = await repo.getByTradition('sample');
      expect(samplePractices.length, 1);
      expect(samplePractices.first.name, 'Sample практика');

      final nyingmaPractices = await repo.getByTradition('nyingma');
      expect(nyingmaPractices.length, 1);
      expect(nyingmaPractices.first.name, 'Nyingma практика');

      await db.close();
    });

    test('incrementCount обновляет currentCount', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
      final repo = PracticeRepository(db);

      final now = DateTime.now();
      final practiceId = await repo.create(PracticeEntity(
        name: 'Тест',
        type: 'counter',
        traditionTag: 'test',
        createdAt: now,
        updatedAt: now,
      ));

      // Инкрементим несколько раз
      await repo.incrementCount(practiceId, 10);
      await repo.incrementCount(practiceId, 5);
      await repo.incrementCount(practiceId, 3);

      final practices = await repo.getByTradition('test');
      expect(practices.first.currentCount, 18);

      await db.close();
    });

    test('watchByTradition эмитит список и реагирует на инкремент', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
      final repo = PracticeRepository(db);

      final now = DateTime.now();
      final practiceId = await repo.create(PracticeEntity(
        name: 'Тест',
        type: 'counter',
        traditionTag: 'test',
        createdAt: now,
        updatedAt: now,
      ));

      // Подписываемся на стрим
      final stream = repo.watchByTradition('test');
      final emissions = <List<PracticeEntity>>[];
      final sub = stream.listen(emissions.add);

      // Даём стриму эмитить начальное состояние
      await Future<void>.delayed(Duration.zero);

      // Инкремент должен вызвать новый эмиссий
      await repo.incrementCount(practiceId, 7);
      await Future<void>.delayed(Duration.zero);

      await sub.cancel();
      await db.close();

      // Минимум два эмиссии: начальное состояние + после инкремента
      expect(emissions.length, greaterThanOrEqualTo(2));
      // Последний эмиссий показывает обновлённый счёт
      expect(emissions.last.first.currentCount, 7);
    });

    test('watchById эмитит null после удаления практики (лекарство B-6)',
        () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
      final repo = PracticeRepository(db);

      final now = DateTime.now();
      final practiceId = await repo.create(PracticeEntity(
        name: 'Тест',
        type: 'counter',
        traditionTag: 'test',
        createdAt: now,
        updatedAt: now,
      ));

      final stream = repo.watchById(practiceId);
      final emissions = <PracticeEntity?>[];
      final sub = stream.listen(emissions.add);

      await Future<void>.delayed(Duration.zero);

      // Удаляем практику — стрим должен эмитить null
      await repo.delete(practiceId);
      await Future<void>.delayed(Duration.zero);

      await sub.cancel();
      await db.close();

      // Последний эмиссий — null (практика не найдена)
      expect(emissions.last, isNull);
    });

    test('два параллельных incrementCount дают строго +2 (атомарность, B-8)',
        () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
      final repo = PracticeRepository(db);

      final now = DateTime.now();
      final practiceId = await repo.create(PracticeEntity(
        name: 'Тест',
        type: 'counter',
        traditionTag: 'test',
        createdAt: now,
        updatedAt: now,
      ));

      // Запускаем два инкремента параллельно (без await между ними)
      await Future.wait([
        repo.incrementCount(practiceId, 1),
        repo.incrementCount(practiceId, 1),
      ]);

      final practices = await repo.getByTradition('test');
      // При read-modify-write гонка могла бы дать 1 вместо 2.
      // Атомарный UPDATE гарантирует 2.
      expect(practices.first.currentCount, 2);

      await db.close();
    });

    // B-10: create() обязан сохранять переданные даты, а не дефолты БД.
    test('create() сохраняет заданные createdAt/updatedAt (B-10)', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
      final repo = PracticeRepository(db);

      // Даты с точностью до секунды — Drift хранит DateTime без мисек (F-33).
      final created = DateTime(2026, 3, 14, 1, 2, 3);
      final updated = DateTime(2026, 3, 15, 4, 5, 6);
      await repo.create(PracticeEntity(
        name: 'Архивная',
        type: 'counter',
        traditionTag: 'test',
        createdAt: created,
        updatedAt: updated,
      ));

      final p = (await repo.getByTradition('test')).single;
      expect(p.createdAt, created);
      expect(p.updatedAt, updated);

      await db.close();
    });

    test('порядок getByTradition по createdAt детерминирован (B-10)', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
      final repo = PracticeRepository(db);

      // I-6: разнос > 1 секунды — Drift усекает даты до секунд,
      // вставки внутри одной секунды неупорядочены.
      final base = DateTime(2026, 1, 1, 12, 0, 0);
      for (var i = 0; i < 3; i++) {
        await repo.create(PracticeEntity(
          name: 'P$i',
          type: 'counter',
          traditionTag: 'test',
          createdAt: base.add(Duration(seconds: i * 2)),
          updatedAt: base.add(Duration(seconds: i * 2)),
        ));
      }
      // Специально вставляем «старшую» четвёртой — порядок по датам, не по id.
      await repo.create(PracticeEntity(
        name: 'Late',
        type: 'counter',
        traditionTag: 'test',
        createdAt: base.add(const Duration(seconds: 1)),
        updatedAt: base.add(const Duration(seconds: 1)),
      ));

      final practices = await repo.getByTradition('test');
      expect(
        practices.map((p) => p.name).toList(),
        ['P0', 'Late', 'P1', 'P2'],
        reason: 'сортировка по createdAt, а не по id вставки',
      );

      await db.close();
    });

    // R-23: неположительный инкремент — не «ошибочный тап», а тихая потеря
    // счёта с легальной на вид записью в истории. Гард проверяется на слое
    // репозитория (урок 3): UI-валидация — не граница домена.
    group('R-23: incrementCount отклоняет неположительный amount', () {
      Future<(AppDatabase, PracticeRepository, int)> seed() async {
        final db =
            AppDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
        final repo = PracticeRepository(db);
        final now = DateTime.now();
        final id = await repo.create(PracticeEntity(
          name: 'Тест',
          type: 'counter',
          traditionTag: 'test',
          createdAt: now,
          updatedAt: now,
        ));
        await repo.incrementCount(id, 5);
        return (db, repo, id);
      }

      test('amount = -1 → ArgumentError, счёт и история не тронуты', () async {
        final (db, repo, id) = await seed();

        await expectLater(repo.incrementCount(id, -1), throwsArgumentError);

        final p = (await repo.getByTradition('test')).single;
        expect(p.currentCount, 5, reason: 'отклонённый инкремент не меняет счёт');
        final history = await db.select(db.countHistory).get();
        expect(history.length, 1,
            reason: 'запись «-1» не должна попасть в историю');
        expect(history.single.count, 5);

        await db.close();
      });

      test('amount = 0 → ArgumentError, следов в БД нет', () async {
        final (db, repo, id) = await seed();

        await expectLater(repo.incrementCount(id, 0), throwsArgumentError);

        final p = (await repo.getByTradition('test')).single;
        expect(p.currentCount, 5);
        final history = await db.select(db.countHistory).get();
        expect(history.length, 1, reason: 'нулевой инкремент — не событие');

        await db.close();
      });

      test('положительный amount по-прежнему работает (граница 1)', () async {
        final (db, repo, id) = await seed();

        await repo.incrementCount(id, 1);

        final p = (await repo.getByTradition('test')).single;
        expect(p.currentCount, 6);

        await db.close();
      });
    });

    // C4 (D-45): строка с `preset_id` без `preset_practice_id` невидима
    // upsert-ключу материализации (tradition_tag, preset_practice_id), а
    // уникальный индекс SQLite на NULL не конфликтует → первый же applyPreset
    // кладёт двойника, и счёт рассекается. Инвариант держится на слое записи,
    // а не веткой миграции: по истории кода такое состояние не порождается
    // (см. обоснование в PracticeRepository.create и D-45).
    group('C4/D-45: create не заводит пресетных строк', () {
      test('presetId != null → ArgumentError, в БД ни следа', () async {
        final db = AppDatabase.forTesting(
            NativeDatabase.memory(setup: enableForeignKeys));
        final repo = PracticeRepository(db);
        final now = DateTime.now();

        await expectLater(
          repo.create(PracticeEntity(
            name: 'Простирания',
            type: 'counter',
            traditionTag: 'nyingma',
            presetId: 'nyingma',
            createdAt: now,
            updatedAt: now,
          )),
          throwsArgumentError,
        );

        expect(await db.select(db.practices).get(), isEmpty,
            reason: 'отклонённая запись не должна оставлять строку без '
                'preset_practice_id');
        await db.close();
      });

      test('пресетную строку, прочитанную из БД, нельзя пересоздать через create',
          () async {
        // Лазейка: materialization пишет preset_id сама, entity умеет нести
        // presetId (fromRow) — и кто-то может подать этот entity в create.
        final db = AppDatabase.forTesting(
            NativeDatabase.memory(setup: enableForeignKeys));
        final repo = PracticeRepository(db);
        final now = DateTime.now();

        await db.into(db.practices).insert(PracticesCompanion.insert(
              presetId: const Value('nyingma'),
              presetPracticeId: const Value('ngondro_prostrations'),
              name: 'Простирания',
              type: 'counter',
              traditionTag: 'nyingma',
              createdAt: Value(now),
              updatedAt: Value(now),
            ));
        final asEntity =
            PracticeEntity.fromRow(await db.select(db.practices).getSingle());
        expect(asEntity.presetId, 'nyingma');

        await expectLater(
          repo.create(asEntity.copyWith(id: null, name: 'Копия')),
          throwsArgumentError,
        );

        final rows = await db.select(db.practices).get();
        expect(rows, hasLength(1), reason: 'лазейки в инварианте нет');
        expect(rows.single.presetPracticeId, 'ngondro_prostrations');
        await db.close();
      });
    });
  });
}
