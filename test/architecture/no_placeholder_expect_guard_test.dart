import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// W27: в `test/` не должно быть тавтологичных заглушек `expect(true, …)`.
///
/// Урок 1 аудита: тест, который не мог упасть, не доказал ничего. Заглушка
/// `expect(true, isTrue)` — ровно такая: она зелёная всегда и маскирует
/// отсутствие проверки. Прежний guard-файл `imports_guard_test.dart` сам
/// признаётся в комментарии, что «второй тест был заглушкой»; закрытие R-27
/// (fix-r27) обязано было не оставить заглушек — этот сторож делает проверку
/// машинной, чтобы заглушка не вернулась молча.
///
/// Скан идёт по коду, а не по комментариям (иначе описание антипаттерна в
/// docstring'ах само стало бы «нарушением»), и по всему `test/**`. Детектор
/// проверяется синтетикой отдельным тестом.
void main() {
  test('детектор видит заглушку и не путает её с комментарием/именем', () {
    expect(hasPlaceholderExpect("expect(" "true" ", isTrue);"), isTrue);
    expect(hasPlaceholderExpect('expect(\n  true,\n  isTrue,\n);'), isTrue);
    expect(hasPlaceholderExpect('// expect(' 'true, isTrue);'), isFalse);
    expect(hasPlaceholderExpect('/// был заглушкой `expect(' 'true, isTrue)`'),
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
      final stripped = stripLineComments(content).split('\n');
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

/// Убрать `//`-комментарии построчно (описание антипаттерна в docstring'ах —
/// не код).
String stripLineComments(String source) => source
    .split('\n')
    .map((line) {
      final at = line.indexOf('//');
      return at == -1 ? line : line.substring(0, at);
    })
    .join('\n');

/// Есть ли заглушка `expect(true, …)` в [source] (заглушка в `//`-комментарии
/// не считается кодом).
bool hasPlaceholderExpect(String source) =>
    _placeholder.hasMatch(stripLineComments(source));
