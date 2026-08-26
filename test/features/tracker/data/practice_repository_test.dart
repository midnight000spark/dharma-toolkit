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
  });
}
