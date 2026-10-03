import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Гигиенический сторож S1: в `lib/` не должно быть test-only файлов.
///
/// Перенос `test_events.dart` из `lib/core/events/` в `test/` закрыл находку
/// только на бумаге: без сторожа файл вернётся молча. Правило —
/// конвенциональное: test-only файл называется `test_*` и обязан жить в
/// `test/`, а не ехать в поставку.
///
/// Сторож обязан краснеть от нарушения (урок 1): мутация — вернуть
/// `lib/core/events/test_events.dart` → тест падает со списком нарушителей.
void main() {
  test('в lib/ нет test-only файлов (имя начинается с test_)', () {
    final offenders = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.path.replaceAll(r'\', '/'))
        .where((p) => p.endsWith('.dart'))
        .where((p) => p.split('/').last.startsWith('test_'))
        .toList()
      ..sort();

    expect(
      offenders,
      isEmpty,
      reason: 'test-only файлы обязаны жить в test/, а не в lib/:\n'
          '${offenders.join('\n')}',
    );
  });
}
