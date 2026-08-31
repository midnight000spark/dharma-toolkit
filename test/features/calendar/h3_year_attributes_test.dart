/// H-3: сверка атрибутов года pub.dev `tibetan_calendar` (MIT, v2.0.0)
/// против нашего порта (источник нумерации — tibcal, F-18/F-43).
///
/// Пакет одобрен как dev_dependency (I-3, пакет 5a). Осторожно с соглашением
/// годов: `tibetan_calendar` нумерует тибетский год как царский год
/// (Bod rGyal lo = западный + 127, `yearDiff` в его константах), тогда как
/// наш порт/источник — западным годом Лосара.
///
/// Имена животных расходятся лексически (Mouse↔Rat, Rabbit↔Hare) — сверяем
/// через словарь алиасов, фаза цикла обязана совпадать.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:tibetan_calendar/tibetan_calendar.dart' as pkg;

import 'package:dharma_toolkit/features/calendar/data/tibetan/tibetan_calendar.dart';

/// Лексические синонимы животных (наша/тиб-cal транслитерация vs пакет).
const Map<String, String> animalAlias = {
  'Rat': 'Mouse',
  'Hare': 'Rabbit',
};

void main() {
  final vectors = jsonDecode(
          File('test/fixtures/tibcal_vectors.json').readAsStringSync())
      as Map<String, dynamic>;

  // Годы Лосаров 2023–2027 + 20 векторов из g2t-потока (шаг 37 — чтобы
  // захватить разные годы и границы месяцев).
  final losarYears = (vectors['losar'] as List<dynamic>)
      .map((e) => (e as Map<String, dynamic>)['tibetanYear'] as int)
      .toList();
  final g2t = vectors['g2t'] as List<dynamic>;
  final vectorYears = <int>[
    for (var i = 0; i < g2t.length; i += 37)
      ((g2t[i] as Map<String, dynamic>)['tibetan']
          as Map<String, dynamic>)['year'] as int,
  ];
  final years = <int>{...losarYears, ...vectorYears}.toList()..sort();

  group('H-3: годичные атрибуты пакета против нашего порта', () {
    test('животное/элемент/пол совпадают для Лосаров 2023–2027 '
        'и 20+ лет из векторов (с сверкой по +127)', () {
      expect(years.length, greaterThanOrEqualTo(5));
      final mismatches = <String>[];
      for (final y in years) {
        final mine = yearAttributes(y);
        // Нумерация пакета — царский год: западный год Лосара + 127.
        final theirs = pkg.TibetanCalendar.getYearAttributes(tibetanYear: y + 127);
        final wantAnimal = animalAlias[mine.animal] ?? mine.animal;
        final wantGender =
            mine.gender[0].toUpperCase() + mine.gender.substring(1);
        if (theirs.animal != wantAnimal ||
            theirs.element != mine.element ||
            theirs.gender != wantGender) {
          mismatches.add('year $y: port=${mine.element} ${mine.gender} '
              '${mine.animal} pkg=${theirs.element} '
              '${theirs.gender.toLowerCase()} ${theirs.animal}');
        }
      }
      expect(mismatches, isEmpty,
          reason: 'расхождений: ${mismatches.length} из ${years.length}');
    });

    test('фаза 60-летия не смещена: 2020=Iron Rat, 2026=Fire Horse', () {
      final rat = pkg.TibetanCalendar.getYearAttributes(tibetanYear: 2020 + 127);
      expect('${rat.element} ${rat.gender} ${rat.animal}', 'Iron Male Mouse');
      final horse =
          pkg.TibetanCalendar.getYearAttributes(tibetanYear: 2026 + 127);
      expect('${horse.element} ${horse.gender} ${horse.animal}',
          'Fire Male Horse');
    });
  });
}
