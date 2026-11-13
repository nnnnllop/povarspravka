// STATE-08: rapid multi-field input on `CustomNumpadSheet`, and the
// 7-character cap of `_onKey` (`custom_numpad.dart:109`: `length < 7`).
//
// `_currentInput` is private, so every assertion goes through the visible
// readout and through the value handed to `onConfirm`.
//
// NOTE on the readout helper: in `build()` the KEYPAD is rebuilt from inside
// `_buildKeypad()`, i.e. it is the LAST child of the sheet, so
// `element.visitAncestorElements` (which goes up to the ROOT) would also pass
// through the readout's `AnimatedSwitcher`. The readout is therefore located
// by `find.ancestor(of: ..., matching: find.byType(AnimatedSwitcher))` with
// `matchRoot: true` instead.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/calculation_engine.dart';
import 'package:povarspravka/core/calculation/models/product.dart';
import 'package:povarspravka/core/theme/app_theme.dart';
import 'package:povarspravka/presentation/widgets/custom_numpad.dart';

Product potato() => const Product(
      id: 1,
      code: 'p',
      name: 'Картофель',
      groupId: 1,
      source: 'skurikhin',
      wastePct: 20,
      protein: 2,
      fat: .4,
      carbs: 16.3,
      kcal: 77,
    );

/// The number shown in `_buildReadout`.
String readout(WidgetTester tester) {
  final animated = find.byType(AnimatedSwitcher);
  expect(animated, findsOneWidget, reason: 'the readout AnimatedSwitcher');
  int depth(Element e) {
    var d = 0;
    e.visitAncestorElements((_) {
      d++;
      return true;
    });
    return d;
  }

  final candidates = find
      .descendant(of: animated, matching: find.byType(Text))
      .evaluate()
      .where((e) {
    final t = e.widget as Text;
    return t.data != null && RegExp(r'^[0-9]+(,[0-9]*)?$').hasMatch(t.data!);
  }).toList();
  expect(candidates, isNotEmpty, reason: 'no readout Text found');
  String dataOf(Element e) => (e.widget as Text).data!;
  if (candidates.length == 1) return dataOf(candidates.single);
  // Newest child = the one mounted LAST (the outgoing cross-fade child is
  // wrapped in the extra FadeTransition/SlideTransition pair added by
  // `transitionBuilder`, and appears FIRST in the child list).
  final depths = {for (final e in candidates) e: depth(e)};
  candidates.sort((a, b) {
    final byDepth = depths[a]!.compareTo(depths[b]!);
    if (byDepth != 0) return byDepth;
    return _mountOrder(a).compareTo(_mountOrder(b)) * -1;
  });
  return dataOf(candidates.first);
}

/// Monotonic counter of Element creation — approximates "which one is newer".
final Map<Element, int> _mountIds = Map.identity();
int _mountOrder(Element e) => _mountIds.putIfAbsent(e, () => _mountIds.length);

Future<void> _gestureUp(WidgetTester tester, Finder finder, int pointer) async {
  final g = await tester.startGesture(tester.getCenter(finder),
      pointer: pointer, kind: PointerDeviceKind.touch);
  await g.up();
}

Future<void> tapKey(WidgetTester tester, String k, {required int pointer}) async {
  final finder =
      k == '⌫' ? find.byKey(const ValueKey('key-⌫')) : find.byKey(ValueKey('key-$k'));
  expect(finder, findsOneWidget, reason: 'no key "$k"');
  await _gestureUp(tester, finder, pointer);
}

Future<void> pumpSheet(
  WidgetTester tester, {
  required void Function(double grams, bool isGross) onConfirm,
  double initialGrams = 0,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: SingleChildScrollView(
        child: CustomNumpadSheet(
          product: potato(),
          initialGrams: initialGrams,
          onConfirm: onConfirm,
        ),
      ),
    ),
  ));
  await tester.pump();
}

