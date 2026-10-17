class CalculationMath {
  static (BigInt, int) decimal(double value) {
    if (!value.isFinite)
      throw ArgumentError.value(value, 'value', 'Must be finite');
    final parts = value.toString().toLowerCase().split('e');
    final mantissa = parts[0];
    final fraction = mantissa.contains('.') ? mantissa.split('.')[1].length : 0;
    final exponent = parts.length == 2 ? int.parse(parts[1]) : 0;
    return (BigInt.parse(mantissa.replaceAll('.', '')), fraction - exponent);
  }

  /// Точное округление HALF-UP (не банковское) произведения на базе BigInt,
  /// полностью эквивалентное Python Decimal(v).quantize(..., ROUND_HALF_UP) и функции Excel ROUND().
  static double productRounded(double a, double b, int digits,
      {bool divideBy100 = false}) {
    if (a == 0.0 || b == 0.0) return 0.0;
    final (an, ad) = decimal(a);
    final (bn, bd) = decimal(b);
    var n = an * bn;
    final scale = ad + bd + (divideBy100 ? 2 : 0) - digits;
    final d = scale > 0 ? BigInt.from(10).pow(scale) : BigInt.one;
    if (scale < 0) n *= BigInt.from(10).pow(-scale);
    final rounded = (n.abs() * BigInt.two + d) ~/ (d * BigInt.two);
    return (n.isNegative ? -rounded : rounded).toDouble() /
        BigInt.from(10).pow(digits).toDouble();
  }

  /// Энергетическая ценность по формуле бланка: Б × 4 + Ж × 9 + У × 4
  /// с точным округлением до 0,1 ккал без ошибок IEEE 754
  static double energy(double p, double f, double c) {
    final cents =
        (p * 100).round() * 4 + (f * 100).round() * 9 + (c * 100).round() * 4;
    return ((cents + 5) ~/ 10) / 10.0;
  }

  /// Exact decimal ratio, avoiding a binary floating division before HALF-UP.
  static double ratioRounded(double value, double divisor, int digits,
      {double multiplier = 100}) {
    final (vn, vd) = decimal(value);
    final (dn, dd) = decimal(divisor);
    final (mn, md) = decimal(multiplier);
    if (dn <= BigInt.zero) throw ArgumentError.value(divisor, 'divisor');
    var n = vn * mn;
    var d = dn;
    final scale = dd - vd - md + digits;
    if (scale >= 0) {
      n *= BigInt.from(10).pow(scale);
    } else {
      d *= BigInt.from(10).pow(-scale);
    }
    final rounded = (n.abs() * BigInt.two + d) ~/ (d * BigInt.two);
    return (n.isNegative ? -rounded : rounded).toDouble() /
        BigInt.from(10).pow(digits).toDouble();
  }

  static double round1(double v) => productRounded(v, 1.0, 1);
  static double round2(double v) => productRounded(v, 1.0, 2);
}
