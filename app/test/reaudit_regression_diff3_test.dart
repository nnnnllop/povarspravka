// [DIAGNOSTIC PROBE — NOT ACCEPTANCE COVERAGE]
// DIFFERENTIAL / REGRESSION HARNESS — part 3: formatting helpers of
// CalculationEngine (formatGrams / formatPercent / parseInputDouble ...).
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/calculation_engine.dart';

import 'reaudit_regression_old_lib.dart';

// HEAD implementations (verbatim bodies from git show HEAD), expressed with
// the HEAD CalculationMath copy so they do not depend on the fixed one.
String oldFormatGrams(double value) {
  final rounded = OldMath.round1(value);
  if (rounded == rounded.roundToDouble()) return rounded.toInt().toString();
  return rounded.toStringAsFixed(1).replaceAll('.', ',');
}

String oldFormatMacro(double value) =>
    OldMath.round2(value).toStringAsFixed(2).replaceAll('.', ',');

String oldFormatKcal(double value) =>
    OldMath.round1(value).toStringAsFixed(1).replaceAll('.', ',');

double? oldParseInputDouble(String input) {
  final cleaned = input.trim().replaceAll(',', '.');
  if (cleaned.isEmpty) return null;
  final parsed = double.tryParse(cleaned);
  return parsed != null && parsed.isFinite ? parsed : null;
}

void main() {
  test('formatting helpers differential', () {
    print('\n=== [14] formatGrams ===');
    for (final v in <double>[
      0.0, 0.04, 0.05, 0.049, 0.0000001, 1e-7, 2.5, 2.55, 149.95, 150.0,
      1.5e21, 1e300, 99.949999, 99.95, 9999999.0, -0.4, -0.0000001, -2.54,
    ]) {
      String o, n;
      try {
        o = oldFormatGrams(v);
      } catch (e) {
        o = 'THROW ${e.runtimeType}';
      }
      n = CalculationEngine.formatGrams(v);
      print('  ${o == n ? "SAME" : "DIFF"}  formatGrams($v): old=$o new=$n');
    }
    print('\n=== [15] formatMacro / formatKcal with NaN/inf ===');
    for (final v in <double>[double.nan, double.infinity, 1.005, -1.004]) {
      String o, n2, o2;
      try {
        o = oldFormatMacro(v);
      } catch (e) {
        o = 'THROW ${e.runtimeType}';
      }
      try {
        o2 = oldFormatKcal(v);
      } catch (e) {
        o2 = 'THROW ${e.runtimeType}';
      }
      n2 = CalculationEngine.formatKcal(v);
      print('  formatMacro($v): old=$o new=${CalculationEngine.formatMacro(v)}');
      print('  formatKcal($v):  old=$o2 new=$n2');
    }
    print('\n=== [16] parseInputDouble ===');
    for (final s in <String>[
      '100', '100,5', ' 100 ', '1 000', '1\u00A0000', '1 0000', '-3', '+3',
      '1e3', '1e-7', '1,0,0', '', '   ', 'abc', '100.', '.5', '0',
    ]) {
      final o = oldParseInputDouble(s);
      final n = CalculationEngine.parseInputDouble(s);
      print('  ${o == n ? "SAME" : "DIFF"}  parse("${s.replaceAll('\u00A0', '<NBSP>')}"): '
          'old=$o new=$n');
    }
  });
}
