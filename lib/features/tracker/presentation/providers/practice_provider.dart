import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/db/database_module.dart';
import '../../../../core/module/module_registry.dart';
import '../../data/practice_repository.dart';
import '../../domain/practice.dart';

/// Стрим списка практик для традиции (D-16, I-3).
///
/// Замена `FutureProvider.autoDispose.family` на `StreamProvider.family`:
/// Drift `.watch()` сам переэмитит список при любом изменении БД, поэтому
/// ручной `invalidate` после создания/счёта больше не нужен (B-1).
final practiceListProvider = StreamProvider.autoDispose.family<List<PracticeEntity>, String>(
  (ref, traditionTag) {
    final repository = ref.read(practiceRepositoryProvider);
    return repository.watchByTradition(traditionTag);
  },
);

/// Стрим одной практики по ID (I-3).
///
/// Если практика удалена или не существует, стрим эмитит `null` — экран
/// показывает состояние «не найдена» с кнопкой «назад» вместо вечного
/// спиннера (B-6).
final practiceByIdProvider = StreamProvider.autoDispose.family<PracticeEntity?, int>(
  (ref, id) {
    final repository = ref.read(practiceRepositoryProvider);
    return repository.watchById(id);
  },
);

final practiceRepositoryProvider = Provider<PracticeRepository>((ref) {
  final module = ModuleRegistry.instance.get('database');
  if (module is! DatabaseModule) {
    throw StateError('DatabaseModule not registered');
  }
  return PracticeRepository(module.database);
});
