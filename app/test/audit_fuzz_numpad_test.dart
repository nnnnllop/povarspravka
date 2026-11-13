// FUZZ-EDGE / PART 5 — CustomNumpadSheet decimal state machine driven by real taps.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/calculation_engine.dart';
import 'package:povarspravka/core/calculation/models/product.dart';
import 'package:povarspravka/presentation/widgets/custom_numpad.dart';

const product = Product(
  id: 1,
  code: 'p',
  name: 'Сахар',
  groupId: 1,
  source: 'skurikhin',
  protein: 0,
  fat: 0,
  carbs: 99.8,
  kcal: 399,
);

/// Opens the sheet and returns the tapped-value sink.
class Harness {
  final List<(double, bool)> confirmed = [];
  late WidgetTester tester;

  String get readout {
    // The readout Text carries ValueKey<String>(_currentInput)
    // (custom_numpad.dart:545). The keypad digits also carry ValueKey<String>
    // ('1'…'9', ','), so take the LONGEST keyed string.
    final keyed = tester
        .widgetList<Text>(find.byType(Text))
        .where((t) => t.key is ValueKey<String>)
        .map((t) => t.data)
        .whereType<String>()
        .toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    return keyed.isEmpty ? '<no readout>' : keyed.first;
  }

  bool get canConfirm {
    // The confirm key is the InkWell that owns the "Добавить в блюдо" label.
    final of = find.ancestor(
        of: find.text('Добавить в блюдо'), matching: find.byType(InkWell)).first;
    return tester.widget<InkWell>(of).onTap != null;
  }

  Future<void> tap(WidgetTester t, String k) async {
    tester = t;
    if (k == '⌫') {
      await t.tap(find.byKey(const ValueKey('key-⌫')));
    } else {
      await t.tap(find.byKey(ValueKey('key-$k')));
    }
    // The readout is an AnimatedSwitcher: the outgoing child stays mounted for
    // Motion.base (~200 ms), so a bare pump() leaves TWO keyed texts alive.
    await t.pumpAndSettle();
  }

  Future<void> tapSequence(WidgetTester t, List<String> keys) async {
    for (final k in keys) {
      await tap(t, k);
    }
  }

  Future<void> pressConfirm(WidgetTester t) async {
    await t.tap(find.text('Добавить в блюдо'));
    await t.pumpAndSettle();
  }
}

