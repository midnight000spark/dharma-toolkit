import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/l10n/l10n.dart';
import '../../shared/utils/error_text.dart';
import '../db/app_database.dart' show kAppDatabaseFileName;
import '../module/module_registry.dart' show ModuleInitFailure;

/// Отчёт об аварийном стирании (C1(3)): что удалось и что нет.
///
/// До FIX-1 [wipeLocalState] возвращала `void` и проглатывала каждый отказ в
/// `debugPrint`: пользователь жал «Сбросить настройки», видел перезапуск, а
/// не стёршийся файл базы оставался на месте — и тот же экран появлялся снова,
/// без единого признака, что стирание не состоялось.
class WipeReport {
  /// Настройки (SharedPreferences) очищены.
  final bool prefsCleared;

  /// Путь, под который переименован файл базы, или `null`, если файла не было
  /// либо переименование не удалось.
  final String? renamedDatabaseTo;

  /// Имена сайдкаров журнала, удалённых вместе с базой.
  final List<String> removedSidecars;

  /// Человекочитаемые формулировки того, что не получилось. Пусто = чисто.
  final List<String> errors;

  /// Копии `.corrupt-<ts>` в папке документов на момент отчёта, новейшая
  /// первой (W33). Пусто — копий нет (или папка недоступна; тогда причина в
  /// [errors]). Это данные для восстановления счёта, поэтому отчёт обязан
  /// называть их вслух, а не оставлять накопление молчаливым.
  final List<CorruptDatabaseCopy> corruptCopies;

  const WipeReport({
    required this.prefsCleared,
    this.renamedDatabaseTo,
    this.removedSidecars = const [],
    this.errors = const [],
    this.corruptCopies = const [],
  });

  bool get clean => errors.isEmpty;

  /// Сколько копий хранится как рабочее окно: [kRetainedCorruptCopies]
  /// последних (W33, решение п. 11.9).
  int get retainedCorruptCopies => corruptCopies.length < kRetainedCorruptCopies
      ? corruptCopies.length
      : kRetainedCorruptCopies;

  /// Копии старше окна хранения, новейшая из них — первой.
  ///
  /// Они **не удаляются автоматически**: молчаливая массовая чистка — это
  /// потеря данных для восстановления, а политика оставляет решение за
  /// человеком (п. 11.9). Экран обязан перечислить их и их дату/размер.
  List<CorruptDatabaseCopy> get excessCorruptCopies => corruptCopies
      .skip(kRetainedCorruptCopies)
      .toList(growable: false);

  /// Есть ли копии сверх окна хранения — повод показать их человеку.
  bool get hasExcessCorruptCopies =>
      corruptCopies.length > kRetainedCorruptCopies;
}

/// Файлы, которые SQLite держит рядом с базой. Стирать только основной файл —
/// значит оставить журнал, по которому база «восстанавливается» обратно под
/// удалённый путь.
const List<String> _databaseSidecarSuffixes = ['-journal', '-wal', '-shm'];

/// Сколько последних копий повреждённой базы считается рабочим окном (W33).
///
/// Решение 30.09 (п. 11.9): хранить 3 последние копии. Копии старше окна —
/// не мусор, а данные для восстановления счёта, поэтому этот модуль их не
/// удаляет: он их перечисляет человеку ([WipeReport.excessCorruptCopies]).
const int kRetainedCorruptCopies = 3;

/// Префикс имени копии: полное имя файла базы и разделитель `.corrupt-`.
const String _corruptCopyPrefix = '$kAppDatabaseFileName.corrupt-';

/// Копия повреждённой базы (`.corrupt-<ts>`), пережившая стирание (W33).
///
/// Основной файл не удаляется, а переименовывается — шанс вытащить счёт
/// (дух D-26). Со временем такие копии накапливаются, поэтому у каждой есть
/// момент и размер: без них «сколько копий и что с ними» неотличимо от
/// молчаливого накопления.
class CorruptDatabaseCopy {
  /// Имя файла в папке документов. Полный путь намеренно не хранится: экран
  /// показывает человеку дату и размер, а не путь (B-19).
  final String fileName;

  /// Момент сохранения, восстановленный из `<ts>` имени файла.
  final DateTime savedAt;

  /// Размер копии в байтах; `0`, если размер прочитать не удалось.
  final int sizeBytes;

  const CorruptDatabaseCopy({
    required this.fileName,
    required this.savedAt,
    required this.sizeBytes,
  });
}

