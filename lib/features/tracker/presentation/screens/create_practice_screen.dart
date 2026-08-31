import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
  String _type = 'counter';

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
  /// полем, цель не теряется молча (B-9).
  static int? parseTarget(String raw) {
    final normalized = raw.trim().replaceAll(RegExp(r'\s+'), '');
    if (normalized.isEmpty) return null;
    final parsed = int.tryParse(normalized);
    if (parsed == null || parsed <= 0) {
      throw const FormatException('Цель должна быть целым числом больше нуля');
    }
    return parsed;
  }

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
                items: const [
                  DropdownMenuItem(value: 'counter', child: Text('Счётчик')),
                  DropdownMenuItem(value: 'timer', child: Text('Таймер')),
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
