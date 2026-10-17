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

  /// HALF-UP over the decimal spelling of finite double inputs.
  /// Equivalent to Decimal(str(v)), not Decimal(v)'s exact binary expansion.
  static double productRounded(double a, double b, int digits,
      {bool divideBy100 = false}) {
    final (an, ad) = decimal(a);
    final (bn, bd) = decimal(b);
    if (a == 0.0 || b == 0.0) return 0.0;
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
    final terms = [decimal(p), decimal(f), decimal(c)];
    final scale = terms.map((t) => t.$2).reduce((a, b) => a > b ? a : b);
    final weights = [4, 9, 4];
    var numerator = BigInt.zero;
    for (var i = 0; i < terms.length; i++) {
      numerator += terms[i].$1 * BigInt.from(weights[i]) *
          BigInt.from(10).pow(scale - terms[i].$2);
    }
    return _rationalRounded(numerator, BigInt.one, scale, 1);
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

  // value = numerator / denominator * 10^-scale. Integer arithmetic until output.
  static double _rationalRounded(BigInt numerator, BigInt denominator,
      int scale, int digits) {
    final shift = digits - scale;
    if (shift >= 0) {
      numerator *= BigInt.from(10).pow(shift);
    } else {
      denominator *= BigInt.from(10).pow(-shift);
    }
    final units = (numerator.abs() * BigInt.two + denominator) ~/
        (denominator * BigInt.two);
    return (numerator.isNegative ? -units : units).toDouble() /
        BigInt.from(10).pow(digits).toDouble();
  }

  static (BigInt, int) _sum(Iterable<double> values) {
    var total = BigInt.zero;
    var scale = 0;
    for (final value in values) {
      final (n, s) = decimal(value);
      if (s > scale) {
        total *= BigInt.from(10).pow(s - scale);
        scale = s;
      }
      total += n * BigInt.from(10).pow(scale - s);
    }
    return (total, scale);
  }

  static double sumRounded(Iterable<double> values, int digits) {
    final (n, s) = _sum(values);
    return _rationalRounded(n, BigInt.one, s, digits);
  }

  static bool sumExceeds(Iterable<double> values, double limit) {
    final (n, s) = _sum([...values, -limit]);
    return n > BigInt.zero;
  }

  /// Exact decimal (100 - waste), with no floating subtraction or intermediate rounding.
  static double wasteAdjusted(double value, double waste, int digits,
      {bool inverse = false}) {
    final (vn, vs) = decimal(value);
    final (wn, ws) = decimal(waste);
    final scale = ws > 0 ? ws : 0;
    final hundred = BigInt.from(100) * BigInt.from(10).pow(scale);
    final remaining = hundred - wn * BigInt.from(10).pow(scale - ws);
    if (remaining < BigInt.zero || remaining > hundred) {
      throw ArgumentError.value(waste, 'waste');
    }
    if (inverse && remaining == BigInt.zero) {
      throw ArgumentError.value(waste, 'waste', 'No finite inverse');
    }
    return inverse
        ? _rationalRounded(vn * hundred, remaining, vs, digits)
        : _rationalRounded(vn * remaining, hundred, vs, digits);
  }

  static double round1(double v) => productRounded(v, 1.0, 1);
  static double round2(double v) => productRounded(v, 1.0, 2);
}