/// Отбор копий `.corrupt-<ts>` из листинга каталога (W33).
///
/// Чистая функция над «имя файла → размер»: отделена от файлового обхода,
/// чтобы политика хранения (окно из [kRetainedCorruptCopies] последних и
/// явный излишек) проверялась детерминированным тестом без реального I/O
/// (урок 5). Сортировка — по моменту, новейшая первой; ничья по времени
/// разводится именем, чтобы порядок был тотальным. Имена, не являющиеся нашей
/// копией (чужой префикс или нечисловой хвост), отбрасываются.
List<CorruptDatabaseCopy> parseCorruptCopies(Map<String, int> nameToSize) {
  final copies = <CorruptDatabaseCopy>[];
  for (final entry in nameToSize.entries) {
    final name = entry.key;
    if (!name.startsWith(_corruptCopyPrefix)) continue;
    final timestamp = int.tryParse(name.substring(_corruptCopyPrefix.length));
    if (timestamp == null) continue;
    copies.add(CorruptDatabaseCopy(
      fileName: name,
      savedAt: DateTime.fromMillisecondsSinceEpoch(timestamp),
      sizeBytes: entry.value,
    ));
  }
  copies.sort((a, b) {
    final byMoment = b.savedAt.compareTo(a.savedAt);
    return byMoment != 0 ? byMoment : b.fileName.compareTo(a.fileName);
  });
  return copies;
}

/// Собрать копии `.corrupt-<ts>` в папке документов (W33).
///
/// Здесь только файловый обход и размеры; решение «окно/излишек» принимает
/// чистая [parseCorruptCopies]. Отказ листинга не глотается: вызывающий
/// обязан занести его в отчёт.
Future<List<CorruptDatabaseCopy>> _collectCorruptCopies(Directory dir) async {
  final nameToSize = <String, int>{};
  await for (final entity in dir.list()) {
    if (entity is! File) continue;
    final name = p.basename(entity.path);
    if (!name.startsWith(_corruptCopyPrefix)) continue;
    int size;
    try {
      size = await entity.length();
    } catch (_) {
      // Размер не прочитался — копию всё равно показываем с нулём: скрыть
      // существующую копию хуже, чем показать её без размера.
      size = 0;
    }
    nameToSize[name] = size;
  }
  return parseCorruptCopies(nameToSize);
}

/// Аварийное стирание локального состояния (B-5).
///
/// ВНИМАНИЕ (I-3): это НЕ [PresetManager.resetPreset] и не смена традиции —
/// катастроф-рекавери при повреждённых данных: чистит настройки и файл БД.
/// Вызывается только после явного подтверждения пользователем.
/// Каждая операция независима: отказ path_provider не должен мешать
/// очистке prefs (и наоборот) — но обязан попасть в [WipeReport].
///
/// [closeDatabase] вызывается ПЕРЕД файловыми операциями (C1(3)): SQLite
/// дописывает файл при `close`, и «стёртая» база возродилась бы из-под
/// удалённого пути. Основной файл не удаляется, а переименовывается в
/// `…sqlite.corrupt-<ts>` — шанс вытащить счёт остаётся (дух D-26).
Future<WipeReport> wipeLocalState({
  Future<void> Function()? closeDatabase,
}) async {
  final errors = <String>[];
  final removedSidecars = <String>[];
  String? renamedDatabaseTo;
  var corruptCopies = const <CorruptDatabaseCopy>[];

  if (closeDatabase != null) {
    try {
      await closeDatabase();
    } catch (error) {
      errors.add('соединение с базой не закрылось: $error');
      debugPrint('recovery: не удалось закрыть соединение перед стиранием: $error');
    }
  }

  var prefsCleared = false;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    prefsCleared = true;
  } catch (e) {
    errors.add('настройки не очищены: $e');
    debugPrint('recovery: не удалось очистить настройки: $e');
  }

  try {
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, kAppDatabaseFileName);

    for (final suffix in _databaseSidecarSuffixes) {
      final sidecar = File('$dbPath$suffix');
      try {
        if (await sidecar.exists()) {
          await sidecar.delete();
          removedSidecars.add('$kAppDatabaseFileName$suffix');
        }
      } catch (e) {
        errors.add('сайдкар ${p.basename(sidecar.path)} не удалён: $e');
        debugPrint('recovery: не удалось удалить ${sidecar.path}: $e');
      }
    }

    try {
      final file = File(dbPath);
      if (await file.exists()) {
        final target =
            '$dbPath.corrupt-${DateTime.now().millisecondsSinceEpoch}';
        await file.rename(target);
        renamedDatabaseTo = target;
        debugPrint('recovery: файл базы сохранён как $target');
      }
    } catch (e) {
      errors.add('файл базы не переименован: $e');
      debugPrint('recovery: не удалось переименовать файл БД: $e');
    }

    // W33: после переименования перечисляем все копии `.corrupt-<ts>`.
    // Накопление без политики — это то, что видит пользователь как «данные
    // копились сами»; отчёт обязан назвать их количество, дату и размер, а
    // излишек сверх окна — не удалять молча (п. 11.9).
    try {
      corruptCopies = await _collectCorruptCopies(dir);
    } catch (e) {
      errors.add('копии повреждённой базы не перечислены: $e');
      debugPrint('recovery: не удалось перечислить копии БД: $e');
    }
  } catch (e) {
    errors.add('папка документов недоступна: $e');
    debugPrint('recovery: не удалось добраться до файлов БД: $e');
  }

  return WipeReport(
    prefsCleared: prefsCleared,
    renamedDatabaseTo: renamedDatabaseTo,
    removedSidecars: removedSidecars,
    errors: errors,
    corruptCopies: corruptCopies,
  );
}

