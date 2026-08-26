import 'package:flutter/material.dart';

import '../../domain/practice.dart';

/// Экран счёта для конкретной практики
class PracticeCountScreen extends StatefulWidget {
  final PracticeEntity practice;

  const PracticeCountScreen({super.key, required this.practice});

  @override
  State<PracticeCountScreen> createState() => _PracticeCountScreenState();
}

class _PracticeCountScreenState extends State<PracticeCountScreen> {
  late int _currentCount;

  @override
  void initState() {
    super.initState();
    _currentCount = widget.practice.currentCount;
  }

  void _increment(int amount) {
    setState(() {
      _currentCount += amount;
    });
    // TODO: сохранить в БД через repository
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.practice.name),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$_currentCount',
              style: Theme.of(context).textTheme.displayLarge,
            ),
            if (widget.practice.target != null) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: _currentCount / widget.practice.target!,
              ),
              const SizedBox(height: 8),
              Text('Цель: ${widget.practice.target}'),
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
