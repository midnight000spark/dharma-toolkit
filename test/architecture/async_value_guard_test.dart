import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'source_scan.dart';

/// C9-сторож: `.value` у `AsyncValue`, полученного из Riverpod-`ref`, запрещён.
///
/// Пакет critical-1 (C9) заменил в 14 местах `ref.watch(...).value` на явные
/// `.when(...)`: `.value` схлопывал загрузку/ошибку/данные в одно значение,
/// поэтому первая сборка роутера показывала фолбэк-список с пустым тегом, а
/// отказ потока прятался за устаревшим `hasValue`-кэшем. Правка чинится на
/// слое причины только машинным запретом: разовое исправление 14 мест без
/// сторожа вернётся следующим `ref.watch(...).value`.
///
/// Сторож ищет **форму из диагноза C9** — `.value` сразу на вызове
/// `ref.watch/read/listen(...)`, а не любую подстроку `.value`: безопасные
/// `Future.value()`, `ArgumentError.value(...)`, `MapEntry.value` и `.values`
/// остаются в коде и запрету не подлежат. Детектор отдельно проверяется
/// синтетическими кейсами (урок 1: сторож обязан краснеть от нарушения, а
/// не «просто существовать»).
void main() {
  group('синтетика: детектор ловит формы C9 и молчит на безопасных', () {
    test('ref.watch(...).value — нарушение', () {
      expect(
        findRefValueUses("final t = ref.watch(activeTraditionTagProvider)"
            ".value ?? '';"),
        hasLength(1),
      );
    });

    test('ref.read(...).value — нарушение', () {
      expect(
        findRefValueUses('final p = ref.read(activePresetStreamProvider).value;'),
        hasLength(1),
      );
    });

    test('многострочная C9-форма тоже ловится', () {
      expect(
        findRefValueUses('final t = ref.watch(\n  activeTraditionTagProvider,\n)'
            '.value;'),
        hasLength(1),
      );
    });

    test('явное .when(...) — не нарушение', () {
      expect(
        findRefValueUses('final t = ref.watch(activeTraditionTagProvider).when('
            'data: (v) => v, loading: () => null, error: (_, __) => null);'),
        isEmpty,
      );
    });

    test('безопасные .value вне ref не нарушают', () {
      expect(findRefValueUses('Future<void>.value();'), isEmpty);
      expect(findRefValueUses('Stream.value(1);'), isEmpty);
      expect(findRefValueUses("throw ArgumentError.value(x, 'x');"), isEmpty);
      expect(findRefValueUses('final v = entry.value;'), isEmpty);
      expect(findRefValueUses('final all = _modules.values;'), isEmpty);
    });

    test('закомментированная C9-форма не нарушение', () {
      expect(
        findRefValueUses("// ref.watch(activeTraditionTagProvider).value ?? ''"),
        isEmpty,
      );
    });
  });

  test('реальный lib/: нет .value у AsyncValue из ref (C9)', () {
    final offenders = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.path.replaceAll(r'\', '/'))
        .where((p) => p.endsWith('.dart') && !p.endsWith('.g.dart'))
        .toList()
      ..sort();
    for (final path in files) {
      final hits = findRefValueUses(File(path).readAsStringSync());
      for (final hit in hits) {
        offenders.add('$path — $hit');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'AsyncValue из ref читается явным .when(...), а не .value '
          '(C9):\n${offenders.join('\n')}',
    );
  });
}

/// C9-форма: `.value` сразу на `ref.watch/read/listen(...)`; разбор не
/// ограничен строкой — многострочные формы ловятся, комментарии сняты.
final _refValue = RegExp(r'ref\.(?:watch|read|listen)\([\s\S]*?\)\.value\b');

/// Найти C9-формы в [source] (`//`/`/* */`-комментарии сняты до поиска).
List<String> findRefValueUses(String source) {
  final code = stripComments(source);
  final hits = <String>[];
  for (final match in _refValue.allMatches(code)) {
    final line = '\n'.allMatches(code.substring(0, match.start)).length + 1;
    hits.add('line $line: ${match.group(0)!.replaceAll('\n', ' ')}');
  }
  return hits;
}
