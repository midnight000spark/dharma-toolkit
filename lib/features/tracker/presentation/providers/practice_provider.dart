import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/providers/app_providers.dart';
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

/// Репозиторий трекеров поверх единой БД приложения (D-22).
///
/// БД приходит через `appDatabaseProvider` — composition root переопределяет
/// его единственным экземпляром (production) или in-memory базой (тесты).
/// Service locator (`ModuleRegistry.instance.get('database')`) здесь запрещён:
/// строковый ключ и приведение типа в рантайме — паттерн get_it, от которого
/// отказались (R-11).
final practiceRepositoryProvider = Provider<PracticeRepository>((ref) {
  return PracticeRepository(ref.watch(appDatabaseProvider));
});
