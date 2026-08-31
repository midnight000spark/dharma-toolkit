import 'dart:io';

import 'package:dharma_toolkit/core/db/app_database.dart';
import 'package:dharma_toolkit/features/tracker/data/practice_repository.dart';
import 'package:dharma_toolkit/features/tracker/domain/practice.dart';
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
        final db = AppDatabase.forTesting(NativeDatabase(File(dbPath)));
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
        final db = AppDatabase.forTesting(NativeDatabase(File(dbPath)));
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
      final db = AppDatabase.forTesting(NativeDatabase.memory());
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
      final db = AppDatabase.forTesting(NativeDatabase.memory());
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
      final db = AppDatabase.forTesting(NativeDatabase.memory());
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
      final db = AppDatabase.forTesting(NativeDatabase.memory());
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
      final db = AppDatabase.forTesting(NativeDatabase.memory());
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
  });
}
