import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'source_scan.dart';

/// W27: в `test/` не должно быть тавтологичных заглушек `expect(true, …)`.
///
/// Урок 1 аудита: тест, который не мог упасть, не доказал ничего. Заглушка
/// `expect(true, isTrue)` — ровно такая: она зелёная всегда и маскирует
/// отсутствие проверки. Прежний guard-файл `imports_guard_test.dart` сам
/// признаётся в комментарии, что «второй тест был заглушкой»; закрытие R-27
/// (fix-r27) обязано было не оставить заглушек — этот сторож делает проверку
/// машинной, чтобы заглушка не вернулась молча.
///
/// Скан идёт по **коду**, а не по тексту: комментарии (`//`, `/* */`) и
/// содержимое строковых литералов снимаются лексическим сканером
/// (`source_scan.dart`) до поиска, поэтому описание антипаттерна в docstring'е
/// или строке не считается нарушением (находка ревью tests-quality-1).
void main() {
  test('детектор видит заглушку и не путает её с текстом', () {
    expect(hasPlaceholderExpect('expect(true, isTrue);'), isTrue);
    expect(hasPlaceholderExpect('expect(\n  true,\n  isTrue,\n);'), isTrue);
    expect(hasPlaceholderExpect('// expect(true, isTrue);'), isFalse);
    expect(hasPlaceholderExpect('/* expect(true, isTrue); */'), isFalse);
    expect(hasPlaceholderExpect("'пример: expect(true, isTrue)'"), isFalse);
    expect(hasPlaceholderExpect('/// был заглушкой `expect(true, isTrue)`'),
        isFalse);
    expect(hasPlaceholderExpect('expect(trueCount, 1);'), isFalse);
    expect(hasPlaceholderExpect('expect(result, isTrue);'), isFalse);
  });

  test('в test/ нет заглушек expect(true) (W27)', () {
    final offenders = <String>[];
    final files = Directory('test')
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.path.replaceAll(r'\', '/'))
        .where((p) => p.endsWith('.dart'))
        .toList()
      ..sort();
    for (final path in files) {
      final content = File(path).readAsStringSync();
      if (!hasPlaceholderExpect(content)) continue;
      final stripped = stripNonCode(content).split('\n');
      final hit = stripped.indexWhere(_placeholder.hasMatch);
      offenders.add(hit == -1
          ? '$path — многострочная заглушка expect(true)'
          : '$path:${hit + 1} — ${stripped[hit].trim()}');
    }
    expect(
      offenders,
      isEmpty,
      reason: 'тавтологичные заглушки expect(true) не доказывают ничего '
          '(урок 1):\n${offenders.join('\n')}',
    );
  });
}

final _placeholder = RegExp(r'expect\(\s*true\s*,');

/// Есть ли заглушка `expect(true, …)` в [source]: комментарии и содержимое
/// строк снимаются (описание антипаттерна — не код).
bool hasPlaceholderExpect(String source) =>
    _placeholder.hasMatch(stripNonCode(source));
