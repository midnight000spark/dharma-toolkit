import 'package:flutter/material.dart';

/// Экран создания кастомной практики
class CreatePracticeScreen extends StatefulWidget {
  final String traditionTag;

  const CreatePracticeScreen({super.key, required this.traditionTag});

  @override
  State<CreatePracticeScreen> createState() => _CreatePracticeScreenState();
}

class _CreatePracticeScreenState extends State<CreatePracticeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _targetController = TextEditingController();
  String _type = 'counter';
  String? _unit;

  @override
  void dispose() {
    _nameController.dispose();
    _targetController.dispose();
    super.dispose();
  }

  void _save() {
    if (_formKey.currentState!.validate()) {
      // TODO: сохранить через repository
      Navigator.of(context).pop();
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
                validator: (value) => value?.isEmpty ?? true ? 'Введите название' : null,
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
              ),
              const SizedBox(height: 16),
              TextFormField(
                initialValue: _unit,
                decoration: const InputDecoration(labelText: 'Единица измерения'),
                onChanged: (value) => _unit = value,
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _save,
                child: const Text('Создать'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
