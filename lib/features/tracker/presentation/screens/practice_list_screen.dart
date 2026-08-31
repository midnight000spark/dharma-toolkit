import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/utils/format.dart';
import '../../domain/practice.dart';
import '../providers/practice_provider.dart';

/// Экран списка трекеров практик
class PracticeListScreen extends ConsumerWidget {
  final String traditionTag;

  const PracticeListScreen({super.key, required this.traditionTag});

  /// Удаление трекера (FR-TRK-11, D-29): только долгое нажатие на карточку +
  /// явное подтверждение в диалоге. Swipe-удаления нет намеренно — счёт
  /// практики это духовный подвиг, а не черновик (I-2/D-26: удаление только
  /// явное намеренное действие).
  ///
  /// Диалог обязан назвать практику, её текущий счёт и предупредить о
  /// необратимом стирании истории. После подтверждения — repository.delete();
  /// каскад стирает count_history (F-33, B-11), стрим сам убирает карточку
  /// из списка (D-16) — ручной перерисовки нет.
  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    PracticeEntity practice,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Удалить «${practice.name}»?'),
        content: Text(
          'Текущий счёт: ${formatCount(practice.currentCount, practice.unit)}.\n'
          'История счёта будет стёрта. Действие необратимо.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(practiceRepositoryProvider).delete(practice.id!);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final practicesAsync = ref.watch(practiceListProvider(traditionTag));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Практики'),
      ),
      body: practicesAsync.when(
        data: (practices) => practices.isEmpty
            // Пустое состояние по SCR-8: объяснение + действие, а не пустой
            // экран (мелочь аудита из D-24).
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Пока нет практик'),
                    const SizedBox(height: 8),
                    const Text(
                      'Добавьте первую — например, счёт мантр или простираний.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () => context.push('/create'),
                      icon: const Icon(Icons.add),
                      label: const Text('Создать'),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                itemCount: practices.length,
                itemBuilder: (context, index) {
                  final practice = practices[index];
                  return ListTile(
                    title: Text(practice.name),
                    subtitle: Text(formatCount(practice.currentCount, practice.unit)),
                    trailing: practice.target != null
                        ? Text('${(practice.progress * 100).toInt()}%')
                        : null,
                    onTap: () => context.push('/practice/${practice.id}'),
                    // FR-TRK-11: единственная точка удаления — долгое нажатие.
                    onLongPress: () => _confirmDelete(context, ref, practice),
                  );
                },
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Ошибка: $error')),
      ),
      floatingActionButton: FloatingActionButton(
        // Стрим сам обновляет список при изменении БД — invalidate не нужен.
        // Возврат из создания просто pop; данные придут через watch().
        onPressed: () => context.push('/create'),
        child: const Icon(Icons.add),
      ),
    );
  }
}
