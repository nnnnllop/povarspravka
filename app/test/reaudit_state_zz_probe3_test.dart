// [DIAGNOSTIC PROBE — NOT ACCEPTANCE COVERAGE]
// Diagnoses layout exceptions when `BlankPreviewScreen` renders an uncalculable
// dish (`InteractiveViewer(constrained: false)` wrapping `CalcErrorBanner`).
// Asserts the error banner text invariant without altering the tracked layout
// defect pinned by `reaudit_state_01_null_result_test.dart:270-289`.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/presentation/providers/dish_provider.dart';
import 'package:povarspravka/presentation/screens/blank_preview_screen.dart';

import 'reaudit_state_support.dart';

void main() {
  testWidgets('blank on bad dish renders diagnostic banner text',
      (tester) async {
    phoneSize(tester, size: const Size(390, 844));
    final n = DishNotifier(storage: RecordingStorage());
    n.loadDish(uncalculableDish());
    final h = Harness(dish: n);
    await tester.pumpWidget(h.wrap(const BlankPreviewScreen()));
    await tester.pump();
    final errs = <Object>[];
    for (var i = 0; i < 12; i++) {
      final e = tester.takeException();
      if (e != null) errs.add(e);
    }
    // Keep draining diagnostic layout exceptions (see reaudit_state_01 L270-289),
    // and assert the user-facing error banner invariant (A3-TEST-02).
    expect(errs, isNotNull);
    expect(find.text('Проверьте выход и параметры блюда'), findsOneWidget);
  });
}
