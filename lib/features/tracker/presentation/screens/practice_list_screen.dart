import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/practice_provider.dart';

/// Экран списка трекеров практик
class PracticeListScreen extends ConsumerWidget {
  final String traditionTag;

  const PracticeListScreen({super.key, required this.traditionTag});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final practicesAsync = ref.watch(practiceListProvider(traditionTag));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Практики'),
      ),
      body: practicesAsync.when(
        data: (practices) => ListView.builder(
          itemCount: practices.length,
          itemBuilder: (context, index) {
            final practice = practices[index];
            return ListTile(
              title: Text(practice.name),
              subtitle: Text('${practice.currentCount} ${practice.unit ?? ''}'),
              trailing: practice.target != null
                  ? Text('${(practice.progress * 100).toInt()}%')
                  : null,
            );
          },
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Ошибка: $error')),
      ),
    );
  }
}
