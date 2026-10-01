/// W23: план-провайдер событий не имеет права быть публичным без потребителя.
///
/// Факт аудита 24.09: `notificationPlanProvider` объявлен, но в `lib` его
/// никто не читает — «две действующие проводки» не подтверждались, реактивная
/// проводка плана в UI появится только на Этапе 8 (SCR-12/13), а
/// перепланирование строит план напрямую (`buildNotificationPlan`).
///
/// Пока потребителя нет, провайдер обязан быть помечен `@visibleForTesting`;
/// когда потребитель появится — аннотацию снимают, и этот сторож скажет, что
/// пометка пережила свою причину. Две стороны сторожа (урок 1):
///  * снять `@visibleForTesting` без потребителя → красный;
///  * добавить потребителя, оставив аннотацию → красный.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _declarationPath =
    'lib/features/events/presentation/providers/event_providers.dart';
const _provider = 'notificationPlanProvider';

void main() {
  test('W23: notificationPlanProvider — потребитель в lib или @visibleForTesting',
      () {
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    // Самостраховка: ослепший скан не должен молча «проходить» (урок 1).
    expect(files, isNotEmpty, reason: 'скан lib пуст — сторож ослеп');

    final source = File(_declarationPath).readAsStringSync();
    expect(source.contains('final $_provider ='), isTrue,
        reason: 'провайдер переехал? обнови адрес в стороже');

    final annotated = RegExp(
      '@visibleForTesting\\s*\\n\\s*final\\s+$_provider\\s*=',
    ).hasMatch(source);

    final consumers = <String>[];
    for (final file in files) {
      if (file.path == _declarationPath) continue;
      if (file.readAsStringSync().contains(_provider)) {
        consumers.add(file.path);
      }
    }

    if (consumers.isEmpty) {
      expect(annotated, isTrue,
          reason: 'W23: публичный $_provider без потребителя в lib — '
              'проводка на бумаге; до Этапа 8 обязана быть @visibleForTesting');
    } else {
      expect(annotated, isFalse,
          reason: 'W23: у $_provider появился потребитель (${consumers.join(', ')}) — '
              'снимите @visibleForTesting и удалите этот сторож');
    }
  });
}
