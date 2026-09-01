/// DST-тест диапазона упосатх (B-17, пакет 5b.4 блок B).
///
/// Причина нетривиальной формы: баг живёт в часовом поясе процесса, а пояс
/// фиксируется при старте VM. Хост (Moscow — DST отменён в 2014) и CI (UTC)
/// перехода не содержат, поэтому in-process тест был бы ложно-зелёным.
/// Тест детерминирован на любом хосте: запускает чистый Dart-проб
/// [dst_range_probe.dart] в subprocess с `TZ=Europe/Berlin` (урок 5 —
/// поведение, а не отрисовка) и проверяет итоговые дни того календаря.
///
/// Мутация (вернуть `span = b.difference(a).inDays + 1`) обязана краснить
/// assertion про 08.04 — проверка зубатости задокументирована в STATE.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'Берлин, окно 25.03–08.04.2024 через spring-forward: '
      'упосатха конца диапазона на месте (B-17)', () async {
    final result = await Process.run(
      'dart',
      ['run', 'test/features/calendar/dst_range_probe.dart'],
      environment: {'TZ': 'Europe/Berlin'},
    ).timeout(
      const Duration(minutes: 2),
      onTimeout: () => throw StateError(
          'проб не завершился за 2 мин — зависание `dart run`?'),
    );

    expect(result.exitCode, 0,
        reason: 'проб упал: stdout=${result.stdout} stderr=${result.stderr}');
    final out = jsonDecode(result.stdout as String) as Map<String, dynamic>;

    // Самодиагностика: TZ реально применился — переход +1:00 → +2:00 между
    // началом и концом окна. Без этого последующие проверки были бы
    // ложно-зелёными на хосте без DST (урок 1).
    expect(out['tz'], 'Europe/Berlin');
    expect(out['offA'], '+01:00',
        reason: 'ожидаем CET на 25.03 (до перехода 31.03)');
    expect(out['offB'], '+02:00',
        reason: 'ожидаем CEST на 08.04 (после перехода)');

    final days = [
      for (final e in out['days'] as List)
        (date: e['d'] as String, name: e['n'] as String),
    ];
    final dates = days.map((e) => e.date).toList();

    // Якорь начала окна: полнолуние 25.03 (F-49) — скан начинается верно.
    expect(dates, contains('2024-03-25'));
    // Собственно B-17: новолуние 08.04 (F-49) — последний день окна.
    // `difference().inDays` на spring-forward теряет этот день из скана.
    expect(dates, contains('2024-04-08'),
        reason: 'конец диапазона потерян DST-сдвигом (B-17): '
            'в окне скана не попал последний календарный день');
    expect(days.firstWhere((e) => e.date == '2024-04-08').name,
        contains('новолуние'));

    // Контракт: дней вне окна нет — итерация не перескакивает конец
    // (обратный ход DST дал бы лишний день за границей).
    expect(
        dates.every((d) =>
            d.compareTo('2024-03-25') >= 0 &&
            d.compareTo('2024-04-08') <= 0),
        isTrue,
        reason: 'особые дни вне запрошенного окна: $dates');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
