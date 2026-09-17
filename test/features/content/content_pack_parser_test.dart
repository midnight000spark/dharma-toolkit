/// Валидация схемы контент-пака v1 (FR-CNT-1/2/4) — блок A пакета 7.0.
///
/// Тесты проверяют **поведение валидатора**, а не факт разбора: каждое правило
/// схемы имеет красную ветку (испорченное поле названо по имени), плюс
/// forward-compat (неизвестные поля не ломают старый код) и ключевое отличие
/// контент-схемы от событийной — **опциональный** `dateRule` при **обязательном**
/// `source`.
///
/// Фикстуры — синтетические данные, объявленные прямо в тесте: реальных
/// контент-паков в сборке нет и не добавляется автоматически (тексты, прошедшие
/// правовую проверку, собирает человек-трек; выдуманная атрибуция нарушает
/// FR-CNT-4/UX-A-4).
library;

import 'dart:convert';

import 'package:dharma_toolkit/features/content/data/content_pack_parser.dart';
import 'package:dharma_toolkit/features/content/domain/content_pack.dart';
import 'package:flutter_test/flutter_test.dart';

/// Минимальный валидный пак; тесты портят ровно одно поле.
Map<String, dynamic> validPackJson() => jsonDecode('''
{
  "packId": "synthetic_demo",
  "traditionTag": "nyingma",
  "version": "1",
  "verified": false,
  "entries": [
    {
      "id": "c1",
      "type": "daily_reading",
      "title": "Синтетическое чтение",
      "body": "Синтетический текст фикстуры.",
      "source": "синтетическая фикстура теста",
      "dateRule": {"kind": "gregorian_yearly", "month": 1, "day": 1}
    }
  ]
}
''') as Map<String, dynamic>;

/// Пак с одной записью, у которой [mutate] испортило поле.
Map<String, dynamic> packWithEntry(void Function(Map<String, dynamic>) mutate) {
  final json = validPackJson();
  final entry = (json['entries'] as List).first as Map<String, dynamic>;
  mutate(entry);
  return json;
}

/// Ожидать отказ схемы с названным путём поля; вернуть причину.
String expectRejected(Map<String, dynamic> json, String expectedField) {
  try {
    ContentPackParser.parse(json);
  } on ContentPackFormatException catch (e) {
    expect(e.field, expectedField);
    return e.reason;
  }
  fail('ожидался ContentPackFormatException по полю "$expectedField"');
}

