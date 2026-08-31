import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/practice_provider.dart';

/// Экран счёта для конкретной практики (I-3, I-4).
///
/// ConsumerWidget на [practiceByIdProvider]: стрим сам обновляет UI при
/// изменении БД, ручная перезагрузка состояния отсутствует (B-6 решён
/// структурно). Loading показывает спиннер с AppBar и кнопкой «назад».
/// Null из стрима = «практика не найдена» с кнопкой «назад» (B-6).
///
/// Дизайн по SCR-9: одна КРУПНАЯ центральная кнопка «+» (шаг 1); вторичные
/// +10/+100 — меньшими кнопками ниже. Ввод произвольного числа — не сейчас
/// (FR-TRK-9, Этап 8).
class PracticeCountScreen extends ConsumerWidget {
  final int practiceId;

  const PracticeCountScreen({super.key, required this.practiceId});

  Future<void> _increment(WidgetRef ref, int amount) async {
    final repository = ref.read(practiceRepositoryProvider);
    await repository.incrementCount(practiceId, amount);
    // Стрим сам переэмитит новое значение — ничего больше делать не нужно.
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final practiceAsync = ref.watch(practiceByIdProvider(practiceId));

    return practiceAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Практика')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, stack) => Scaffold(
        appBar: AppBar(title: const Text('Практика')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Ошибка загрузки'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => context.pop(),
                child: const Text('Назад'),
              ),
            ],
          ),
        ),
      ),
      data: (practice) {
        if (practice == null) {
          // Практика не найдена (удалена, deep link на несуществующую) —
          // явное состояние вместо вечного спиннера (B-6).
          return Scaffold(
            appBar: AppBar(title: const Text('Практика')),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Практика не найдена'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => context.pop(),
                    child: const Text('Назад'),
                  ),
                ],
              ),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(practice.name),
          ),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${practice.currentCount}',
                  style: Theme.of(context).textTheme.displayLarge,
                ),
                if (practice.target != null) ...[
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: practice.progress,
                  ),
                  const SizedBox(height: 8),
                  Text('Цель: ${practice.target}'),
                ],
                const SizedBox(height: 32),
                // SCR-9: крупная центральная кнопка «+» (шаг 1).
                SizedBox(
                  width: 120,
                  height: 120,
                  child: ElevatedButton(
                    onPressed: () => _increment(ref, 1),
                    style: ElevatedButton.styleFrom(
                      textStyle: const TextStyle(fontSize: 48),
                    ),
                    child: const Text('+'),
                  ),
                ),
                const SizedBox(height: 16),
                // Вторичные кнопки +10/+100 — меньшими кнопками ниже.
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed: () => _increment(ref, 10),
                      child: const Text('+10'),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton(
                      onPressed: () => _increment(ref, 100),
                      child: const Text('+100'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