/// Long-press on ⌫ → `_onClear()` → readout `'0'`, `_isFreshInput == true`.
Future<void> clearToFresh(WidgetTester tester, {required int pointer}) async {
  final g = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('key-⌫'))),
      pointer: pointer,
      kind: PointerDeviceKind.touch);
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
  await g.up();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('STATE-08 rapid keypad input', () {
    testWidgets('30 rapid presses with pump(Duration.zero) between them are '
        'all applied in order', (tester) async {
      double? confirmed;
      await pumpSheet(tester, onConfirm: (g, _) => confirmed = g);
      expect(readout(tester), '100', reason: 'initialGrams == 0 → "100"');

      var pointer = 100;
      await clearToFresh(tester, pointer: pointer++);
      expect(readout(tester), '0');

      const sequence = <String>[
        // 1..9 then backspaces down to 1, then a decimal tail.
        '1', '2', '3', '4', '5', '6', '7', '8', '9', // 1..9   (9)
        // 7 characters are accepted (the cap), so exactly 6 backspaces
        // are needed to come back down to '1'.
        '⌫', '⌫', '⌫', '⌫', '⌫', '⌫', // → '1'      (6)
        '0', // 10                                   (1)
        ',', // 10,                                  (1)
        '7', // 10,7                                 (1)
        '⌫', // 10,                                  (1)
        '3', '⌫', // 10,3 then 10,                   (2)
        '5', '⌫', // 10,5 then 10,                   (2)
        '1', '⌫', // 10,1 then 10,                   (2)
        '9', '⌫', // 10,9 then 10,                   (2)
        '7', '⌫', // 10,7 then 10,                   (2)
        '0', // 10,0                                 (1)
      ];
      expect(sequence.length, 30, reason: 'exactly 30 presses');
      final states = <String>[];
      for (final k in sequence) {
        await tapKey(tester, k, pointer: pointer++);
        await tester.pump(Duration.zero);
        states.add(readout(tester));
      }
      // ignore: avoid_print
      print('STATE-08 states: $states');
      expect(states.last, '10,0');
      // Ink ripples from the taps are still settling; let them finish, then
      // assert nothing keeps scheduling frames (no leaked controllers).
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.transientCallbackCount, 0);

      await _gestureUp(tester, find.text('Добавить в блюдо'), pointer++);
      await tester.pump();
      // ignore: avoid_print
      print('STATE-08 confirmed = $confirmed after 30 presses');
      expect(confirmed, 10.0);
    });

    testWidgets('the 7-character cap allows 7 chars: "1234,56" fits, '
        '"1234,567" loses the last digit', (tester) async {
      double? confirmed;
      await pumpSheet(tester, onConfirm: (g, _) => confirmed = g);
      var pointer = 200;
      await clearToFresh(tester, pointer: pointer++);
      for (final k in ['1', '2', '3', '4', ',', '5', '6']) {
        await tapKey(tester, k, pointer: pointer++);
        await tester.pump();
      }
      expect(readout(tester), '1234,56',
          reason: '7 characters are accepted (length < 7 → 0..6 allowed)');
      // The 8th character is dropped without any feedback.
      await tapKey(tester, '7', pointer: pointer++);
      await tester.pump();
      final shown = readout(tester);
      // ignore: avoid_print
      print('STATE-08 "1234,56" + "7" -> readout "$shown"');
      expect(shown, '1234,56',
          reason: 'OBSERVED: the 8th character is dropped silently');
      await _gestureUp(tester, find.text('Добавить в блюдо'), pointer++);
      await tester.pump();
      expect(confirmed, 1234.56);
    });

    testWidgets('4-digit values with kopecks are fine, but "9999,99" cannot '
        'be typed (only 7 chars) and "1234,567" is silently cut to "1234,56"',
        (tester) async {
      await pumpSheet(tester, onConfirm: (_, __) {});
      var pointer = 250;
      await clearToFresh(tester, pointer: pointer++);
      for (final k in ['9', '9', '9', '9', ',', '9', '9']) {
        await tapKey(tester, k, pointer: pointer++);
        await tester.pump();
      }
      // ignore: avoid_print
      print('STATE-08 "9999,99" -> readout "${readout(tester)}"');
      expect(readout(tester), '9999,99',
          reason: '7 chars exactly — the limit is INCLUSIVE of the comma');
    });

    testWidgets('values ≥ 1000 g with two decimals fit only up to 4 integer '
        'digits: "12345,67" is cut to "12345,6"', (tester) async {
      await pumpSheet(tester, onConfirm: (_, __) {});
      var pointer = 280;
      await clearToFresh(tester, pointer: pointer++);
      for (final k in ['1', '2', '3', '4', '5', ',', '6', '7']) {
        await tapKey(tester, k, pointer: pointer++);
        await tester.pump();
      }
      // ignore: avoid_print
      print('STATE-08 "12345,67" -> readout "${readout(tester)}"');
      expect(readout(tester), '12345,6');
    });

    testWidgets('long integers are capped at 7 characters', (tester) async {
      await pumpSheet(tester, onConfirm: (_, __) {});
      var pointer = 400;
      await clearToFresh(tester, pointer: pointer++);
      for (var i = 0; i < 12; i++) {
        await tapKey(tester, '7', pointer: pointer++);
        await tester.pump(Duration.zero);
      }
      expect(readout(tester), '7777777');
    });

    testWidgets('two taps in the SAME frame both apply (no lost digit)',
        (tester) async {
      await pumpSheet(tester, onConfirm: (_, __) {});
      var pointer = 500;
      await clearToFresh(tester, pointer: pointer++);
      await tapKey(tester, '4', pointer: pointer++);
      await tapKey(tester, '5', pointer: pointer++);
      await tester.pump();
      expect(readout(tester), '45');
    });

    testWidgets('comma as the first character yields "0," and a second comma '
        'is ignored', (tester) async {
      await pumpSheet(tester, onConfirm: (_, __) {});
      var pointer = 600;
      await clearToFresh(tester, pointer: pointer++);
      await tapKey(tester, ',', pointer: pointer++);
      await tester.pump();
      expect(readout(tester), '0,');
      await tapKey(tester, ',', pointer: pointer++);
      await tester.pump();
      expect(readout(tester), '0,');
      await tapKey(tester, '7', pointer: pointer++);
      await tester.pump();
      expect(readout(tester), '0,7');
    });

    testWidgets('+10 / +50 / +100 / +250 in one frame accumulate correctly',
        (tester) async {
      double? confirmed;
      await pumpSheet(tester, onConfirm: (g, _) => confirmed = g);
      var pointer = 700;
      expect(readout(tester), '100');
      for (final label in ['+10 г', '+50 г', '+100 г', '+250 г']) {
        await _gestureUp(tester, find.text(label), pointer++);
        await tester.pump(Duration.zero);
      }
      expect(readout(tester), '510',
          reason: '+10+50+100+250 = 410 on top of the initial 100');
      await _gestureUp(tester, find.text('Добавить в блюдо'), pointer++);
      await tester.pump();
      expect(confirmed, 510.0);
    });

    testWidgets('onConfirm receives exactly the parsed double of the readout',
        (tester) async {
      double? confirmed;
      bool? gross;
      await pumpSheet(tester, onConfirm: (g, isG) {
        confirmed = g;
        gross = isG;
      });
      var pointer = 800;
      await clearToFresh(tester, pointer: pointer++);
      for (final k in ['2', '5', '0', ',', '5']) {
        await tapKey(tester, k, pointer: pointer++);
        await tester.pump(Duration.zero);
      }
      final shown = readout(tester);
      expect(shown, '250,5');
      await _gestureUp(tester, find.text('Добавить в блюдо'), pointer++);
      await tester.pump();
      expect(CalculationEngine.parseInputDouble(shown), confirmed);
      expect(confirmed, 250.5);
      expect(gross, isFalse);
    });
  });
}
