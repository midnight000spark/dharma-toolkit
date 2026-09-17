/// Загрузчик контент-паков: честные сбои и честная пустота (блок A пакета 7.0).
///
/// Проверяется поведение на сбоях, а не «счастливый разбор»:
///  * отсутствующий ассет / битый JSON / не-объект / невалидная схема →
///    запись в `failures` с причиной, **без исключения** (сломанный пак не
///    валит ленту контента — вместо текста пользователь получит фолбэк
///    FR-CNT-3, а не краш);
///  * один сломанный пак не уносит соседний (частичный успех — это норма);
///  * дубль `packId` отвергается: ключ пака обязан быть уникальным;
///  * пустой список паков — легальное «контента пока нет», не ошибка.
///
/// `rootBundle` в тестах не используется вовсе (инъекция читателя): это и
/// сохраняет детерминизм, и снимает F-58 (реальный I/O внутри fake-async зоны).
/// Файловая фикстура читается в обычном `test()`, вне `testWidgets`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dharma_toolkit/features/content/data/content_pack_loader.dart';
import 'package:dharma_toolkit/features/content/domain/content_pack.dart';
import 'package:flutter_test/flutter_test.dart';

/// Синтетический фикстур-файл (имя подчёркивает, что тексты вымышлены).
const syntheticFixture = 'test/fixtures/content/synthetic_content_pack_v1.json';

/// Читатель из памяти: ключ → содержимое.
ContentPackAssetReader readerOf(Map<String, String> assets) => (key) async {
      final value = assets[key];
      if (value == null) {
        throw FileSystemException('ассет отсутствует', key);
      }
      return value;
    };

String packJson({
  required String packId,
  String traditionTag = 'nyingma',
  bool verified = false,
  List<Map<String, dynamic>>? entries,
}) =>
    jsonEncode({
      'packId': packId,
      'traditionTag': traditionTag,
      'version': '1',
      'verified': verified,
      'entries': entries ??
          [
            {
              'id': 'c1',
              'type': 'daily_reading',
              'title': 'Синтетическое чтение',
              'body': 'Синтетический текст фикстуры.',
              'source': 'синтетическая фикстура теста',
            }
          ],
    });

void main() {
  group('ContentPackLoader — пустота и сбои', () {
    test('пустой список паков → пустой итог без сбоев (не ошибка)', () async {
      final result = await ContentPackLoader(readAsset: readerOf({})).load([]);

      expect(result.packs, isEmpty);
      expect(result.failures, isEmpty);
      expect(result.hasFailures, isFalse);
      expect(ContentPackLoadResult.empty.packs, isEmpty);
    });

    test('ассет не найден → сбой с причиной, исключение не летит', () async {
      final result = await ContentPackLoader(readAsset: readerOf({}))
          .load(['assets/content_packs/missing.json']);

      expect(result.packs, isEmpty);
      expect(result.failures, hasLength(1));
      expect(result.failures.single.assetKey,
          'assets/content_packs/missing.json');
      expect(result.failures.single.reason, contains('не прочитан'));
    });

    test('битый JSON → сбой с причиной', () async {
      final result = await ContentPackLoader(
              readAsset: readerOf({'p.json': '{ не json'}))
          .load(['p.json']);

      expect(result.packs, isEmpty);
      expect(result.failures.single.reason, contains('битый JSON'));
    });

    test('JSON-массив вместо объекта пака → сбой', () async {
      final result =
          await ContentPackLoader(readAsset: readerOf({'p.json': '[]'}))
              .load(['p.json']);

      expect(result.failures.single.reason, contains('ожидался объект пака'));
    });

    test('невалидная схема → сбой с путём поля, валидный пак рядом доезжает',
        () async {
      final bad = jsonEncode({
        'packId': 'bad',
        'traditionTag': 'nyingma',
        'version': '1',
        'verified': false,
        'entries': [
          {
            'id': 'c1',
            'type': 'daily_reading',
            'title': 'Синтетическое чтение',
            'body': 'Синтетический текст.',
            'source': '',
          }
        ],
      });
      final result = await ContentPackLoader(readAsset: readerOf({
        'bad.json': bad,
        'good.json': packJson(packId: 'good'),
      })).load(['bad.json', 'good.json']);

      expect(result.packs, hasLength(1));
      expect(result.packs.single.packId, 'good');
      expect(result.failures, hasLength(1));
      expect(result.failures.single.assetKey, 'bad.json');
      expect(result.failures.single.reason, contains('entries[0].source'));
    });

    test('дубль packId отвергается, первый пак сохранён', () async {
      final result = await ContentPackLoader(readAsset: readerOf({
        'a.json': packJson(packId: 'same', verified: true),
        'b.json': packJson(packId: 'same'),
      })).load(['a.json', 'b.json']);

      expect(result.packs, hasLength(1));
      expect(result.packs.single.packId, 'same');
      expect(result.packs.single.verified, isTrue);
      expect(result.failures, hasLength(1));
      expect(result.failures.single.assetKey, 'b.json');
      expect(result.failures.single.reason, contains('дубль packId'));
    });

    test('флаг verified и traditionTag доезжают до модели как есть (честность)',
        () async {
      final result = await ContentPackLoader(
              readAsset: readerOf({'p.json': packJson(packId: 'p')}))
          .load(['p.json']);

      expect(result.packs.single.verified, isFalse);
      expect(result.packs.single.traditionTag, 'nyingma');
    });

    test('запись без dateRule доезжает с null-правилом (пул ротации)', () async {
      final result = await ContentPackLoader(
              readAsset: readerOf({'p.json': packJson(packId: 'p')}))
          .load(['p.json']);

      expect(result.packs.single.entries.single.dateRule, isNull);
    });
  });

  group('ContentPackLoader — файловая синтетическая фикстура', () {
    test('фикстур-файл назван синтетическим (защита от выдуманных текстов)',
        () {
      expect(syntheticFixture, contains('synthetic'));
      final text = File(syntheticFixture).readAsStringSync();
      // Каждая запись фикстуры обязана объявлять себя вымыслом: реальные тексты
      // и их лицензии собирает человек-трек, а не тестовые данные (FR-CNT-4).
      final json = jsonDecode(text) as Map<String, dynamic>;
      for (final entry in json['entries'] as List) {
        expect(entry['source'] as String, contains('синтетическ'));
      }
    });

    test('файл читается и разбирается тем же путём, что продовый ассет',
        () async {
      final result = await ContentPackLoader(
        readAsset: (key) async => File(key).readAsString(),
      ).load([syntheticFixture]);

      expect(result.failures, isEmpty);
      expect(result.packs, hasLength(1));
      expect(result.packs.single.packId, 'synthetic_content_demo');
      expect(result.packs.single.verified, isFalse);
      expect(result.packs.single.entries, hasLength(3));
      expect(result.packs.single.entries[0].dateRule, isNull);
      expect(result.packs.single.entries[1].dateRule,
          const TibetanContentDateRule(month: 10, day: 25));
      expect(result.packs.single.entries[2].dateRule,
          const GregorianYearlyContentDateRule(month: 2, day: 29));
    });
  });
}
