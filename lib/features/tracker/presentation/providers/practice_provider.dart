import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/db/database_module.dart';
import '../../../../core/module/module_registry.dart';
import '../../data/practice_repository.dart';
import '../../domain/practice.dart';

final practiceListProvider = FutureProvider.autoDispose.family<List<PracticeEntity>, String>(
  (ref, traditionTag) async {
    final repository = ref.read(practiceRepositoryProvider);
    return repository.getByTradition(traditionTag);
  },
);

final practiceRepositoryProvider = Provider<PracticeRepository>((ref) {
  final module = ModuleRegistry.instance.get('database');
  if (module is! DatabaseModule) {
    throw StateError('DatabaseModule not registered');
  }
  return PracticeRepository(module.database);
});
