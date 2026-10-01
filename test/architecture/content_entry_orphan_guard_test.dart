/// Архитектурный guard (S4, пакет warning-3c): у записи контент-пака нет
/// обязательных полей без потребителя — «сирот схемы».
///
/// Правило: каждое поле [ContentEntry] обязано читаться кодом фичи контента
/// за пределами самой модели (равенство/hashCode — не потребитель). Поле,
/// которого никто не читает, — мёртвый груз схемы: парсер заставляет паки его
/// нести, а поведение от него не зависит (именно так жил `type` до S4 —
/// аудит нашёл его читаемым только в `==`/`hashCode`).
///
/// Выбор из плана S4 был «фильтровать по type или убрать из схемы»: до
/// потребителя (SCR-13, открытый вопрос изоляции C8в) фильтрация по открытой
/// категории изобретала бы поведение — поэтому поле убрано, а слой причины
/// закрыт стороже: следующий «мёртвый» реквизит схемы обязан получить
/// потребителя или не войти в v1.
///
/// Guard красный при внесении неиспользуемого поля руками (S4: проверено
/// мутацией — возврат `type` в модель даёт красный; лог
/// `.tmp/logs/warning-3c-08-mutant-*.txt`).
///
/// Граница скана: потребители записи живут в `lib/features/content`
/// (парсер, сервис чтения дня, ротация). Если потребитель появится вне
/// фичи (например, в ядре или дашборде) — скан нужно расширить, и guard
/// скажет об этом красным: «модель изменилась?».
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ContentEntry: каждое поле читается потребителями (нет сирот схемы)', () {
    final modelFile = File('lib/features/content/domain/content_pack.dart');
    expect(modelFile.existsSync(), isTrue,
        reason: 'модель контент-пака переехала? обнови guard');
    final text = modelFile.readAsStringSync();

    // Срез объявления полей ContentEntry: от класса до первого @override
    // (==/hashCode идут после и читаются как «не потребитель» по построению).
    final start = text.indexOf('class ContentEntry {');
    expect(start, greaterThan(-1), reason: 'класс ContentEntry не найден');
    final end = text.indexOf('@override', start);
    expect(end, greaterThan(start),
        reason: 'не найден конец объявления полей ContentEntry');
    final classText = text.substring(start, end);

    final declared = RegExp(r'^[ \t]+final\s+[^;\n]+?\s(\w+);', multiLine: true)
        .allMatches(classText)
        .map((m) => m.group(1)!)
        .toSet();

    // Self-check сканера: пустой или усечённый срез — красный, а не «всё чисто».
    expect(declared, contains('id'),
        reason: 'сканер полей не увидел id — сломался формат модели?');
    expect(declared, contains('dateRule'),
        reason: 'сканер полей не увидел nullable-поле dateRule?');
    expect(declared.length, greaterThanOrEqualTo(5),
        reason: 'поля модели не распознались — guard не имеет права молчать');

    final consumers = <String>[];
    for (final entity
        in Directory('lib/features/content').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('.g.dart')) continue;
      if (entity.path == modelFile.path) continue;
      consumers.add(entity.readAsStringSync());
    }

    final orphans = declared
        .where((field) => !consumers.any(RegExp('\\.$field\\b').hasMatch))
        .toList()
      ..sort();

    expect(orphans, isEmpty,
        reason: 'поля схемы контент-пака без потребителя (S4): '
            '${orphans.join(', ')} — либо дайте полю потребителя, '
            'либо уберите его из схемы v1');
  });
}
