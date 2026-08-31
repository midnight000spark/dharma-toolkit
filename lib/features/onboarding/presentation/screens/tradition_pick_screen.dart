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

class _PresetTile extends ConsumerWidget {
  final String tradition;
  final String presetId;

  const _PresetTile({required this.tradition, required this.presetId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(configModuleProvider);
    final preset = config.getPreset(presetId);
    final available = preset != null;

    return ListTile(
      title: Text(preset?.name ?? presetId),
      subtitle: Text(
        available
            ? (preset.description ?? tradition)
            : 'Скоро — пресет ещё не готов',
      ),
      trailing: available ? const Icon(Icons.chevron_right) : null,
      enabled: available,
      onTap: available
          ? () async {
              await ref.read(presetManagerProvider).applyPreset(preset);
              if (context.mounted) context.go('/');
            }
          : null,
    );
  }
}