void main() {
  group('ContentPackParser — валидный пак', () {
    test('оба вида правил и атрибуция разбираются', () {
      final json = validPackJson();
      (json['entries'] as List).add({
        'id': 'c2',
        'type': 'quote',
        'title': 'Синтетическая цитата',
        'body': 'Синтетический текст.',
        'source': 'синтетическая фикстура теста',
        'dateRule': {'kind': 'tibetan', 'month': 10, 'day': 25},
      });

      final pack = ContentPackParser.parse(json);

      expect(pack.packId, 'synthetic_demo');
      expect(pack.traditionTag, 'nyingma');
      expect(pack.version, '1');
      expect(pack.verified, isFalse);
      expect(pack.entries, hasLength(2));
      expect(pack.entries.first.dateRule,
          const GregorianYearlyContentDateRule(month: 1, day: 1));
      expect(pack.entries.last.dateRule,
          const TibetanContentDateRule(month: 10, day: 25));
      expect(pack.entries.first.source, 'синтетическая фикстура теста');
    });

    test('запись без dateRule легальна: текст живёт в пуле ротации', () {
      final json = packWithEntry((entry) => entry.remove('dateRule'));

      final pack = ContentPackParser.parse(json);

      expect(pack.entries.single.dateRule, isNull);
    });

    test('пустой entries легален: пак-заготовка честно ничего не обещает', () {
      final json = validPackJson()..['entries'] = <dynamic>[];

      final pack = ContentPackParser.parse(json);

      expect(pack.entries, isEmpty);
    });

    test('неизвестные поля игнорируются — пак новой версии не ломает разбор',
        () {
      final json = validPackJson()
        ..['futureField'] = {'deep': true}
        ..['entries'] = [
          {
            'id': 'c1',
            'type': 'daily_reading',
            'title': 'Синтетическое чтение',
            'body': 'Синтетический текст.',
            'source': 'синтетическая фикстура теста',
            'futureEntryField': 42,
          }
        ];

      final pack = ContentPackParser.parse(json);

      expect(pack.entries.single.id, 'c1');
    });
  });

  group('ContentPackParser — испорченная схема краснеет с именем поля', () {
    test('packId отсутствует', () {
      final json = validPackJson()..remove('packId');

      final reason = expectRejected(json, 'packId');

      expect(reason, contains('отсутствует'));
    });

    test('packId пустая строка', () {
      final json = validPackJson()..['packId'] = '   ';

      expect(expectRejected(json, 'packId'), contains('пустая строка'));
    });

    test('traditionTag отсутствует (привязка традиции обязательна)', () {
      final json = validPackJson()..remove('traditionTag');

      expect(expectRejected(json, 'traditionTag'), contains('отсутствует'));
    });

    test('version отсутствует', () {
      final json = validPackJson()..remove('version');

      expect(expectRejected(json, 'version'), contains('отсутствует'));
    });

    test('version — не строка (единый тип версии во всех схемах)', () {
      final json = validPackJson()..['version'] = 1;

      expect(expectRejected(json, 'version'), contains('ожидалась строка'));
    });

    test('verified отсутствует', () {
      final json = validPackJson()..remove('verified');

      expect(expectRejected(json, 'verified'), contains('отсутствует'));
    });

    test('verified не bool', () {
      final json = validPackJson()..['verified'] = 'да';

      expect(expectRejected(json, 'verified'), contains('ожидался bool'));
    });

    test('entries отсутствует', () {
      final json = validPackJson()..remove('entries');

      expect(expectRejected(json, 'entries'), contains('отсутствует'));
    });

    test('entries — не список', () {
      final json = validPackJson()..['entries'] = {'c1': true};

      expect(expectRejected(json, 'entries'), contains('ожидался список'));
    });

    test('элемент entries — не объект', () {
      final json = validPackJson()..['entries'] = ['строка'];

      expect(expectRejected(json, 'entries[0]'), contains('объект записи'));
    });

    test('id отсутствует', () {
      final json = packWithEntry((entry) => entry.remove('id'));

      expect(expectRejected(json, 'entries[0].id'), contains('отсутствует'));
    });

    test('type отсутствует', () {
      final json = packWithEntry((entry) => entry.remove('type'));

      expect(expectRejected(json, 'entries[0].type'), contains('отсутствует'));
    });

    test('title отсутствует', () {
      final json = packWithEntry((entry) => entry.remove('title'));

      expect(expectRejected(json, 'entries[0].title'), contains('отсутствует'));
    });

    test('body пустой — текст без содержания не запись', () {
      final json = packWithEntry((entry) => entry['body'] = '');

      expect(expectRejected(json, 'entries[0].body'), contains('пустая строка'));
    });

    test('source отсутствует (текст без источника неотличим от выдуманного)',
        () {
      final json = packWithEntry((entry) => entry.remove('source'));

      expect(expectRejected(json, 'entries[0].source'), contains('отсутствует'));
    });

    test('source пустая строка — атрибуция-заглушка не считается атрибуцией',
        () {
      final json = packWithEntry((entry) => entry['source'] = '  ');

      expect(expectRejected(json, 'entries[0].source'), contains('пустая строка'));
    });

    test('dateRule — не объект (присутствующее поле обязано быть валидным)',
        () {
      final json = packWithEntry((entry) => entry['dateRule'] = 'tibetan');

      expect(expectRejected(json, 'entries[0].dateRule'),
          contains('объект правила даты'));
    });

    test('dateRule без kind не считается «правила нет»', () {
      final json = packWithEntry((entry) => entry['dateRule'] = <String, dynamic>{});

      expect(expectRejected(json, 'entries[0].dateRule.kind'),
          contains('отсутствует'));
    });

    test('dateRule.kind неизвестен (закрытое перечисление v1)', () {
      final json =
          packWithEntry((entry) => entry['dateRule'] = {'kind': 'lunar'});

      expect(expectRejected(json, 'entries[0].dateRule.kind'),
          contains('неизвестный вид правила'));
    });

    test('tibetan: день 0 и 31 вне диапазона', () {
      for (final day in [0, 31]) {
        final json = packWithEntry((entry) =>
            entry['dateRule'] = {'kind': 'tibetan', 'month': 1, 'day': day});

        expect(expectRejected(json, 'entries[0].dateRule.day'),
            contains('вне диапазона'));
      }
    });

    test('tibetan: месяц 13 вне диапазона', () {
      final json = packWithEntry((entry) =>
          entry['dateRule'] = {'kind': 'tibetan', 'month': 13, 'day': 1});

      expect(expectRejected(json, 'entries[0].dateRule.month'),
          contains('вне диапазона'));
    });

    test('tibetan: день — не число', () {
      final json = packWithEntry((entry) =>
          entry['dateRule'] = {'kind': 'tibetan', 'month': 1, 'day': '1'});

      expect(expectRejected(json, 'entries[0].dateRule.day'),
          contains('целое число'));
    });

    test('gregorian_yearly: 30 февраля не существует', () {
      final json = packWithEntry((entry) => entry['dateRule'] = {
            'kind': 'gregorian_yearly',
            'month': 2,
            'day': 30
          });

      expect(expectRejected(json, 'entries[0].dateRule.day'),
          contains('вне диапазона'));
    });

    test('gregorian_yearly: 31 апреля не существует', () {
      final json = packWithEntry((entry) => entry['dateRule'] = {
            'kind': 'gregorian_yearly',
            'month': 4,
            'day': 31
          });

      expect(expectRejected(json, 'entries[0].dateRule.day'),
          contains('вне диапазона'));
    });

    test('дубль entries[].id отвергается — id есть ключ записи', () {
      final json = validPackJson();
      final first = (json['entries'] as List).first as Map<String, dynamic>;
      (json['entries'] as List).add({...first, 'title': 'Другой заголовок'});

      final reason = expectRejected(json, 'entries[1].id');

      expect(reason, contains('дубль идентификатора'));
    });

    test('сообщение об ошибке несёт путь поля и причину', () {
      final json = packWithEntry((entry) => entry.remove('title'));

      try {
        ContentPackParser.parse(json);
        fail('ожидался ContentPackFormatException');
      } on ContentPackFormatException catch (e) {
        expect(e.toString(), contains('entries[0].title'));
        expect(e.toString(), contains('Контент-пак невалиден'));
      }
    });
  });
}
