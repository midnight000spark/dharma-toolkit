/// Архитектурный guard (B-16, пакет 5b.4): в календарной фиче нет
/// разделяемого изменяемого состояния уровня библиотеки или класса.
///
/// Урок B-16: глобальный `final Map ... = {}` в порту тибетского календаря
/// был невидимым общим состоянием домена — никогда не чистился и не
/// изолировался между инстансами. Правила:
///  * top-level `final/late/var` с изменяемым контейнером запрещён
///    (`const`-коллекции — неизменяемы, разрешены);
///  * `static`-поле того же вида запрещено;
///  * экземплярные поля (`final TibetanMonthCache ...`) — легальный
///    инкапсулированный state, вне проверки.
///
/// Guard краснеет на обеих мутациях (урок 1: проверялось внесением
/// нарушения руками — top-level `final Map = {}` и `static final List = []`).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// имя правила → паттерн-нарушение (мультистрочный, колонка-0 или static).
final _rules = <String, RegExp>{
  'top-level mutable container': RegExp(
    r'^(?:final|late|var)\s+(?:Map|List|Set)[^=\n]*=\s*(?:\{|\[|<)',
    multiLine: true,
  ),
  'top-level inferred mutable literal': RegExp(
    r'^(?:final|late|var)\s+\w+\s*=\s*(?:\{|\[|<[^>]*>\s*\{)',
    multiLine: true,
  ),
  'static mutable container': RegExp(
    r'^[ \t]*static\s+(?!const)[^=\n]*=\s*(?:\{|\[|<[^>]*>\s*\{|'
    r'(?:List|Map|Set)\.(?:filled|fromEntries|from|generate))',
    multiLine: true,
  ),
};

void main() {
  test('lib/features/calendar: нет разделяемого изменяемого состояния', () {
    final dir = Directory('lib/features/calendar');
    expect(dir.existsSync(), isTrue, reason: 'фича переехала? обнови guard');

    final offenders = <String>[];
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('.g.dart')) continue;
      final text = entity.readAsStringSync();
      for (final rule in _rules.entries) {
        for (final m in rule.value.allMatches(text)) {
          final line = text.substring(0, m.start).split('\n').length;
          offenders.add(
              '${entity.path}:$line: ${rule.key} → "${m.group(0)!.trim()}"');
        }
      }
    }

    expect(offenders, isEmpty,
        reason: 'разделяемое изменяемое состояние (top-level/static '
            'mutable-контейнеры) в календарной фиче запрещено (B-16):\n'
            '${offenders.join('\n')}');
  });
}
