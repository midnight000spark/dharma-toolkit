/// Валидация схемы пака событий v1 (D-35, FR-EVT-1) — блок B пакета 6.1.
///
/// Тесты проверяют **поведение валидатора**, а не факт разбора: каждое правило
/// схемы имеет красную ветку (испорченное поле названо по имени), плюс
/// forward-compat (неизвестные поля не ломают старый код).
///
/// Фикстуры — синтетические данные, объявленные прямо в тесте: реальных
/// праздничных паков в сборке нет и не добавляется автоматически (проверенные
/// даты собирает человек-трек; выдуманная дата нарушает UX-A-4).
library;

import 'dart:convert';

import 'package:dharma_toolkit/features/events/data/event_pack_parser.dart';
import 'package:dharma_toolkit/features/events/domain/event_pack.dart';
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
      "id": "e1",
      "type": "festival",
      "name": "Синтетическое событие",
      "dateRule": {"kind": "tibetan", "month": 1, "day": 1},
      "source": "синтетическая фикстура теста"
    }
  ]
}
''') as Map<String, dynamic>;

void main() {
  group('EventPackParser — валидный пак', () {
    test('оба вида правил и атрибуция разбираются', () {
      final json = validPackJson();
      (json['entries'] as List).add({
        'id': 'e2',
        'type': 'observance',
        'name': 'Второе синтетическое событие',
        'dateRule': {'kind': 'gregorian_yearly', 'month': 2, 'day': 29},
        'source': 'синтетическая фикстура теста',
      });

      final pack = EventPackParser.parse(json);

      expect(pack.packId, 'synthetic_demo');
      expect(pack.traditionTag, 'nyingma');
      expect(pack.version, '1');
      expect(pack.verified, isFalse);
      expect(pack.entries, hasLength(2));
      expect(
        pack.entries.first.dateRule,
        const TibetanDateRule(month: 1, day: 1),
      );
      expect(
        pack.entries.last.dateRule,
        const GregorianYearlyDateRule(month: 2, day: 29),
      );
      expect(pack.entries.first.source, isNotEmpty);
      expect(pack.entries.first.dateRule.kind, EventDateRuleKind.tibetan);
    });

    test('пустой entries легален: пак-заготовка честно ничего не обещает', () {
      final json = validPackJson()..['entries'] = <dynamic>[];
      expect(EventPackParser.parse(json).entries, isEmpty);
    });

    test('неизвестные поля игнорируются — пак новой версии не ломает разбор',
        () {
      final json = validPackJson()
        ..['futureField'] = {'anything': true}
        ..['entries'][0]['futureField'] = 42;
      expect(EventPackParser.parse(json).entries, hasLength(1));
    });
  });

  group('EventPackParser — испорченная схема краснеет с именем поля', () {
    void expectField(Map<String, dynamic> json, String field) {
      expect(
        () => EventPackParser.parse(json),
        throwsA(isA<EventPackFormatException>()
            .having((e) => e.field, 'field', field)),
      );
    }

    test('packId отсутствует', () {
      expectField(validPackJson()..remove('packId'), 'packId');
    });

    test('packId пустая строка', () {
      expectField(validPackJson()..['packId'] = '   ', 'packId');
    });

    test('traditionTag отсутствует (атрибуция традиции обязательна)', () {
      expectField(validPackJson()..remove('traditionTag'), 'traditionTag');
    });

    test('verified отсутствует', () {
      expectField(validPackJson()..remove('verified'), 'verified');
    });

    test('verified не bool', () {
      expectField(validPackJson()..['verified'] = 'yes', 'verified');
    });

    test('entries отсутствует', () {
      expectField(validPackJson()..remove('entries'), 'entries');
    });

    test('entries — не список', () {
      expectField(validPackJson()..['entries'] = {'id': 'e1'}, 'entries');
    });

    test('элемент entries — не объект', () {
      expectField(validPackJson()..['entries'] = ['e1'], 'entries[0]');
    });

    test('имя записи пустое — путь называет индекс', () {
      final json = validPackJson()..['entries'][0]['name'] = '';
      expectField(json, 'entries[0].name');
    });

    test('source отсутствует (дата без источника неотличима от выдуманной)', () {
      final json = validPackJson()..['entries'][0].remove('source');
      expectField(json, 'entries[0].source');
    });

    test('type отсутствует', () {
      final json = validPackJson()..['entries'][0].remove('type');
      expectField(json, 'entries[0].type');
    });

    test('dateRule отсутствует', () {
      final json = validPackJson()..['entries'][0].remove('dateRule');
      expectField(json, 'entries[0].dateRule');
    });

    test('dateRule — не объект', () {
      final json = validPackJson()..['entries'][0]['dateRule'] = 'tibetan';
      expectField(json, 'entries[0].dateRule');
    });

    test('dateRule.kind неизвестен (закрытое перечисление v1)', () {
      final json = validPackJson()..['entries'][0]['dateRule']['kind'] = 'lunar';
      expectField(json, 'entries[0].dateRule.kind');
    });

    test('dateRule.kind отсутствует', () {
      final json = validPackJson()..['entries'][0]['dateRule'].remove('kind');
      expectField(json, 'entries[0].dateRule.kind');
    });

    test('tibetan: день 0 и 31 вне диапазона', () {
      final zero = validPackJson()..['entries'][0]['dateRule']['day'] = 0;
      expectField(zero, 'entries[0].dateRule.day');
      final tooBig = validPackJson()..['entries'][0]['dateRule']['day'] = 31;
      expectField(tooBig, 'entries[0].dateRule.day');
    });

    test('tibetan: месяц 13 вне диапазона', () {
      final json = validPackJson()..['entries'][0]['dateRule']['month'] = 13;
      expectField(json, 'entries[0].dateRule.month');
    });

    test('tibetan: день — не число', () {
      final json = validPackJson()..['entries'][0]['dateRule']['day'] = '1';
      expectField(json, 'entries[0].dateRule.day');
    });

    test('gregorian_yearly: 30 февраля не существует', () {
      final json = validPackJson()
        ..['entries'][0]['dateRule'] = {
          'kind': 'gregorian_yearly',
          'month': 2,
          'day': 30,
        };
      expectField(json, 'entries[0].dateRule.day');
    });

    test('gregorian_yearly: 31 апреля не существует', () {
      final json = validPackJson()
        ..['entries'][0]['dateRule'] = {
          'kind': 'gregorian_yearly',
          'month': 4,
          'day': 31,
        };
      expectField(json, 'entries[0].dateRule.day');
    });

    test('дубль entries[].id отвергается — id есть ключ записи', () {
      final json = validPackJson();
      (json['entries'] as List).add(
        Map<String, dynamic>.from(json['entries'][0] as Map),
      );
      expect(
        () => EventPackParser.parse(json),
        throwsA(isA<EventPackFormatException>()
            .having((e) => e.field, 'field', 'entries[1].id')
            .having((e) => e.reason, 'reason', contains('дубль'))),
      );
    });

    test('сообщение об ошибке несёт путь поля и причину', () {
      final json = validPackJson()..['entries'][0]['name'] = 7;
      try {
        EventPackParser.parse(json);
        fail('ожидалось EventPackFormatException');
      } on EventPackFormatException catch (e) {
        expect(e.toString(), contains('entries[0].name'));
        expect(e.toString(), contains('ожидалась строка'));
      }
    });
  });
}
