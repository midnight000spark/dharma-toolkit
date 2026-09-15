/// Tier-0 сверка усечённых рядов Луны с первоисточником (R-24).
///
/// Точка опоры — собственный пример книги: Meeus, *Astronomical Algorithms*,
/// Example 47.a (1992-04-12.0 TD, JD 2448724.5): λ = 133.162655°,
/// β = −3.229126°. Усечение до 15 членов долготы (табл. 47.A) и 5 членов
/// широты (табл. 47.B) обязано держаться в пределах ~0.1° от полного ряда.
/// До правки R-24 тот же ряд давал λ +0.28° и β +4.86° к примеру книги —
/// тест краснеет на искажённом аргументе ряда (проверено мутацией).
///
/// Второй слой — 149 моментов фаз astronomia (F-49, точные моменты Мееуса
/// гл. 49, моменты `jde` фикстуры). В момент четверти элонгация равна
/// 90°/270° независимо от широты, поэтому `moonPhase` там обязан совпасть с
/// 0.25/0.75 с точностью ряда: замерено ≤0.0002 после правки против ≤0.0013
/// до неё. Для новолуния/полнолуния конвенция даёт сдвиг |β|/360 (до 0.0145)
/// — он покрыт отдельным, намеренно широким допуском.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dharma_toolkit/features/calendar/data/uposatha/moon_phase.dart';
import 'package:flutter_test/flutter_test.dart';

/// Meeus Example 47.a: 1992-04-12.0 TD.
const double _jdMeeus47a = 2448724.5;
const double _meeusLambda = 133.162655;
const double _meeusBeta = -3.229126;

/// Допуск усечения ряда: 15/5 членов дают ~0.02°, т.е. с запасом < 0.1°.
const double _truncationToleranceDeg = 0.1;

/// Момент события фазы из фикстуры: `jde` — в шкале TT.
class _Event {
  const _Event(this.type, this.utcMoment);
  final String type;
  final DateTime utcMoment;
}

/// JD (UT) → DateTime UTC (Meeus 7.a–7.g — та же формула, что в генераторе
/// фикстуры `scripts/gen_uposatha_vectors.mjs`).
DateTime _jdToUtc(double jd) {
  final z = (jd + 0.5).floorToDouble();
  final f = jd + 0.5 - z;
  var a = z;
  if (z >= 2299161) {
    final alpha = ((z - 1867216.25) / 36524.25).floorToDouble();
    a = z + 1 + alpha - (alpha / 4).floorToDouble();
  }
  final b = a + 1524;
  final c = ((b - 122.1) / 365.25).floorToDouble();
  final d = (365.25 * c).floorToDouble();
  final e = ((b - d) / 30.6001).floorToDouble();
  final dayFull = b - d - (30.6001 * e).floorToDouble() + f;
  final day = dayFull.floor();
  final month = e < 14 ? e - 1 : e - 13;
  final year = month > 2 ? c - 4716 : c - 4715;
  final hours = (dayFull - day) * 24;
  final h = hours.floor();
  final min = ((hours - h) * 60).floor();
  final sec = (((hours - h) * 60 - min) * 60).round();
  return DateTime.utc(year.toInt(), month.toInt(), day, h, min, sec);
}

/// ΔT = TT − UT, сек: полином Эспенака–Мееуса, как в генераторе фикстуры.
double _deltaTsec(int year) {
  final t = (year - 2000).toDouble();
  return 62.92 + 0.32217 * t + 0.005589 * t * t;
}

List<_Event> _loadEvents() {
  final raw = jsonDecode(
          File('test/fixtures/moon_phase_vectors.json').readAsStringSync())
      as Map<String, dynamic>;
  return [
    for (final e in raw['events'] as List)
      () {
        final m = e as Map<String, dynamic>;
        final jde = (m['jde'] as num).toDouble();
        // Конвенция F-49: utcDate = UTC-день момента (TT минус ΔT).
        final ttYear = _jdToUtc(jde).year;
        return _Event(
          m['type'] as String,
          _jdToUtc(jde - _deltaTsec(ttYear) / 86400.0),
        );
      }(),
  ];
}

/// Циклическая разность фаз (на случай перехода через 0/1).
double _phaseDistance(double a, double b) {
  var d = (a - b).abs() % 1.0;
  if (d > 0.5) d = 1 - d;
  return d;
}

void main() {
  group('R-24 / Tier-0: пример 47.a Мееуса', () {
    test('долгота и широта Луны в 0.1° от книжных значений', () {
      // Пример книги — 1992-04-12.0 TD; разница TT−UT (~59 с) при точности
      // 0.1° пренебрежима, поэтому берём тот же календарный момент.
      final pos = moonEclipticPosition(DateTime.utc(1992, 4, 12));

      expect(
        (pos.longitude - _meeusLambda).abs(),
        lessThan(_truncationToleranceDeg),
        reason: 'λ=${pos.longitude} против книжного $_meeusLambda '
            '(искажение аргументов ряда долготы — см. R-24)',
      );
      expect(
        (pos.latitude - _meeusBeta).abs(),
        lessThan(_truncationToleranceDeg),
        reason: 'β=${pos.latitude} против книжного $_meeusBeta '
            '(аргумент ряда широты — F, а не выдуманный «D′»)',
      );
      // Контроль знака/масштаба: широта обязана быть в физических пределах.
      expect(pos.latitude.abs(), lessThanOrEqualTo(5.3));
      expect(pos.longitude, inInclusiveRange(0.0, 360.0));
      expect(_jdMeeus47a, 2448724.5); // якорь примера из книги
    });
  });

  group('R-24: моменты фаз astronomia (149 событий, F-49)', () {
    final events = _loadEvents();

    test('фикстура цела: 149 событий четырёх типов', () {
      expect(events, hasLength(149));
      expect(events.map((e) => e.type).toSet(),
          {'new', 'first', 'full', 'last'});
    });

    test('четверти: в точный момент фазы moonPhase = 0.25 / 0.75', () {
      final violations = <String>[];
      for (final e in events) {
        final target = e.type == 'first' ? 0.25 : 0.75;
        if (e.type != 'first' && e.type != 'last') continue;
        final p = moonPhase(e.utcMoment);
        if (_phaseDistance(p, target) > 0.0005) {
          violations.add('${e.utcMoment.toIso8601String()} ${e.type}: '
              'phase=$p, расхождение ${_phaseDistance(p, target)}');
        }
      }
      expect(violations, isEmpty,
          reason: 'в момент четверти элонгация = 90°/270° тождественно, '
              'поэтому расхождение — ошибка ряда: $violations');
    });

    test('новолуние/полнолуние: сдвиг не больше широтного (|β|/360)', () {
      // Порог: максимум |β| = 5.3° → 0.0147 доли фазы + запас на усечение.
      const tolerance = 0.016;
      final violations = <String>[];
      for (final e in events) {
        if (e.type != 'new' && e.type != 'full') continue;
        final target = e.type == 'new' ? 0.0 : 0.5;
        final p = moonPhase(e.utcMoment);
        if (_phaseDistance(p, target) > tolerance) {
          violations.add('${e.utcMoment.toIso8601String()} ${e.type}: '
              'phase=$p, расхождение ${_phaseDistance(p, target)}');
        }
      }
      expect(violations, isEmpty,
          reason: 'элонгация ≠ разность долгот: сдвиг |β|/360 неизбежен по '
              'конвенции величины, но больше него расхождение быть не должно: '
              '$violations');
    });
  });
}
