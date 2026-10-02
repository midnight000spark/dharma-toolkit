/// Тест-векторы календарных праздников 2026–2027 из пакета F-81.
///
/// Фикстура собрана из `docs/research/holidays-2026-2027/` (список владельца
/// + верификация 24.09.2026): закрепляются только пункты, подтверждённые
/// независимыми слоями (первичные таблицы календаря + внешние источники);
/// наш порт был слоем A той же проверки и независимым источником не считается.
///
/// Движки уже существуют (порт Пхугпа F-45, упосатхи Мееус F-49) — тест
/// сторожевой, а не реализующий. Чувствительность доказана мутациями
/// фикстуры (`.tmp/logs/holidays-vectors-1-mutations.txt`).
library;

import 'dart:convert';
import 'dart:io';

import 'package:dharma_toolkit/core/calendar/special_day.dart';
import 'package:dharma_toolkit/features/calendar/data/tibetan/tibetan_calendar.dart';
import 'package:dharma_toolkit/features/calendar/data/tibetan/tibetan_date.dart';
import 'package:dharma_toolkit/features/calendar/data/uposatha/uposatha_calendar_provider.dart';
import 'package:flutter_test/flutter_test.dart';

const String _fixturePath = 'test/fixtures/holiday_vectors_2026_2027.json';
const Set<String> _engines = {'phugpa', 'uposatha', 'phugpa-structure'};

Map<String, dynamic> _loadFixture() =>
    jsonDecode(File(_fixturePath).readAsStringSync()) as Map<String, dynamic>;

List<Map<String, dynamic>> _group(Map<String, dynamic> fixture, String name) =>
    (fixture[name] as List).cast<Map<String, dynamic>>();

DateTime _utcDate(String iso) {
  final p = iso.split('-').map(int.parse).toList();
  return DateTime.utc(p[0], p[1], p[2]);
}

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

int _dayDiff(DateTime a, DateTime b) => DateTime(a.year, a.month, a.day)
    .difference(DateTime(b.year, b.month, b.day))
    .inDays;

