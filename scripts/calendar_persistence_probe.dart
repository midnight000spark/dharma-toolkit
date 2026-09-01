/// Замер персистентности особых дней (пакет 5b.5, I-3).
///
/// Воспроизводимый performance-проб: **не тест** — ничего не утверждает,
/// в CI не запускается, печатает числа. Критерий решения из плана 5b.5:
/// медиана холодного `getSpecialDays` на окне 1 месяц < 100 мс → таблица
/// `calendar_events` не вводится (заносится факт F-51 с числами); иначе →
/// таблица и миграция (решение D-31, Блок 2 пакета). Пограничные
/// 90–110 мс — стоп-гейт, решение оркестратора.
///
/// Протоколы:
///  * `cold` — каждый прогон НОВЫЙ инстанс провайдера (кэш пуст), замер
///    одного вызова `getSpecialDays`; 20 прогонов, медиана;
///  * `warm` — тот же инстанс идёт по 12 месяцам года, медиана считается
///    по месяцам 2–12 (прогрев кэша месяцами 1-го окна) — справка о
///    стоимости прокрутки в живой сессии;
///  * окна: месяц (2026-03, 31 день) и год (2026, 365 дней) справочно;
///    `UposathaCalendarProvider` — на тех же окнах (кэша нет, cold==warm).
///
/// Пуск: `dart run scripts/calendar_persistence_probe.dart`
/// (из корня проекта; зависимости не нужны — чистый Dart, без Flutter).
///
/// Выход: человекочитаемая таблица + JSON-блок (архивируется в отчёт
/// пакета; числа фиксируются в STATE как факт).
library;

import 'dart:convert';
import 'dart:io';

import 'package:dharma_toolkit/features/calendar/data/tibetan/tibetan_calendar_provider.dart';
import 'package:dharma_toolkit/features/calendar/data/uposatha/uposatha_calendar_provider.dart';
import 'package:dharma_toolkit/features/calendar/domain/calendar_provider.dart';

/// Число прогонов холодного протокола (медиана по ним — критерий решения).
const int _runs = 20;

/// Тег-заглушка провайдера: проба не касается выбора по пресету.
const String _tag = 'persistence-probe';

void main(List<String> args) {
  final out = StringBuffer();
  final machine = <String, String>{
    'hostname': Platform.localHostname,
    'os': '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    'dart': Platform.version.split(' ').first,
    'cores': '${Platform.numberOfProcessors}',
    'tz': DateTime(2026, 3, 1).timeZoneOffset.toString(),
  };
  out.writeln('Машина: ${machine['hostname']} | ${machine['os']} | '
      'Dart ${machine['dart']} | ${machine['cores']} ядер | '
      'TZ offset ${machine['tz']}');
  out.writeln();
  out.writeln('Прогон: $_runs холодных повторов на сценарий, '
      'единицы — миллисекунды.');
  out.writeln();

  final results = <String, dynamic>{};

  void scenario(String name, CalendarProvider Function() make,
      DateTime Function(int i) windowStart, DateTime Function(int i) end) {
    final cold = <double>[];
    var days = 0;
    for (var i = 0; i < _runs; i++) {
      final p = make();
      final sw = Stopwatch()..start();
      days = p.getSpecialDays(windowStart(i), end(i)).length;
      sw.stop();
      cold.add(sw.elapsedMicroseconds / 1000.0);
    }
    final c = _stats(cold);
    out.writeln('$name cold: med=${c.median.toStringAsFixed(2)}ms '
        'min=${c.min.toStringAsFixed(2)} max=${c.max.toStringAsFixed(2)} '
        'avg=${c.avg.toStringAsFixed(2)} (особых дней: $days)');
    results[name] = {'cold': _json(c), 'specialDays': days};
  }

  // --- Тибетский: холодное окно 1 месяц (критерий) и 1 год (справка).
  scenario(
    'tibetan-month',
    () => TibetanCalendarProvider(traditionTag: _tag),
    (i) => DateTime(2026, 3, 1),
    (i) => DateTime(2026, 3, 31),
  );
  scenario(
    'tibetan-year',
    () => TibetanCalendarProvider(traditionTag: _tag),
    (i) => DateTime(2026, 1, 1),
    (i) => DateTime(2026, 12, 31),
  );

  // --- Упосатхи: те же окна.
  scenario(
    'uposatha-month',
    () => UposathaCalendarProvider(traditionTag: _tag),
    (i) => DateTime(2026, 3, 1),
    (i) => DateTime(2026, 3, 31),
  );
  scenario(
    'uposatha-year',
    () => UposathaCalendarProvider(traditionTag: _tag),
    (i) => DateTime(2026, 1, 1),
    (i) => DateTime(2026, 12, 31),
  );

  // --- Warm-прокрутка тибетского провайдера: один инстанс идёт по годам
  // окнами по месяцу; медиана по месяцам 2–12 (первый — прогрев).
  final warmP = TibetanCalendarProvider(traditionTag: _tag);
  final warm = <double>[];
  for (var m = 1; m <= 12; m++) {
    final first = DateTime(2026, m, 1);
    final last = DateTime(2026, m + 1, 0);
    final sw = Stopwatch()..start();
    warmP.getSpecialDays(first, last);
    sw.stop();
    if (m > 1) warm.add(sw.elapsedMicroseconds / 1000.0);
  }
  final w = _stats(warm);
  out.writeln('tibetan-month warm (прокрутка 12 окон одним инстансом, '
      'медиана по 2–12): med=${w.median.toStringAsFixed(2)}ms '
      'min=${w.min.toStringAsFixed(2)} max=${w.max.toStringAsFixed(2)}');
  (results['tibetan-month'] as Map<String, Object?>)['warm'] = _json(w);

  out.writeln();
  out.writeln('JSON:');
  out.writeln(const JsonEncoder.withIndent('  ').convert({
    'machine': machine,
    'runs': _runs,
    'unit': 'ms',
    'scenarios': results,
  }));
  stdout.write(out);
}

/// Сводка по выборке замеров.
typedef _Stats = ({double median, double min, double max, double avg});

/// Медиана/мин/макс/среднее по выборке.
_Stats _stats(List<double> xs) {
  final s = [...xs]..sort();
  final n = s.length;
  final median = n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
  final sum = s.fold<double>(0, (a, b) => a + b);
  return (median: median, min: s.first, max: s.last, avg: sum / n);
}

/// JSON-представление сводки (числа с точностью до мкс).
Map<String, double> _json(_Stats s) => {
      'median': double.parse(s.median.toStringAsFixed(3)),
      'min': double.parse(s.min.toStringAsFixed(3)),
      'max': double.parse(s.max.toStringAsFixed(3)),
      'avg': double.parse(s.avg.toStringAsFixed(3)),
    };
