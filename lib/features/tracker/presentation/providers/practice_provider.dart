import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/practice_repository.dart';
import '../../domain/practice.dart';

final practiceListProvider = FutureProvider.autoDispose.family<List<PracticeEntity>, String>(
  (ref, traditionTag) async {
    final repository = ref.read(practiceRepositoryProvider);
    return repository.getByTradition(traditionTag);
  },
);

final practiceRepositoryProvider = Provider<PracticeRepository>((ref) {
  // TODO: получить из registry в будущем
  throw UnimplementedError('PracticeRepository not registered yet');
});