void main() {
  final fixture = _loadFixture();
  final confirmed = _group(fixture, 'confirmed');
  final disputed = _group(fixture, 'disputed');
  final refuted = _group(fixture, 'refuted');
  final open = _group(fixture, 'open');

  final uposatha = UposathaCalendarProvider(traditionTag: 'theravada_default');

  /// Дни полнолуния (упосатха «полнолуние») в диапазоне [from, to].
  List<DateTime> fullMoons(DateTime from, DateTime to) => uposatha
      .getSpecialDays(from, to)
      .where((d) =>
          d.type == SpecialDayType.uposatha && d.name.contains('полнолуние'))
      .map((d) => DateTime(d.date.year, d.date.month, d.date.day))
      .toList();

  group('фикстура: схема и честность', () {
    test('группы непусты и каждая запись несёт id/engine', () {
      final groups = {
        'confirmed': confirmed,
        'disputed': disputed,
        'refuted': refuted,
        'open': open,
      };
      for (final entry in groups.entries) {
        expect(entry.value, isNotEmpty, reason: 'группа ${entry.key}');
        for (final it in entry.value) {
          expect((it['id'] as String).isNotEmpty, isTrue);
          expect(_engines.contains(it['engine']), isTrue,
              reason: '${it['id']}: engine=${it['engine']}');
        }
      }
    });

    test('id уникальны во всех группах', () {
      final all = [...confirmed, ...disputed, ...refuted, ...open];
      final ids = all.map((e) => e['id']).toList();
      expect(ids.toSet().length, ids.length);
    });

    // Пропуск/добавление/подмена вектора обязаны красить набор: размеры и
    // состав id — контракт фикстуры, а не производная от её содержимого
    // (finding ревью: динамические проверки не ловили удаление записи).
    test('размеры групп и состав id зафиксированы', () {
      expect(confirmed, hasLength(24));
      expect(disputed, hasLength(4));
      expect(refuted, hasLength(4));
      expect(open, hasLength(3));
      expect(confirmed.map((e) => e['id']).toSet(), {
        'chotrul-duchen-2026', 'chotrul-duchen-2027',
        'saga-dawa-duchen-2026', 'saga-dawa-duchen-2027',
        'chokhor-duchen-2026', 'chokhor-duchen-2027',
        'lhabab-duchen-2026', 'lhabab-duchen-2027',
        'shoton-2026', 'shoton-2027',
        'palden-lhamo-2026', 'palden-lhamo-2027',
        'zamling-chisang-2026', 'guru-rinpoche-birth-2026',
        'guru-rinpoche-birth-2027', 'magha-puja-2026', 'magha-puja-2027',
        'visakha-puja-2026', 'visakha-puja-2027', 'asalha-puja-2026',
        'vassa-2026', 'pavarana-2026', 'pavarana-2027', 'anapanasati-2027',
      });
      expect(disputed.map((e) => e['id']).toSet(), {
        'asalha-puja-2027', 'vassa-2027',
        'longchenpa-parinirvana-2026', 'longchenpa-parinirvana-2027',
      });
      expect(refuted.map((e) => e['id']).toSet(), {
        'jigme-lingpa-parinirvana-2026', 'jigme-lingpa-parinirvana-2027',
        'anapanasati-2026', 'model-intercalary-2027',
      });
      expect(open.map((e) => e['id']).toSet(), {
        'zamling-chisang-2027', 'longchenpa-birth-2026',
        'longchenpa-birth-2027',
      });
    });

    test('атрибуция не ссылается на наш порт (слой A) как на подтверждение',
        () {
      final layerA = RegExp(r'порт|tibcal|F-45|наша реализация',
          caseSensitive: false);
      for (final it in [...confirmed, ...disputed, ...refuted, ...open]) {
        for (final s in (it['sources'] as List).cast<String>()) {
          expect(layerA.hasMatch(s), isFalse,
              reason: '${it['id']}: слой A не является независимым: $s');
        }
      }
    });

    test('закреплённое и помеченное не пересекаются по id', () {
      final pinned = {
        ...confirmed.map((e) => e['id']),
        ...refuted.map((e) => e['id']),
      };
      final unpinned = {
        ...disputed.map((e) => e['id']),
        ...open.map((e) => e['id']),
      };
      expect(pinned.intersection(unpinned), isEmpty,
          reason: 'пункт не может быть и закреплён, и помечен');
    });

    test('подтверждённое и опровергнутое несут непустые источники', () {
      for (final it in [...confirmed, ...refuted]) {
        final sources = (it['sources'] as List).cast<Object>();
        expect(sources, isNotEmpty, reason: '${it['id']}: нет атрибуции');
        for (final s in sources) {
          expect((s as String).trim(), isNotEmpty, reason: '${it['id']}');
        }
      }
    });

    test('спорное и открытое несут непустую пометку (не закрепляются)', () {
      for (final it in [...disputed, ...open]) {
        expect((it['note'] as String?)?.trim(), isNotEmpty,
            reason: '${it['id']}: нужна пометка');
      }
    });

    test('подтверждённый набор покрывает оба года и оба движка', () {
      final years =
          confirmed.map((e) => _utcDate(e['date'] as String).year).toSet();
      expect(years, containsAll(<int>[2026, 2027]));
      expect(confirmed.map((e) => e['engine']).toSet(),
          containsAll(<String>['phugpa', 'uposatha']));
      final kinds = confirmed
          .where((e) => e['engine'] == 'uposatha')
          .map((e) => e['kind'])
          .toSet();
      expect(kinds, containsAll(<String>['full_moon', 'post_full_moon']));
    });
  });

  group('Пхугпа: подтверждённые праздники ↔ лунное правило', () {
    final items = confirmed.where((e) => e['engine'] == 'phugpa').toList();

    for (final it in items) {
      final lunar = it['lunar'] as Map<String, dynamic>;
      test('${it['id']}: ${it['date']} ↔ ${lunar['month']}/${lunar['day']}',
          () {
        final date = _utcDate(it['date'] as String);
        final td = gregorianToTibetan(date);
        expect(td.isSkipped, isFalse, reason: 'день не может быть пропущен');
        expect(td.month, lunar['month'], reason: 'месяц');
        expect(td.day, lunar['day'], reason: 'день');
        expect(td.isLeapMonth, lunar['leapMonth'] ?? false,
            reason: 'вставной месяц');

        final back = tibetanToGregorian(TibetanDate(
          year: td.year,
          month: td.month,
          isLeapMonth: td.isLeapMonth,
          day: td.day,
          isLeapDay: td.isLeapDay,
        ));
        expect(_iso(back), it['date'], reason: 'обратный ход');
      });
    }
  });

  group('Тхеравада: подтверждённые даты ↔ полнолуние (±1 день, F-49)', () {
    final items = confirmed.where((e) => e['engine'] == 'uposatha').toList();

    for (final it in items) {
      test('${it['id']}: ${it['date']} (${it['kind']})', () {
        final date = _utcDate(it['date'] as String);
        final window = fullMoons(date.subtract(const Duration(days: 2)),
            date.add(const Duration(days: 2)));
        if (it['kind'] == 'full_moon') {
          final near =
              window.where((f) => _dayDiff(f, date).abs() <= 1).toList();
          expect(near, hasLength(1),
              reason: 'полнолуние в ±1 день: окно=$window');
        } else {
          // post_full_moon: полнолуние накануне, на самой дате — нет.
          final before = window.where((f) => f.isBefore(date)).toList();
          expect(before, hasLength(1),
              reason: 'полнолуние накануне: окно=$window');
          expect(_dayDiff(before.single, date), inInclusiveRange(-2, -1));
          expect(window.where((f) => !f.isBefore(date)), isEmpty,
              reason: 'на дате Вассы полнолуния нет: окно=$window');
        }
      });
    }
  });

  group('опровергнутые: контрпримеры с явной пометкой', () {
    final phugpa = refuted.where((e) => e['engine'] == 'phugpa').toList();
    for (final it in phugpa) {
      test('${it['id']}: исправленная дата верна, архивная — нет', () {
        final archive = it['archive'] as Map<String, dynamic>;
        final corrected = it['corrected'] as Map<String, dynamic>;
        final archiveLunar = archive['lunar'] as Map<String, dynamic>;
        final correctedLunar = corrected['lunar'] as Map<String, dynamic>;

        final tdCorrected =
            gregorianToTibetan(_utcDate(corrected['date'] as String));
        expect(tdCorrected.month, correctedLunar['month']);
        expect(tdCorrected.day, correctedLunar['day']);
        final back = tibetanToGregorian(TibetanDate(
          year: tdCorrected.year,
          month: tdCorrected.month,
          isLeapMonth: tdCorrected.isLeapMonth,
          day: tdCorrected.day,
          isLeapDay: tdCorrected.isLeapDay,
        ));
        expect(_iso(back), corrected['date']);

        // Архивная дата — валидный день своей (ошибочной) лунной даты,
        // но не канонический: месяц не тот.
        final tdArchive =
            gregorianToTibetan(_utcDate(archive['date'] as String));
        expect(tdArchive.month, archiveLunar['month']);
        expect(tdArchive.day, archiveLunar['day']);
        expect(tdArchive.month, isNot(correctedLunar['month']),
            reason: 'контрпример: архивная дата не 9-й месяц');
      });
    }

    test('anapanasati-2026: 05.11.2026 — не полнолуние, 24.11.2026 — полнолуние',
        () {
      final it = refuted.firstWhere((e) => e['id'] == 'anapanasati-2026');
      final archiveDate =
          _utcDate((it['archive'] as Map<String, dynamic>)['date'] as String);
      expect(
          fullMoons(archiveDate.subtract(const Duration(days: 2)),
              archiveDate.add(const Duration(days: 2))),
          isEmpty,
          reason: 'опровергнуто: 05.11.2026 не полнолуние');

      final correctedDate = _utcDate(
          (it['corrected'] as Map<String, dynamic>)['date'] as String);
      final near = fullMoons(correctedDate.subtract(const Duration(days: 2)),
              correctedDate.add(const Duration(days: 2)))
          .where((f) => _dayDiff(f, correctedDate).abs() <= 1)
          .toList();
      expect(near, hasLength(1),
          reason: 'исправление: полнолуние 24.11.2026 (±1)');
    });

    test('model-intercalary-2027: вставной 2-й месяц, вставного 1-го нет', () {
      final it = refuted.firstWhere((e) => e['id'] == 'model-intercalary-2027');
      final corrected = it['corrected'] as Map<String, dynamic>;
      final intercalary = corrected['intercalary'] as Map<String, dynamic>;
      final notIntercalary = corrected['notIntercalary'] as Map<String, dynamic>;

      expect(
        () => tibetanToGregorian(TibetanDate(
          year: notIntercalary['year'] as int,
          month: notIntercalary['month'] as int,
          isLeapMonth: true,
          day: 1,
          isLeapDay: false,
        )),
        throwsA(isA<NoSuchTibetanDayException>()),
        reason: 'вставного 1-го месяца не существует',
      );

      final leap = tibetanToGregorian(TibetanDate(
        year: intercalary['year'] as int,
        month: intercalary['month'] as int,
        isLeapMonth: true,
        day: 1,
        isLeapDay: false,
      ));
      expect(_iso(leap), intercalary['firstDate'],
          reason: 'вставной 2-й месяц начинается 09.03.2027');
      final td = gregorianToTibetan(leap);
      expect(td.isLeapMonth, isTrue);
      expect(td.month, 2);
    });
  });
}