/// Операция аварийного стирания локального состояния.
///
/// Инжектируема (R-27): экран восстановления уже принимает [RecoveryApp.onRetry]
/// и [RecoveryApp.onReset] извне, а стирание было зашито внутрь — из-за этого
/// widget-тест вынужденно ждал реального I/O платформенных каналов фиксированным
/// окном и флейкал. По умолчанию — реальный [wipeLocalState].
typedef WipeLocalState = Future<WipeReport> Function();

/// Корень приложения, когда данные не прочитаны (B-5): вместо чёрного
/// экрана — два пути: повторить попытку или стереть локальное состояние.
class RecoveryApp extends StatelessWidget {
  final Object error;
  final Future<void> Function() onRetry;
  final Future<void> Function() onReset;

  /// Отказы, которые приложение пережило в ограниченном режиме (S12-min):
  /// без строки на экране «работаем не полностью» неотличимо от «всё плохо».
  final List<ModuleInitFailure> degradations;

  /// Стирание до вызова [onReset]; по умолчанию — реальный [wipeLocalState].
  final WipeLocalState wipe;

  const RecoveryApp({
    super.key,
    required this.error,
    required this.onRetry,
    required this.onReset,
    this.degradations = const [],
    this.wipe = wipeLocalState,
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
        degradations: degradations,
        wipe: wipe,
      ),
    );
  }
}

/// Экран восстановления: «не удалось прочитать данные» + «попробовать
/// снова» + «сбросить настройки» (с подтверждением).
class RecoveryScreen extends StatefulWidget {
  final Object error;
  final Future<void> Function() onRetry;

  /// Вызывается ПОСЛЕ [wipe] — обычно это повторный bootstrap.
  final Future<void> Function() onReset;

  /// Ограниченный режим старта (S12-min): список пережитых отказов с классом.
  final List<ModuleInitFailure> degradations;

  /// Аварийное стирание локального состояния (по умолчанию [wipeLocalState]).
  final WipeLocalState wipe;

  const RecoveryScreen({
    super.key,
    required this.error,
    required this.onRetry,
    required this.onReset,
    this.degradations = const [],
    this.wipe = wipeLocalState,
  });

