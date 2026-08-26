import 'package:flutter/foundation.dart';

import '../../features/tracker/data/practice_repository.dart';
import '../../features/tracker/domain/practice.dart';
import 'app_database.dart';

/// Dev seeder для тестовых данных.
/// 
/// TODO: удалить в Этапе 8
class DevSeeder {
  /// Заполняет БД тестовыми данными, если таблица practices пуста.
  /// Вызывать ТОЛЬКО внутри `if (kDebugMode)`.
  static Future<void> seedIfEmpty(AppDatabase db) async {
    final repository = PracticeRepository(db);
    final practices = await repository.getByTradition('sample');
    
    if (practices.isEmpty) {
      final now = DateTime.now();
      
      // Простирания — 100000 повторений
      await repository.create(PracticeEntity(
        name: 'Простирания',
        type: 'counter',
        target: 100000,
        unit: 'повторений',
        traditionTag: 'sample',
        createdAt: now,
        updatedAt: now,
      ));
      
      // Мантра Ваджрасаттвы — 100000 повторений
      await repository.create(PracticeEntity(
        name: 'Мантра Ваджрасаттвы',
        type: 'counter',
        target: 100000,
        unit: 'повторений',
        traditionTag: 'sample',
        createdAt: now,
        updatedAt: now,
      ));
      
      // Чтение — 60 минут
      await repository.create(PracticeEntity(
        name: 'Чтение текстов',
        type: 'timer',
        target: 60,
        unit: 'минут',
        traditionTag: 'sample',
        createdAt: now,
        updatedAt: now,
      ));
    }
  }
}
