import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/utils/format.dart';
import '../../domain/practice.dart';
import '../providers/practice_provider.dart';

/// Экран создания кастомной практики
class CreatePracticeScreen extends ConsumerStatefulWidget {
  final String traditionTag;

  const CreatePracticeScreen({super.key, required this.traditionTag});

  @override
  ConsumerState<CreatePracticeScreen> createState() => _CreatePracticeScreenState();
}

class _CreatePracticeScreenState extends ConsumerState<CreatePracticeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _targetController = TextEditingController();
  final _unitController = TextEditingController();
  String _type = PracticeTypes.counter;

  /// Подписи типов — текст интерфейса, поэтому живут в presentation, а не в
  /// домене. Сам набор типов — доменный [PracticeTypes] (R-19): форма не
  /// может предложить тип, которого нет в домене, потому что список не
  /// является литералом виджета. Отсутствие подписи для нового типа ловит
  /// guard-тест (тип показывается сырым значением — заметно, а не молча).
  static const Map<String, String> _typeLabels = <String, String>{
    PracticeTypes.counter: 'Счётчик',
  };

  /// Защита от двойного тапа (B-9): пока [PracticeRepository.create] в полёте,
  /// кнопка заблокирована, повторный вход в [_save] игнорируется.
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _targetController.dispose();
    _unitController.dispose();
    super.dispose();
  }

  /// Разбор цели: «100 000» → 100000 (пробелы — группировка разрядов, а не
  /// данные); пусто → null; нечисловое или неположительное — ошибка под
  /// полем, цель не теряется молча (B-9). Правила — общая утилита
  /// [parseGroupedPositiveInt] (урок 3: те же правила у диалога произвольного
  /// инкремента, 5.0.5).
  static int? parseTarget(String raw) => parseGroupedPositiveInt(
        raw,
        error: 'Цель должна быть целым числом больше нуля',
      );

  String? _validateTarget(String? value) {
    try {
      parseTarget(value ?? '');
      return null;
    } on FormatException catch (e) {
      return e.message;
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      final repository = ref.read(practiceRepositoryProvider);
      final now = DateTime.now();
      final unitText = _unitController.text.trim();

      final practice = PracticeEntity(
        name: _nameController.text.trim(),
        type: _type,
        target: parseTarget(_targetController.text),
        unit: unitText.isEmpty ? null : unitText,
        traditionTag: widget.traditionTag,
        createdAt: now,
        updatedAt: now,
      );

      await repository.create(practice);

      // Стрим списка сам обновится после insert — просто pop без result.
      // go_router API, а не Navigator (6.5): навигация в приложении одна.
      if (mounted) {
        context.pop();
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Новая практика'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Название'),
                validator: (value) =>
                    value?.trim().isEmpty ?? true ? 'Введите название' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Тип'),
                // R-19: пункты строятся из доменного набора PracticeTypes,
                // а не из литералов виджета (урок 3). Тип «timer» относится
                // к FR-TRK-7 (бэклог v1.1) и здесь не появляется, пока не
                // появится его экран.
                items: [
                  for (final type in PracticeTypes.available)
                    DropdownMenuItem(
                      value: type,
                      child: Text(_typeLabels[type] ?? type),
                    ),
                ],
                onChanged: (value) => setState(() => _type = value!),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _targetController,
                decoration: const InputDecoration(labelText: 'Цель (опционально)'),
                keyboardType: TextInputType.number,
                validator: _validateTarget,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _unitController,
                decoration: const InputDecoration(labelText: 'Единица измерения'),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _saving ? null : _save,
                child: const Text('Создать'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