  @override
  State<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends State<RecoveryScreen> {
  bool _busy = false;

  /// Сколько попыток подряд не удалось (C3): без счётчика пользователь
  /// нажимал «Попробовать снова» в никуда и не видел, что что-то меняется.
  int _attempts = 0;

  /// Что показать после неудачной попытки (C3). Только текст для человека:
  /// детали исключения уходят в лог (B-19).
  String? _retryFailure;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) setState(() => _retryFailure = null);
    } catch (error) {
      // C3: раньше у экрана не было catch — отказ повторной попытки уходил
      // в зон только с логом (а там `rootMounted == true`, то есть вообще
      // ничего), кнопка гасла на кадр и становилась активной снова.
      if (mounted) {
        setState(() {
          _attempts++;
          _retryFailure = userFacingErrorText(
            'Повторная попытка не удалась (попытка $_attempts). '
            'Можно попробовать ещё раз или стереть локальное состояние.',
            details: error,
          );
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Отчёт последней операции стирания (C1(3)): «кнопка нажата» ≠ «стёрто».
  WipeReport? _wipeReport;

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
        final report = await widget.wipe();
        if (mounted) {
          setState(() => _wipeReport = report);
          if (!report.clean) {
            // B-19: на экран — факт неполноты, в лог — формулировки отказов.
            debugPrint('recovery: стирание неполное: ${report.errors}');
          }
        }
        await widget.onReset();
      });
    }
  }

  /// Ограниченный режим (S12-min): что именно приложение пережило, классом
  /// отказа, а не сырым исключением (B-19). Раньше `degradedModules` из
  /// вердикта старта (`StartupOutcome`) до экрана не доезжали — пользователь
  /// видел либо «не удалось прочитать данные», либо ничего.
  List<Widget> _limitedModeLines() {
    if (widget.degradations.isEmpty) return const [];
    return [
      const SizedBox(height: 16),
      const Text(
        'Приложение работает в ограниченном режиме:',
        style: TextStyle(fontWeight: FontWeight.bold),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 4),
      for (final failure in widget.degradations)
        Text(
          '${failure.kind.label} — ${failure.moduleId}'
          '${failure.subject == null ? '' : ': ${failure.subject}'}',
          key: ValueKey('degradation-${failure.kind.name}-${failure.subject}'),
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
    ];
  }

  /// Переполнение копий повреждённой базы (W33): сколько копий, сколько
  /// хранится, какие лишние, их дата и размер — и что с ними НЕ сделали.
  ///
  /// Появляется только при переполнении: молчаливое накопление — это когда
  /// копии растут, а человек об этом не знает. Здесь он видит и список, и
  /// прямое «удалять или нет — ваше право».
  List<Widget> _corruptCopiesNotice(WipeReport report) {
    return [
      const SizedBox(height: 12),
      Text(
        'Сохранённых копий повреждённой базы: ${report.corruptCopies.length}. '
        'Хранятся ${report.retainedCorruptCopies} последние.',
        key: const ValueKey('corrupt-copies-summary'),
        style: Theme.of(context).textTheme.bodySmall,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 4),
      for (final copy in report.excessCorruptCopies)
        Text(
          '${_formatCopyMoment(copy.savedAt)} · ${_formatCopySize(copy.sizeBytes)}',
          key: ValueKey('corrupt-copy-${copy.fileName}'),
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      const SizedBox(height: 4),
      Text(
        'Лишние копии не удалялись автоматически — удалить их можно вручную.',
        key: const ValueKey('corrupt-copies-retained'),
        style: Theme.of(context).textTheme.bodySmall,
        textAlign: TextAlign.center,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // S12: пока идёт повторная попытка или стирание, системный «назад»
      // увёл бы с экрана посреди операции — результат остался бы невидимым.
      key: const ValueKey('recovery-pop-scope'),
      canPop: !_busy,
      child: Scaffold(
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
                // B-19: детали исключения — в лог, а не на экран.
                Text(
                  userFacingErrorText(
                    'Попробуйте ещё раз. Если не поможет — сбросьте настройки.',
                    details: widget.error,
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
                if (_retryFailure != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _retryFailure!,
                    key: const ValueKey('retry-failure'),
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
                if (_wipeReport case final WipeReport report
                    when !report.clean) ...[
                  const SizedBox(height: 8),
                  // C1(3): отказ стирания обязан быть виден. Без этого
                  // «Сбросить настройки» выглядит выполненным, а экран
                  // восстановления возвращается молча — тот же класс
                  // молчаливой деградации, что R-11/R-13/R-20.
                  Text(
                    'Стирание прошло не полностью: данные могли остаться '
                    'на устройстве.',
                    key: const ValueKey('wipe-incomplete'),
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
                if (_wipeReport case final WipeReport report
                    when report.hasExcessCorruptCopies) ...[
                  ..._corruptCopiesNotice(report),
                ],
                ..._limitedModeLines(),
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
                // S12: занятость видна, а не только выключенные кнопки:
                // «кнопки серые» без индикатора неотличимо от «экран завис».
                if (_busy) ...[
                  const SizedBox(height: 16),
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      key: ValueKey('recovery-busy'),
                      strokeWidth: 2,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Дата и время копии для человека: «15.01.2026 08:00». Без пути и без
/// системных зон — только момент, который пользователь может узнать.
String _formatCopyMoment(DateTime moment) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(moment.day)}.${two(moment.month)}.${moment.year} '
      '${two(moment.hour)}:${two(moment.minute)}';
}

/// Размер копии для человека: байты / КБ / МБ. Нужен, чтобы «копия» была не
/// абстракцией: видно, сколько занимает то, что решено сохранить.
String _formatCopySize(int bytes) {
  if (bytes < 1024) return '$bytes Б';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} КБ';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
}

/// Замена красного экрана Flutter (5.3): человекочитаемо, без падения кадра.
/// Исключение логируется — разработчик его видит, пользователь — нет.
///
/// C2: `ErrorWidget.builder` вызывают и для сбоев **выше** `MaterialApp`,
/// где предка `Directionality` ещё нет. `Text` → `RichText` без него падает
/// сам, фреймворк подставляет замену для замены — рекурсия и всё тот же
/// чёрный экран (класс 5.3/B-5), ради которого заглушку и вводили. Состав
/// намеренно минимальный: ни theme, ни MediaQuery-зависимых виджетов.
/// Рецепт был в проекте (`debug_notification_button.dart`) и в критический
/// путь не переехал.
Widget humanErrorWidget(FlutterErrorDetails details) {
  debugPrint('Ошибка виджета: ${details.exception}');
  return const Directionality(
    textDirection: TextDirection.ltr,
    child: ColoredBox(
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
    ),
  );
}
