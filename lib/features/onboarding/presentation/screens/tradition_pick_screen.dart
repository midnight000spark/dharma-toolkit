import 'package:dharma_toolkit/core/config/preset_schema.dart';
import 'package:dharma_toolkit/shared/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Минимальный экран выбора традиции (B-4).
///
/// Цель — чтобы путь из приложения в `PresetManager.applyPreset` существовал:
/// карточки берутся из `tree.json`, недоступные пресеты помечены «скоро»
/// и некликабельны. Никаких заглушек «собрать свой набор» — это Этап 8.
class TraditionPickScreen extends ConsumerWidget {
  const TraditionPickScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(configModuleProvider);
    final tree = config.tree;

    return Scaffold(
      appBar: AppBar(title: const Text('Выберите традицию')),
      body: ListView(
        children: [
          for (final tradition in tree) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                tradition.name,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final presetId in tradition.presetIds)
              _PresetTile(tradition: tradition.name, presetId: presetId),
          ],
        ],
      ),
    );
  }
}

class _PresetTile extends ConsumerStatefulWidget {
  final String tradition;
  final String presetId;

  const _PresetTile({required this.tradition, required this.presetId});

  @override
  ConsumerState<_PresetTile> createState() => _PresetTileState();
}

class _PresetTileState extends ConsumerState<_PresetTile> {
  /// Защита от двойного тапа (R-22): пока [PresetManager.applyPreset] в
  /// полёте, карточка не принимает повторный тап. Материализация внутри
  /// транзакции защищает целостность БД, этот гард — от второго применения
  /// и лишней навигации; вместе они делают быстрый тап-спам безвредным.
  /// Тот же паттерн, что у формы создания (B-9, урок 3).
  bool _saving = false;

  Future<void> _pick(PresetSchema preset) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref.read(presetManagerProvider).applyPreset(preset);
      if (mounted) context.go('/');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(configModuleProvider);
    final preset = config.getPreset(widget.presetId);
    final available = preset != null;

    return ListTile(
      title: Text(preset?.name ?? widget.presetId),
      subtitle: Text(
        available
            ? (preset.description ?? widget.tradition)
            : 'Скоро — пресет ещё не готов',
      ),
      trailing: _saving
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : (available ? const Icon(Icons.chevron_right) : null),
      // Пока применение в полёте, тайл выключен — тап не доходит до onTap.
      enabled: available && !_saving,
      onTap: available ? () => _pick(preset) : null,
    );
  }
}
