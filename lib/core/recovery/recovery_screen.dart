import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/l10n/l10n.dart';
import '../db/app_database.dart' show kAppDatabaseFileName;

/// Аварийное стирание локального состояния (B-5).
///
/// ВНИМАНИЕ (I-3): это НЕ [PresetManager.resetPreset] и не смена традиции —
/// катастроф-рекавери при повреждённых данных: чистит настройки и файл БД.
/// Вызывается только после явного подтверждения пользователем.
/// Каждая операция независима: отказ path_provider не должен мешать
/// очистке prefs (и наоборот).
Future<void> wipeLocalState() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  } catch (e) {
    debugPrint('recovery: не удалось очистить настройки: $e');
  }
  try {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, kAppDatabaseFileName));
    if (await file.exists()) {
      await file.delete();
    }
  } catch (e) {
    debugPrint('recovery: не удалось удалить файл БД: $e');
  }
}

/// Корень приложения, когда данные не прочитаны (B-5): вместо чёрного
/// экрана — два пути: повторить попытку или стереть локальное состояние.
class RecoveryApp extends StatelessWidget {
  final Object error;
  final Future<void> Function() onRetry;
  final Future<void> Function() onReset;

  const RecoveryApp({
    super.key,
    required this.error,
    required this.onRetry,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Дхарма-тулкит',
      // Тот же ru-контур, что и у основного приложения (D-28): экран
      // восстановления может показать системные строки — они обязаны быть
      // русскими.
      locale: appLocale,
      supportedLocales: appSupportedLocales,
      localizationsDelegates: appLocalizationsDelegates,
      home: RecoveryScreen(
        error: error,
        onRetry: onRetry,
        onReset: onReset,
      ),
    );
  }
}

/// Экран восстановления: «не удалось прочитать данные» + «попробовать
/// снова» + «сбросить настройки» (с подтверждением).
class RecoveryScreen extends StatefulWidget {
  final Object error;
  final Future<void> Function() onRetry;

  /// Вызывается ПОСЛЕ [wipeLocalState] — обычно это повторный bootstrap.
  final Future<void> Function() onReset;

  const RecoveryScreen({
    super.key,
    required this.error,
    required this.onRetry,
    required this.onReset,
  });

  @override
  State<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends State<RecoveryScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Сброс только через явное подтверждение (I-3): это необратимое удаление
  /// духовного счёта практикующего, а не «кнопка починки».
  Future<void> _confirmReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Сбросить все данные?'),
        content: const Text(
          'Будут полностью удалены настройки и история практик на этом '
          'устройстве. Отменить это будет невозможно.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Сбросить'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _run(() async {
        await wipeLocalState();
        await widget.onReset();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Дхарма-тулкит')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.storage_rounded, size: 48),
              const SizedBox(height: 16),
              const Text(
                'Не удалось прочитать данные',
                style: TextStyle(fontSize: 18),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '${widget.error}',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _busy ? null : () => _run(widget.onRetry),
                child: const Text('Попробовать снова'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _busy ? null : _confirmReset,
                child: const Text('Сбросить настройки'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Замена красного экрана Flutter (5.3): человекочитаемо, без падения кадра.
/// Исключение логируется — разработчик его видит, пользователь — нет.
Widget humanErrorWidget(FlutterErrorDetails details) {
  debugPrint('Ошибка виджета: ${details.exception}');
  return const ColoredBox(
    color: Color(0xFF1E1E1E),
    child: Padding(
      padding: EdgeInsets.all(16.0),
      child: Center(
        child: Text(
          'Ошибка интерфейса. Приложение продолжит работу, '
          'эта часть экрана временно не отображается.',
          style: TextStyle(color: Color(0xFFEDEDED), fontSize: 13),
          textAlign: TextAlign.center,
        ),
      ),
    ),
  );
}
