/// DST-проб диапазонов `UposathaCalendarProvider` (B-17, пакет 5b.4 блок B).
///
/// Чистая Dart-программа (без flutter): запускается из
/// `uposatha_dst_test.dart` в дочернем процессе с `TZ=Europe/Berlin`.
/// Часовой пояс процесса фиксируется на старте, а хост тестов (Moscow —
/// DST отменён в 2014; CI — UTC) перехода не содержит, поэтому in-process
/// потеря конца диапазона наблюдению не поддаётся — только в subprocess.
///
/// Сценарий (эталон фаз — фикстура F-49): окно 25.03–08.04.2024, внутри —
/// spring-forward Берлина 31.03 (смещение +1:00 → +2:00), конец окна — день
/// новолуния 08.04.2024. Подсчитчик `difference().inDays + 1` теряет ровно
/// один день на таком переходе — упосатха конца окна исчезает молча.
///
/// Формат вывода — одна JSON-строка: {tz, offA, offB, days:[{d,n}]},
/// где d — ISO-дата дня, n — название упосатхи.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dharma_toolkit/features/calendar/data/uposatha/uposatha_calendar_provider.dart';

void main() {
  final a = DateTime(2024, 3, 25);
  final b = DateTime(2024, 4, 8);
  final cal = UposathaCalendarProvider(traditionTag: 'dst-probe');
  final days = cal.getSpecialDays(a, b);

  String two(int v) => v.toString().padLeft(2, '0');
  String off(Duration x) {
    final sign = x.isNegative ? '-' : '+';
    return '$sign${two(x.inMinutes.abs() ~/ 60)}:${two(x.inMinutes.abs() % 60)}';
  }

  String iso(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';

  stdout.write(jsonEncode({
    'tz': Platform.environment['TZ'],
    'offA': off(a.timeZoneOffset),
    'offB': off(b.timeZoneOffset),
    'days': [
      for (final day in days) {'d': iso(day.date), 'n': day.name},
    ],
  }));
}
