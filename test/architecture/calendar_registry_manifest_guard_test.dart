/// W4/S6 (п. 11.3): ключи реестра календарей = теги пресетов из манифеста.
///
/// Решение 30.09: ключ выбора и матчинга календарного движка — **тег
/// пресета** (`preset.id`), а поле схемы `tradition` — таксономия
/// (группировка/фильтры). Реестр `calendarProviderForTagProvider` объявляет
/// ключи прямо в исходнике, поэтому сторож сверяет их с манифестом
/// `presets/index.json` и с тем, какие пресеты реально объявляют модуль
/// `calendar`.
///
/// Две стороны инварианта (урок 1):
///  * **ключ реестра вне манифеста** → красный: мёртвый/опечатанный ключ,
///    календарь которого недостижим;
///  * **пресет с модулем `calendar` без ключа реестра** → красный: для него
///    календарь молча деградирует в `null` (класс «разметка отсекается»,
///    ради которого W4/S6 и заведён).
///
/// Сторож аттестован мутациями в обе стороны (ключ `'kagyu'` вне манифеста;
/// снятый ключ `'nyingma'`) — обе красные, лог пакета warning-3c.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _registryPath =
    'lib/features/calendar/presentation/providers/calendar_providers.dart';
const _manifestPath = 'presets/index.json';

/// Ключи `switch`-реестра из исходника: строковые литералы вида `'key' =>`
/// в блоке после `switch (…)` внутри объявления реестра.
Set<String> _extractRegistryKeys(String source) {
  final declaration = source.indexOf('calendarProviderForTagProvider');
  expect(declaration, greaterThanOrEqualTo(0),
      reason: 'реестр переехал? обнови адрес в стороже');

  final switchStart = source.indexOf('switch (', declaration);
  expect(switchStart, greaterThanOrEqualTo(0),
      reason: 'switch-реестр не найден после объявления');

  final switchEnd = source.indexOf('_ =>', switchStart);
  expect(switchEnd, greaterThanOrEqualTo(0),
      reason: 'дефолтная ветка реестра не найдена — разметку не разобрать');

  final block = source.substring(switchStart, switchEnd);
  return RegExp(r"'([a-z0-9_]+)'\s*=>")
      .allMatches(block)
      .map((m) => m.group(1)!)
      .toSet();
}

void main() {
  test('W4/S6: ключи реестра календарей = теги пресетов манифеста', () {
    final registrySource = File(_registryPath).readAsStringSync();
    final registryKeys = _extractRegistryKeys(registrySource);
    // Самостраховка: ослепший скан не имеет права молча «проходить».
    expect(registryKeys, isNotEmpty,
        reason: 'скан реестра пуст — сторож ослеп');

    final manifest = jsonDecode(File(_manifestPath).readAsStringSync())
        as Map<String, dynamic>;
    final manifestIds =
        (manifest['presets'] as List).cast<String>().toSet();
    expect(manifestIds, isNotEmpty,
        reason: 'манифест пуст — сторож ослеп');

    // Пресеты, объявившие модуль `calendar`, обязаны иметь движок в реестре;
    // заодно: id внутри файла совпадает с ключом манифеста (иначе запись
    // теряет адрес и реестр ссылается в пустоту).
    final calendarPresetIds = <String>{};
    for (final id in manifestIds) {
      final file = File('presets/$id.json');
      expect(file.existsSync(), isTrue,
          reason: 'манифест ссылается на presets/$id.json — файла нет');
      final preset =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      expect(preset['id'], id,
          reason: 'presets/$id.json объявляет id "${preset['id']}" — '
              'ключ манифеста и id пресета обязаны совпадать');
      final modules = (preset['modules'] as List).cast<String>();
      if (modules.contains('calendar')) {
        calendarPresetIds.add(id);
      }
    }

    expect(
      registryKeys.difference(manifestIds),
      isEmpty,
      reason: 'W4/S6: ключ реестра календарей вне манифеста — '
          'мёртвый/опечатанный ключ: ${registryKeys.difference(manifestIds)}',
    );
    expect(
      calendarPresetIds.difference(registryKeys),
      isEmpty,
      reason: 'W4/S6: пресет с модулем calendar без ключа в реестре — '
          'календарь молча деградирует в null: '
          '${calendarPresetIds.difference(registryKeys)}',
    );
  });
}
