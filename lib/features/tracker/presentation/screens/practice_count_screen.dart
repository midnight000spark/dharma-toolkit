import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/practice.dart';
import '../providers/practice_provider.dart';

/// Экран счёта для конкретной практики
class PracticeCountScreen extends ConsumerStatefulWidget {
  final int practiceId;

  const PracticeCountScreen({super.key, required this.practiceId});

  @override
  ConsumerState<PracticeCountScreen> createState() => _PracticeCountScreenState();
}

class _PracticeCountScreenState extends ConsumerState<PracticeCountScreen> {
  PracticeEntity? _practice;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPractice();
  }

  Future<void> _loadPractice() async {
    final repository = ref.read(practiceRepositoryProvider);
    final practice = await repository.getById(widget.practiceId);
    setState(() {
      _practice = practice;
      _loading = false;
    });
  }

  Future<void> _increment(int amount) async {
    final repository = ref.read(practiceRepositoryProvider);
    await repository.incrementCount(widget.practiceId, amount);
    await _loadPractice();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _practice == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final practice = _practice!;

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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: () => _increment(1),
                  child: const Text('+1'),
                ),
                ElevatedButton(
                  onPressed: () => _increment(10),
                  child: const Text('+10'),
                ),
                ElevatedButton(
                  onPressed: () => _increment(100),
                  child: const Text('+100'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
