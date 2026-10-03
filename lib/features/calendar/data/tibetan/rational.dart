/// Точная рациональная арифметика поверх [BigInt] (D-18).
///
/// Единственный арифметический тип тибетского календаря: `double` в формулах
/// запрещён, потому что цена ошибки накопления — сдвиг пропущенного/двойного
/// дня (F-2, D-18).
///
/// Семантика повторяет `fractions.Fraction` из Python-источника
/// dorjeduck/tibcal (`public/tibetan_calendar.py`, строка 27; лицензия MIT,
/// источник указан в шапке портируемых файлов): знаменатель всегда положителен,
/// знак живёт в числителе, дробь нормализована по НОД.
library;

/// Точная дробь `numerator / denominator` на BigInt.
///
/// Поверхность сужена до нужного календарю (§4.1(i) ревью 19.09): `ceil`,
/// `abs`, `sign`, `isNegative`, `isZero`, `toDouble`, `operator %` и статик
/// `one` сняты — у них не было потребителей вне собственных тестов. Возврат —
/// только вместе с реальным потребителем, не «на будущее».
class Rational implements Comparable<Rational> {
  /// Числитель (несёт знак).
  final BigInt numerator;

  /// Знаменатель (всегда > 0, взаимно прост с числителем).
  final BigInt denominator;

  Rational._(this.numerator, this.denominator);

  /// Создаёт нормализованную дробь [numerator]/[denominator].
  ///
  /// Бросает [ArgumentError] при нулевом знаменателе.
  factory Rational(BigInt numerator, BigInt denominator) {
    if (denominator == BigInt.zero) {
      throw ArgumentError('Rational: denominator must not be zero');
    }
    var n = numerator;
    var d = denominator;
    if (d < BigInt.zero) {
      n = -n;
      d = -d;
    }
    if (n == BigInt.zero) {
      return Rational._(BigInt.zero, BigInt.one);
    }
    final g = _gcd(n, d);
    if (g > BigInt.one) {
      n = n ~/ g;
      d = d ~/ g;
    }
    return Rational._(n, d);
  }

  /// Дробь `value / 1`.
  factory Rational.fromInt(int value) =>
      Rational(BigInt.from(value), BigInt.one);

  /// Дробь `num / den` из int (int — 64-битный, переполнение не ожидается
  /// в аргументах календаря, но наружные вызовы обязаны это гарантировать).
  factory Rational.div(int numerator, int denominator) =>
      Rational(BigInt.from(numerator), BigInt.from(denominator));

  /// 0.
  static final Rational zero = Rational.fromInt(0);

  static BigInt _gcd(BigInt a, BigInt b) {
    var x = a.abs();
    var y = b.abs();
    while (y != BigInt.zero) {
      final t = x % y;
      x = y;
      y = t;
    }
    return x;
  }

  /// Сложение.
  Rational operator +(Rational other) => Rational(
        numerator * other.denominator + other.numerator * denominator,
        denominator * other.denominator,
      );

  /// Вычитание.
  Rational operator -(Rational other) => Rational(
        numerator * other.denominator - other.numerator * denominator,
        denominator * other.denominator,
      );

  /// Умножение.
  Rational operator *(Rational other) => Rational(
        numerator * other.numerator,
        denominator * other.denominator,
      );

  /// Деление. Бросает [ArgumentError] при делении на ноль.
  Rational operator /(Rational other) {
    if (other.numerator == BigInt.zero) {
      throw ArgumentError('Rational: division by zero');
    }
    return Rational(
      numerator * other.denominator,
      denominator * other.numerator,
    );
  }

  /// Знакопеременение.
  Rational operator -() => Rational._(-numerator, denominator);

  /// Меньше.
  bool operator <(Rational other) => compareTo(other) < 0;

  /// Меньше или равно.
  bool operator <=(Rational other) => compareTo(other) <= 0;

  /// Больше.
  bool operator >(Rational other) => compareTo(other) > 0;

  /// Больше или равно.
  bool operator >=(Rational other) => compareTo(other) >= 0;

  @override
  int compareTo(Rational other) => (numerator * other.denominator)
      .compareTo(other.numerator * denominator);

  @override
  bool operator ==(Object other) =>
      other is Rational &&
      numerator == other.numerator &&
      denominator == other.denominator;

  @override
  int get hashCode => Object.hash(numerator, denominator);

  /// Наименьшее целое, не превосходящее значение (семантика `__floor__`
  /// Python: floor(−3/2) = −2).
  BigInt floor() => _floorDiv(numerator, denominator);

  /// Дробная часть `this − floor(this)` ∈ [0, 1) — как `x % 1` у Fraction
  /// в tibcal (строки 193–194).
  Rational fractionalPart() => this - Rational(floor(), BigInt.one);

  static BigInt _floorDiv(BigInt a, BigInt b) {
    // Dart `%` для b > 0 даёт floor-остаток (0 <= r < b); b здесь положителен
    // по инварианту Rational, у внешних вызовов — проверяемый аргумент.
    final r = a % b;
    final t = (a - r) ~/ b;
    return t;
  }

  @override
  String toString() =>
      denominator == BigInt.one ? '$numerator' : '$numerator/$denominator';
}
