import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/utils/format.dart';
import '../providers/practice_provider.dart';

/// Экран счёта для конкретной практики (I-3, I-4).
///
/// ConsumerWidget на [practiceByIdProvider]: стрим сам обновляет UI при
/// изменении БД, ручная перезагрузка состояния отсутствует (B-6 решён
/// структурно). Loading показывает спиннер с AppBar и кнопкой «назад».
/// Null из стрима = «практика не найдена» с кнопкой «назад» (B-6).
///
/// Дизайн по SCR-9: одна КРУПНАЯ центральная кнопка «+» (шаг 1); вторичные
/// +10/+100 — меньшими кнопками ниже. Рядом — «Ввести число» (FR-TRK-9,
/// 5.0.5): диалог с валидацией общих правил и атомарным инкрементом.
class PracticeCountScreen extends ConsumerWidget {
  final int practiceId;

  const PracticeCountScreen({super.key, required this.practiceId});

  Future<void> _increment(WidgetRef ref, int amount) async {
    final repository = ref.read(practiceRepositoryProvider);
    await repository.incrementCount(practiceId, amount);
    // Стрим сам переэмитит новое значение — ничего больше делать не нужно.
  }

  /// Произвольный инкремент (FR-TRK-9): диалог → атомарный
  /// `incrementCount(amount)`, который пишет и счёт, и строку истории (B-8).
  Future<void> _enterAmount(BuildContext context, WidgetRef ref) async {
    final amount = await showDialog<int>(
      context: context,
      builder: (_) => const _CustomAmountDialog(),
    );
    if (amount != null) {
      await _increment(ref, amount);
    }
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
                // Вторичные +10/+100 и «Ввести число» — меньшими кнопками ниже.
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
                    const SizedBox(width: 16),
                    // FR-TRK-9 (5.0.5): произвольное число через диалог.
                    OutlinedButton(
                      onPressed: () => _enterAmount(context, ref),
                      child: const Text('Ввести число'),
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

/// Диалог произвольного инкремента (FR-TRK-9, 5.0.5).
///
/// Валидация — общие правила числового ввода ([parseGroupedPositiveInt]):
/// группировка пробелами («1 500» → 1500), целое > 0, иначе видимая ошибка
/// под полем (урок 4: неправильный ввод не должен молча ничего менять).
/// Пустой ввод — тоже видимая ошибка: в отличие от цели в форме создания,
/// пустое число здесь не имеет допустимого смысла.
class _CustomAmountDialog extends StatefulWidget {
  const _CustomAmountDialog();

  @override
  State<_CustomAmountDialog> createState() => _CustomAmountDialogState();
}

class _CustomAmountDialogState extends State<_CustomAmountDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final parsed = tryParseAmount(_controller.text);
    if (parsed.$2 != null) {
      setState(() => _error = parsed.$2);
      return;
    }
    Navigator.of(context).pop(parsed.$1);
  }

  /// Разбор без исключений: (значение, ошибка). Пусто — ошибка «введите»,
  /// нечисловое/≤0 — сообщение правил из общей утилиты.
  (int?, String?) tryParseAmount(String raw) {
    if (raw.trim().isEmpty) return (null, 'Введите число');
    try {
      final value = parseGroupedPositiveInt(
        raw,
        error: 'Число должно быть целым больше нуля',
      );
      return (value, null);
    } on FormatException catch (e) {
      return (null, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ввести число'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: 'Сколько повторений',
          errorText: _error,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        TextButton(
          onPressed: _submit,
          child: const Text('Прибавить'),
        ),
      ],
    );
  }
}