Future<Harness> open(WidgetTester tester,
    {double initialGrams = 100, double wastePct = 0, bool isGross = false}) async {
  // The default 800x600 test surface clips the sticky keypad; use a real phone.
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  final h = Harness()..tester = tester;
  final p = wastePct == 0 ? product : product.copyWith(wastePct: wastePct);
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => CustomNumpadSheet(
                product: p,
                initialGrams: initialGrams,
                initialIsGross: isGross,
                onConfirm: (g, gross) => h.confirmed.add((g, gross)),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return h;
}

void main() {
  testWidgets('0 , 5 -> "0,5" and confirms 0.5', (tester) async {
    final h = await open(tester);
    await h.tapSequence(tester, ['0', ',', '5']);
    expect(h.readout, '0,5');
    expect(h.canConfirm, isTrue);
    await h.pressConfirm(tester);
    expect(h.confirmed.single.$1, 0.5);
  });

  testWidgets('[RISK FUZZ-11] "," pressed FIRST gives "0," (confirmed as 0.0?)', (tester) async {
    final h = await open(tester);
    await h.tap(tester, ',');
    expect(h.readout, '0,');
    // "0," parses to 0.0 -> below the 0.1 gate -> Enter is DISABLED. Good.
    expect(CalculationEngine.parseInputDouble('0,'), 0.0);
    expect(h.canConfirm, isFalse);
    expect(find.text('Добавить в блюдо'), findsOneWidget);
    // Typing a digit completes the fraction.
    await h.tapSequence(tester, ['7']);
    expect(h.readout, '0,7');
    expect(h.canConfirm, isTrue);
  });

  testWidgets('double comma is impossible', (tester) async {
    final h = await open(tester);
    await h.tapSequence(tester, ['1', ',', ',', '5']);
    expect(h.readout, '1,5');
  });

  testWidgets('comma after a fresh digit replaces the default 100', (tester) async {
    final h = await open(tester);
    await h.tapSequence(tester, ['3', ',', '2', '5']);
    expect(h.readout, '3,25');
  });

  testWidgets('backspace to empty produces "0", never an empty string', (tester) async {
    final h = await open(tester);
    await h.tapSequence(tester, ['1', ',', '5']);
    await h.tap(tester, '⌫');
    await h.tap(tester, '⌫');
    expect(h.readout, '1');
    await h.tap(tester, '⌫');
    expect(h.readout, '0');
    await h.tap(tester, '⌫');
    expect(h.readout, '0'); // stays "0", never ""
    expect(h.canConfirm, isFalse);
  });

  testWidgets('backspace after a fresh "0," leaves "0," -> still "0"', (tester) async {
    final h = await open(tester);
    await h.tap(tester, ',');
    expect(h.readout, '0,');
    await h.tap(tester, '⌫');
    expect(h.readout, '0');
  });

  testWidgets('7-char cap: "1234,56" fits exactly', (tester) async {
    final h = await open(tester);
    await h.tapSequence(tester, ['1', '2', '3', '4', ',', '5', '6']);
    expect(h.readout, '1234,56');
    await h.pressConfirm(tester);
    expect(h.confirmed.single.$1, 1234.56);
  });

  testWidgets('[RISK FUZZ-11b] 8th keystroke is DROPPED silently on short values', (tester) async {
    final h = await open(tester);
    // "1,5" is only 3 chars but still cannot accept a 4th (cap is on length 7,
    // so this one is fine)…
    await h.tapSequence(tester, ['1', ',', '5']);
    await h.tap(tester, '0');
    expect(h.readout, '1,50');
    // …but after 7 chars the keyboard goes dead with no feedback at all.
    await h.tapSequence(tester, ['0', '0', '0']);
    expect(h.readout, '1,50000');
    await h.tap(tester, '9');
    expect(h.readout, '1,50000');
    // The user sees a live decimal that silently ignores input.
    expect(h.readout.length, 7);
  });

  testWidgets('[RISK FUZZ-11c] "1234567" (7 digits) blocks the comma forever', (tester) async {
    final h = await open(tester);
    await h.tapSequence(tester, ['1', '2', '3', '4', '5', '6', '7']);
    expect(h.readout, '1234567');
    await h.tap(tester, ',');
    // Comma path has no length guard, so "1234567," is 8 chars and parsable.
    expect(h.readout, '1234567,');
    await h.tap(tester, '5');
    // …but the digit path refuses at 8 chars: the fraction can never be typed.
    expect(h.readout, '1234567,');
    expect(CalculationEngine.parseInputDouble(h.readout), 1234567.0);
  });

  testWidgets('[RISK FUZZ-11d] initialGrams with many decimals overflows the cap on open', (tester) async {
    // Re-opening an existing row seeds the field from toString(), bypassing the
    // 7-char cap entirely.
    final h = await open(tester, initialGrams: 123.456789);
    expect(h.readout, '123,456789');
    expect(h.readout.length, greaterThan(7));
  });

  testWidgets('[DEFECT FUZZ-11] "12345,6" + "7" is SILENTLY dropped: 7-char cap blocks 12345,67 g', (tester) async {
    final h = await open(tester);
    await h.tapSequence(tester, ['1', '2', '3', '4', '5', ',', '6']);
    expect(h.readout, '12345,6'); // 7 chars
    expect(h.canConfirm, isTrue);
    // The 8th keystroke does nothing at all — no haptic error, no snackbar,
    // no readout change. `_onKey` simply falls through the `length < 7` guard.
    await h.tap(tester, '7');
    expect(h.readout, '12345,6');
    expect(find.byType(SnackBar), findsNothing);
    // The value that was asked for (12 345,67 g) is unreachable…
    expect(CalculationEngine.parseInputDouble('12345,67'), 12345.67);
    // …while the validator happily accepts up to 9 999 999 g.
    await h.pressConfirm(tester);
    expect(h.confirmed.single.$1, 12345.6); // what the chef got
    expect(h.confirmed.single.$1, isNot(12345.67)); // what the chef typed
  });

  testWidgets('quick-add clamps to [1, 99999] and never produces garbage', (tester) async {
    final h = await open(tester, initialGrams: 99999);
    await tester.tap(find.text('+250 г'));
    await tester.pumpAndSettle();
    expect(h.readout, '99999'); // formatGrams drops the ",0"
    await tester.tap(find.text('+10 г'));
    await tester.pumpAndSettle();
    expect(h.readout, '99999');
    await h.pressConfirm(tester);
    expect(h.confirmed.single.$1, 99999.0);
  });

  testWidgets('quick-add on "0" adds the delta (0 + 10)', (tester) async {
    final h = await open(tester, initialGrams: 0);
    expect(h.readout, '100'); // default when initialGrams == 0
    await h.tap(tester, '⌫'); // 100 -> 10
    await h.tap(tester, '⌫'); // 10 -> 1
    await h.tap(tester, '⌫'); // 1 -> 0
    expect(h.readout, '0');
    await tester.tap(find.text('+10 г'));
    await tester.pumpAndSettle();
    expect(h.readout, '10');
  });

  testWidgets('gross mode with 99.9% waste confirms the gross value', (tester) async {
    final h = await open(tester, initialGrams: 100, wastePct: 99.9, isGross: true);
    expect(h.readout, '100,0');
    await h.pressConfirm(tester);
    expect(h.confirmed.single.$1, 100.0);
    expect(h.confirmed.single.$2, isTrue);
  });

  testWidgets('[OK] the seeded "100,0" is replaced by the first digit tap (fresh-input flag)', (tester) async {
    final h = await open(tester, initialGrams: 100);
    expect(h.readout, '100,0');
    // _isFreshInput == true on open, so one tap yields a clean "1".
    await h.tap(tester, '1');
    expect(h.readout, '1');
    await h.tapSequence(tester, ['5', '0']);
    expect(h.readout, '150');
  });
}
