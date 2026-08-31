import 'package:flutter_test/flutter_test.dart';

import 'package:dharma_toolkit/features/calendar/data/tibetan/rational.dart';

Rational r(int n, int d) => Rational.div(n, d);

void main() {
  group('нормализация', () {
    test('НОД сокращает: 6/4 == 3/2', () {
      final x = r(6, 4);
      expect(x.numerator, BigInt.from(3));
      expect(x.denominator, BigInt.from(2));
    });

    test('знак собирается в числителе: 1/-2 == -1/2', () {
      final x = Rational(BigInt.one, BigInt.from(-2));
      expect(x.numerator, BigInt.from(-1));
      expect(x.denominator, BigInt.from(2));
      expect(x, r(-1, 2));
    });

    test('оба отрицательных: -1/-2 == 1/2', () {
      expect(Rational(BigInt.from(-1), BigInt.from(-2)), r(1, 2));
    });

    test('нулевой числитель -> 0/1', () {
      final x = r(0, -5);
      expect(x.numerator, BigInt.zero);
      expect(x.denominator, BigInt.one);
      expect(x.isZero, isTrue);
    });

    test('нулевой знаменатель бросает ArgumentError', () {
      expect(() => Rational(BigInt.one, BigInt.zero), throwsArgumentError);
    });
  });

  group('арифметика точна', () {
    test('1/3 + 1/3 + 1/3 == 1 точно', () {
      final third = r(1, 3);
      expect(third + third + third, Rational.one);
    });

    test('деление на ноль бросает', () {
      expect(() => Rational.one / Rational.zero, throwsArgumentError);
      expect(() => Rational.one % Rational.zero, throwsArgumentError);
    });

    test('сложение/вычитание разноточечных', () {
      expect(r(1, 2) + r(1, 3), r(5, 6));
      expect(r(1, 2) - r(1, 3), r(1, 6));
      expect(r(1, 2) * r(2, 3), r(1, 3));
      expect(r(1, 2) / r(2, 3), r(3, 4));
    });

    test('коммутативность + и *', () {
      final a = r(7, 12);
      final b = r(-5, 8);
      expect(a + b, b + a);
      expect(a * b, b * a);
    });

    test('ассоциативность + и *', () {
      final a = r(7, 12);
      final b = r(-5, 8);
      final c = r(3, 7);
      expect((a + b) + c, a + (b + c));
      expect((a * b) * c, a * (b * c));
    });

    test('унитарный минус и вычитание', () {
      final a = r(3, 4);
      expect(-a, r(-3, 4));
      expect(a - a, Rational.zero);
      expect(a + (-a), Rational.zero);
      expect((-a).numerator, BigInt.from(-3));
      expect((-a).denominator, BigInt.from(4));
    });

    test('точный bigint-путь: (2^64+1)/(2^64-1) не схлопывается', () {
      final big = (BigInt.one << 64) + BigInt.one;
      final den = (BigInt.one << 64) - BigInt.one;
      final x = Rational(big, den);
      // double здесь дал бы ровно 1.0 и потерял разницу; Rational — нет.
      expect(x > Rational.one, isTrue);
      expect(x - Rational.one, Rational.div(2, 1) / Rational(den, BigInt.one));
    });
  });

  group('сравнения', () {
    test('порядок', () {
      expect(r(1, 3) < r(1, 2), isTrue);
      expect(r(-1, 2) < Rational.zero, isTrue);
      expect(r(2, 4) == r(1, 2), isTrue);
      expect(r(3, 4) >= r(3, 4), isTrue);
      expect(r(3, 4) > r(2, 3), isTrue);
    });

    test('hashCode согласован с == для несокращённых форм', () {
      expect(r(2, 4).hashCode, r(1, 2).hashCode);
    });
  });

  group('floor/ceil, включая отрицательные (семантика Python)', () {
    test('floor', () {
      expect(r(3, 2).floor(), BigInt.from(1));
      expect(r(-3, 2).floor(), BigInt.from(-2));
      expect(Rational.one.floor(), BigInt.one);
      expect(r(-4, 2).floor(), BigInt.from(-2));
      expect(r(0, 5).floor(), BigInt.zero);
    });

    test('ceil', () {
      expect(r(3, 2).ceil(), BigInt.from(2));
      expect(r(-3, 2).ceil(), BigInt.from(-1));
      expect(r(-4, 2).ceil(), BigInt.from(-2));
    });

    test('floor-мод: -1/2 % 1 == 1/2 (как Fraction % 1 в tibcal)', () {
      expect(r(-1, 2) % Rational.one, r(1, 2));
      expect(r(7, 2) % Rational.one, r(1, 2));
      expect(r(6, 2) % Rational.one, Rational.zero);
      expect(r(5, 2) % r(3, 2), Rational.one); // 2.5 − 1×1.5 = 1
      expect(r(7, 2) % r(3, 2), r(1, 2)); // 3.5 − 2×1.5 = 0.5
      expect(r(-7, 2) % r(3, 2), Rational.one); // floormod: −3.5 + 3×1.5 = 1
    });

    test('fractionalPart ∈ [0,1) для отрицательных', () {
      final f = r(-13, 5).fractionalPart();
      expect(f >= Rational.zero, isTrue);
      expect(f < Rational.one, isTrue);
      expect(f, r(2, 5));
    });
  });

  group('abs / sign /toString', () {
    test('abs', () {
      expect(r(-3, 4).abs(), r(3, 4));
      expect(r(3, 4).abs(), r(3, 4));
    });

    test('sign', () {
      expect(r(-1, 2).sign, -1);
      expect(Rational.zero.sign, 0);
      expect(r(1, 2).sign, 1);
    });

    test('toString', () {
      expect(r(3, 2).toString(), '3/2');
      expect(Rational.fromInt(5).toString(), '5');
    });

    test('toDouble приближает (для логов)', () {
      expect(r(1, 2).toDouble(), closeTo(0.5, 1e-12));
    });
  });
}
