import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/heat_process.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/product.dart';
import 'package:povarspravka/core/theme/app_space.dart';
import 'package:povarspravka/core/theme/app_theme.dart';
import 'package:povarspravka/data/repositories/dish_storage_repository.dart';
import 'package:povarspravka/presentation/providers/dish_provider.dart';
import 'package:povarspravka/presentation/providers/search_provider.dart';
import 'package:povarspravka/presentation/screens/blank_preview_screen.dart';
import 'package:povarspravka/presentation/screens/home_screen.dart';
import 'package:povarspravka/presentation/screens/recipe_editor_screen.dart';
import 'package:povarspravka/presentation/screens/search_product_modal.dart';
import 'package:povarspravka/presentation/widgets/app_buttons.dart';
import 'package:povarspravka/presentation/widgets/custom_numpad.dart';

import 'reaudit_state_support.dart';

const List<(String, Size)> _viewports = [
  ('320x568', Size(320, 568)),
  ('320x640', Size(320, 640)),
  ('360x780', Size(360, 780)),
  ('390x844', Size(390, 844)),
  ('412x915', Size(412, 915)),
  ('640x320', Size(640, 320)),
  ('800x600', Size(800, 600)),
];

final List<(String, ThemeData)> _themes = [
  ('light', AppTheme.light),
  ('dark', AppTheme.dark),
];

const List<double> _textScales = [1.0, 1.3, 1.5, 2.0];

const Product _potatoWithMeasures = Product(
  id: 9103,
  code: 'p-meas',
  name: 'Картофель',
  groupId: 5,
  source: 'skurikhin',
  wastePct: 25,
  protein: 2,
  fat: 0.4,
  carbs: 16.1,
  kcal: 77,
  measures: [
    ProductMeasure(id: 1, productId: 9103, name: '1 шт. средн.', grams: 110),
    ProductMeasure(id: 2, productId: 9103, name: '1 стакан кубиков', grams: 150),
  ],
);

Dish _samplePopulatedDish() {
  return Dish(
    id: 'v11-dish-1',
    title: 'Борщ овощной с картофелем и свеклой',
    process: HeatProcess.boil,
    ingredients: const [
      Ingredient(
        id: 'ing-1',
        product: _potatoWithMeasures,
        weightGrams: 300,
        isGross: true,
      ),
      Ingredient(id: 'ing-2', product: beet, weightGrams: 200),
      Ingredient(id: 'ing-3', product: buckwheat, weightGrams: 120),
    ],
    customYieldGrams: 540,
    retentionProtein: 0.94,
    retentionFat: 0.88,
    retentionCarbs: 0.91,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );
}

void _setViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
}

Widget _buildScopedApp({
  required ThemeData theme,
  required double textScale,
  required Widget home,
  Dish? activeDraft,
  List<Dish> savedDishes = const [],
  FakeProductRepo? repo,
}) {
  final storage = RecordingStorage(
    initial: DishStorageData(
      activeDraft: activeDraft,
      savedDishes: savedDishes,
    ),
  );
  final productRepo = repo ??
      FakeProductRepo(results: const [_potatoWithMeasures, beet, butter]);

  return ProviderScope(
    key: UniqueKey(),
    overrides: [
      dishStorageRepositoryProvider.overrideWithValue(storage),
      productRepositoryProvider.overrideWithValue(productRepo),
      searchProvider.overrideWith((ref) => SearchNotifier(productRepo)),
      sourceCountsProvider.overrideWith((ref) async => const SourceCounts()),
      productNutrientsProvider.overrideWith((ref, id) async => const []),
    ],
    child: MaterialApp(
      theme: theme,
      locale: const Locale('ru', 'RU'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ru', 'RU'), Locale('en', 'US')],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: home,
    ),
  );
}

Future<void> _collect(
  List<String> failures,
  String tag,
  Future<void> Function() body,
) async {
  try {
    await body();
  } on TestFailure catch (e) {
    final msg = (e.message ?? e.toString())
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .take(4)
        .join(' | ');
    failures.add('[$tag] $msg');
  } catch (e) {
    failures.add('[$tag] $e');
  }
}

Future<void> _pumpAndCaptureErrors(
  WidgetTester tester,
  Widget root,
  String tag, {
  Future<void> Function()? afterPump,
}) async {
  final errors = <FlutterErrorDetails>[];
  final oldOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    errors.add(details);
  };
  try {
    await tester.pumpWidget(root);
    await tester.pumpAndSettle();
    if (afterPump != null) {
      await afterPump();
      await tester.pumpAndSettle();
    }
  } finally {
    FlutterError.onError = oldOnError;
  }
  expect(
    errors,
    isEmpty,
    reason: 'FlutterError on $tag: '
        '${errors.map((e) {
          final lines = e.summary
              .toDescription()
              .split('\n')
              .map((l) => l.trim())
              .where((l) => l.isNotEmpty)
              .toList();
          final overflowOrAssert = e
              .exceptionAsString()
              .split('\n')
              .map((l) => l.trim())
              .where((l) =>
                  l.isNotEmpty &&
                  !l.startsWith('══') &&
                  !l.startsWith('The following') &&
                  !l.startsWith('FlutterErrorDetails'))
              .take(3)
              .join(' | ');
          return overflowOrAssert.isNotEmpty
              ? overflowOrAssert
              : lines.take(2).join(' | ');
        }).join(' ; ')}',
  );
}

bool _isAncestor(Element ancestor, Element descendant) {
  var hit = false;
  descendant.visitAncestorElements((parent) {
    if (identical(parent, ancestor)) {
      hit = true;
      return false;
    }
    return true;
  });
  return hit;
}

bool _rectsIntersect(Rect a, Rect b, {double tol = 0.5}) {
  final overlap = a.intersect(b);
  return overlap.width > tol && overlap.height > tol;
}

Rect? _globalRect(Element el) {
  final ro = el.renderObject;
  if (ro is! RenderBox || !ro.hasSize) return null;
  if (ro.size.width <= 0 || ro.size.height <= 0) return null;
  return ro.localToGlobal(Offset.zero) & ro.size;
}

List<Element> _collectInteractiveElements(
  WidgetTester tester, {
  Finder? scope,
}) {
  final seen = <Element>[];
  final types = <Type>[
    FilledButton,
    OutlinedButton,
    ElevatedButton,
    TextButton,
    IconButton,
    PopupMenuButton<String>,
    SegmentedButton<bool>,
    SegmentedButton<bool?>,
    SegmentedButton<String?>,
  ];

  void addFinder(Finder base) {
    final f = scope == null
        ? base
        : find.descendant(of: scope, matching: base);
    for (final el in f.evaluate()) {
      if (!seen.any((other) => identical(other, el))) {
        seen.add(el);
      }
    }
  }

  for (final t in types) {
    addFinder(find.byType(t));
  }
  addFinder(find.byWidgetPredicate((w) {
    final key = w.key;
    if (key is! ValueKey<String>) return false;
    return key.value.startsWith('key-') ||
        key.value == 'heat-process-row' ||
        key.value == 'yield-explanation' ||
        key.value.startsWith('loss-');
  }));

  // Убираем вложенные элементы (например, TextButton внутри другого контрола),
  // оставляя внешние интерактивные границы, а затем убираем пустые/скрытые.
  final deduped = <Element>[];
  for (final el in seen) {
    final hasParentInSeen =
        seen.any((other) => !identical(other, el) && _isAncestor(other, el));
    if (!hasParentInSeen && _globalRect(el) != null) {
      deduped.add(el);
    }
  }
  return deduped;
}

(Rect, bool) _visibleRectInScrollables(Element el, Rect raw) {
  var clipped = raw;
  var insideScrollable = false;
  el.visitAncestorElements((parent) {
    if (parent.widget is Scrollable) {
      insideScrollable = true;
      final ro = parent.renderObject;
      if (ro is RenderBox && ro.hasSize) {
        final sRect = ro.localToGlobal(Offset.zero) & ro.size;
        clipped = clipped.intersect(sRect);
      }
    }
    return true;
  });
  return (clipped, insideScrollable);
}

Finder _buttonWithText<T extends Widget>(String text) => find.ancestor(
      of: find.text(text),
      matching: find.byWidgetPredicate((w) => w is T),
    );

Finder _iconButtonFor(IconData icon) => find.ancestor(
      of: find.byIcon(icon),
      matching: find.byWidgetPredicate((w) => w is IconButton),
    );

void _assertInteractiveControls(
  WidgetTester tester,
  Size viewport,
  String tag, {
  Finder? scope,
  bool enforceFullViewportBounds = false,
}) {
  final controls = _collectInteractiveElements(tester, scope: scope);
  final visible = <(Element, Rect)>[];
  final viewportRect = Offset.zero & viewport;

  for (final el in controls) {
    final rect = _globalRect(el);
    if (rect == null) continue;
    // Размер интерактивной зоны обязан быть >= 48 dp.
    expect(
      rect.height,
      greaterThanOrEqualTo(kMinTapTarget - 0.5),
      reason: '[$tag] ${el.widget.runtimeType} height ${rect.height} < 48 dp',
    );
    if (el.widget is! InkWell ||
        (el.widget.key is ValueKey<String> &&
            (el.widget.key as ValueKey<String>).value.startsWith('key-'))) {
      expect(
        rect.width,
        greaterThanOrEqualTo(kMinTapTarget - 0.5),
        reason: '[$tag] ${el.widget.runtimeType} width ${rect.width} < 48 dp',
      );
    }
    expect(
      rect.left,
      greaterThanOrEqualTo(-0.5),
      reason: '[$tag] ${el.widget.runtimeType} clipped on left: $rect',
    );
    expect(
      rect.right,
      lessThanOrEqualTo(viewport.width + 0.5),
      reason: '[$tag] ${el.widget.runtimeType} overflows right of $viewport: $rect',
    );

    final (scrollClipped, insideScrollable) = _visibleRectInScrollables(el, rect);
    if (enforceFullViewportBounds && !insideScrollable) {
      expect(
        rect.top,
        greaterThanOrEqualTo(-0.5),
        reason: '[$tag] ${el.widget.runtimeType} clipped on top: $rect',
      );
      expect(
        rect.bottom,
        lessThanOrEqualTo(viewport.height + 0.5),
        reason:
            '[$tag] ${el.widget.runtimeType} overflows bottom of $viewport: $rect',
      );
    }
    final painted = scrollClipped.intersect(viewportRect);
    if (painted.width > 1.0 && painted.height > 1.0) {
      visible.add((el, painted));
    }
  }

  for (var i = 0; i < visible.length; i++) {
    for (var j = i + 1; j < visible.length; j++) {
      final (elA, rectA) = visible[i];
      final (elB, rectB) = visible[j];
      if (_isAncestor(elA, elB) || _isAncestor(elB, elA)) continue;
      expect(
        _rectsIntersect(rectA, rectB),
        isFalse,
        reason: '[$tag] interactive overlap between '
            '${elA.widget.runtimeType}($rectA) and '
            '${elB.widget.runtimeType}($rectB)',
      );
    }
  }
}

void _assertRegionBoundsAndNoOverlap(
  WidgetTester tester,
  Size viewport,
  Finder region,
  String tag, {
  bool checkVerticalViewport = true,
}) {
  final regionMatches = region.evaluate().toList();
  expect(regionMatches, isNotEmpty, reason: '[$tag] missing region $region');
  final regionRect = _globalRect(regionMatches.first)!;
  expect(regionRect.left, greaterThanOrEqualTo(-0.5), reason: '[$tag] left $regionRect');
  expect(
    regionRect.right,
    lessThanOrEqualTo(viewport.width + 0.5),
    reason: '[$tag] right $regionRect vs ${viewport.width}',
  );
  if (checkVerticalViewport) {
    expect(regionRect.top, greaterThanOrEqualTo(-0.5), reason: '[$tag] top $regionRect');
    expect(
      regionRect.bottom,
      lessThanOrEqualTo(viewport.height + 0.5),
      reason: '[$tag] bottom $regionRect vs ${viewport.height}',
    );
  }

  // Текстовые узлы внутри региона не должны перекрывать друг друга или вылезать
  // за горизонтальные границы региона.
  final texts = find
      .descendant(of: region, matching: find.byType(Text))
      .evaluate()
      .toList();
  final rects = <(Element, Rect)>[];
  for (final el in texts) {
    final rect = _globalRect(el);
    if (rect == null) continue;
    expect(
      rect.left,
      greaterThanOrEqualTo(regionRect.left - 1.0),
      reason: '[$tag] text ${(el.widget as Text).data} escaped left $rect vs $regionRect',
    );
    expect(
      rect.right,
      lessThanOrEqualTo(regionRect.right + 1.0),
      reason: '[$tag] text ${(el.widget as Text).data} escaped right $rect vs $regionRect',
    );
    rects.add((el, rect));
  }
  for (var i = 0; i < rects.length; i++) {
    for (var j = i + 1; j < rects.length; j++) {
      final (elA, rectA) = rects[i];
      final (elB, rectB) = rects[j];
      if (_isAncestor(elA, elB) || _isAncestor(elB, elA)) continue;
      expect(
        _rectsIntersect(rectA, rectB),
        isFalse,
        reason: '[$tag] text overlap between '
            '"${(elA.widget as Text).data}"($rectA) and '
            '"${(elB.widget as Text).data}"($rectB)',
      );
    }
  }
}

void _assertButtonPairConsistent(
  WidgetTester tester,
  Finder a,
  Finder b,
  String tag,
) {
  final boxA = _globalRect(a.evaluate().single)!;
  final boxB = _globalRect(b.evaluate().single)!;
  expect(boxA.height, greaterThanOrEqualTo(kMinTapTarget - 0.5), reason: tag);
  expect(boxB.height, greaterThanOrEqualTo(kMinTapTarget - 0.5), reason: tag);
  // Если кнопки стоят рядом в одной строке, их высота должна быть одинаковой.
  if ((boxA.top - boxB.top).abs() <= 4.0 ||
      (boxA.center.dy - boxB.center.dy).abs() <= 4.0) {
    expect(
      (boxA.height - boxB.height).abs(),
      lessThanOrEqualTo(1.0),
      reason: '[$tag] paired buttons on same row differ in height: '
          '${boxA.height} vs ${boxB.height}',
    );
  }
}

void _assertSingleLineAppBar(WidgetTester tester, Size viewport, String tag) {
  final barFinder = find.byType(AppBar);
  expect(barFinder, findsOneWidget, reason: '[$tag] expected AppBar');
  final barWidget = tester.widget<AppBar>(barFinder);
  expect(barWidget.bottom, isNull, reason: '[$tag] AppBar must be single-line');
  final barRect = _globalRect(barFinder.evaluate().single)!;
  expect(
    barRect.height,
    lessThanOrEqualTo(kToolbarHeight + 1.0),
    reason: '[$tag] AppBar height ${barRect.height} exceeded kToolbarHeight',
  );
  _assertRegionBoundsAndNoOverlap(tester, viewport, barFinder, '$tag/AppBar');
}

void _assertNoMastersUi(WidgetTester tester, String tag) {
  final forbiddenIcons = [
    Icons.auto_stories_outlined,
    Icons.auto_stories,
  ];
  for (final icon in forbiddenIcons) {
    expect(
      find.byIcon(icon),
      findsNothing,
      reason: '[$tag] forbidden masters icon $icon still present in UI',
    );
  }
  final forbiddenWords = ['мастеров', 'мастер-рецеп', 'рецептуры мастеров'];
  for (final w in tester.allWidgets) {
    String? s;
    if (w is Text) {
      s = w.data ?? w.textSpan?.toPlainText();
    } else if (w is RichText) {
      s = w.text.toPlainText();
    } else if (w is Tooltip) {
      s = w.message;
    } else if (w is Semantics) {
      s = w.properties.label;
    }
    if (s == null) continue;
    final lower = s.toLowerCase();
    for (final needle in forbiddenWords) {
      expect(
        lower.contains(needle),
        isFalse,
        reason: '[$tag] forbidden masters text "$needle" found in "$s"',
      );
    }
  }
}

void _assertNumpadStrictLayout(
  WidgetTester tester,
  Size viewport,
  String tag,
) {
  final sheetScope = find.byType(CustomNumpadSheet);
  expect(sheetScope, findsOneWidget, reason: tag);

  // Ни одна прокручиваемая область внутри шита (включая шапку/выбор брутто-нетто)
  // не должна схлопываться в нулевую высоту на компактном landscape-экране.
  for (final sEl in find
      .descendant(of: sheetScope, matching: find.byType(Scrollable))
      .evaluate()) {
    final ro = sEl.renderObject;
    expect(ro, isA<RenderBox>(), reason: tag);
    final box = ro! as RenderBox;
    expect(box.hasSize, isTrue, reason: tag);
    expect(
      box.size.height,
      greaterThanOrEqualTo(kMinTapTarget),
      reason: '[$tag] Scrollable collapsed vertically: ${box.size}',
    );
    expect(
      box.size.width,
      greaterThanOrEqualTo(kMinTapTarget),
      reason: '[$tag] Scrollable collapsed horizontally: ${box.size}',
    );
  }

  _assertInteractiveControls(
    tester,
    viewport,
    tag,
    scope: sheetScope,
    enforceFullViewportBounds: true,
  );

  // Все 12 клавиш кейпада >= 48 dp по ширине и высоте и одинаковой высоты.
  const keys = [
    '1', '2', '3',
    '4', '5', '6',
    '7', '8', '9',
    '⌫', '0', ',',
  ];
  final keyRects = <Rect>[];
  for (final k in keys) {
    final kf = find.descendant(
      of: sheetScope,
      matching: find.byKey(ValueKey('key-$k')),
    );
    expect(kf, findsOneWidget, reason: '[$tag] missing key-$k');
    final rect = _globalRect(kf.evaluate().single)!;
    expect(rect.height, greaterThanOrEqualTo(kMinTapTarget - 0.5),
        reason: '[$tag] key-$k height ${rect.height}');
    expect(rect.width, greaterThanOrEqualTo(kMinTapTarget - 0.5),
        reason: '[$tag] key-$k width ${rect.width}');
    keyRects.add(rect);
  }
  final heights = keyRects.map((r) => r.height).toList();
  final maxKeyH = heights.reduce((a, b) => a > b ? a : b);
  final minKeyH = heights.reduce((a, b) => a < b ? a : b);
  expect(maxKeyH - minKeyH, lessThanOrEqualTo(1.0),
      reason: '[$tag] keypad key heights vary: $minKeyH..$maxKeyH');

  // Быстрые прибавки +10..+250 >= 48 dp и на одной линии.
  const chips = ['+10 г', '+50 г', '+100 г', '+250 г'];
  final chipRects = <Rect>[];
  for (final label in chips) {
    final chipInk = find.descendant(
      of: sheetScope,
      matching: find.ancestor(
        of: find.text(label),
        matching: find.byType(InkWell),
      ),
    );
    expect(chipInk, findsOneWidget, reason: '[$tag] missing chip $label');
    final rect = _globalRect(chipInk.evaluate().single)!;
    expect(rect.height, greaterThanOrEqualTo(kMinTapTarget - 0.5),
        reason: '[$tag] chip $label height ${rect.height}');
    expect(rect.width, greaterThanOrEqualTo(kMinTapTarget - 0.5),
        reason: '[$tag] chip $label width ${rect.width}');
    chipRects.add(rect);
  }
  final chipHeights = chipRects.map((r) => r.height).toList();
  expect(
    chipHeights.reduce((a, b) => a > b ? a : b) -
        chipHeights.reduce((a, b) => a < b ? a : b),
    lessThanOrEqualTo(1.0),
    reason: '[$tag] quick chip heights differ',
  );
  for (var i = 0; i < chipRects.length; i++) {
    for (var j = i + 1; j < chipRects.length; j++) {
      expect(
        _rectsIntersect(chipRects[i], chipRects[j]),
        isFalse,
        reason: '[$tag] quick chips overlap: ${chipRects[i]} vs ${chipRects[j]}',
      );
    }
  }

  // Кнопка подтверждения >= 48 dp и не наезжает ни на одну цифровую клавишу/чипс.
  final confirmInk = find.descendant(
    of: sheetScope,
    matching: find.ancestor(
      of: find.text('Добавить в блюдо'),
      matching: find.byType(InkWell),
    ),
  );
  expect(confirmInk, findsOneWidget, reason: '[$tag] missing confirm InkWell');
  final confirmRect = _globalRect(confirmInk.evaluate().single)!;
  expect(confirmRect.height, greaterThanOrEqualTo(kMinTapTarget - 0.5),
      reason: '[$tag] confirm height ${confirmRect.height}');
  expect(confirmRect.right, lessThanOrEqualTo(viewport.width + 0.5),
      reason: '[$tag] confirm overflows right');
  expect(confirmRect.bottom, lessThanOrEqualTo(viewport.height + 0.5),
      reason: '[$tag] confirm overflows bottom');
  for (final kr in keyRects) {
    expect(_rectsIntersect(confirmRect, kr), isFalse,
        reason: '[$tag] confirm overlaps keypad key');
  }
  for (final cr in chipRects) {
    expect(_rectsIntersect(confirmRect, cr), isFalse,
        reason: '[$tag] confirm overlaps quick chip');
  }
}

void main() {
  testWidgets('HomeScreen: responsive, zero masters UI, consistent dock buttons',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final failures = <String>[];

    for (final (vpName, vpSize) in _viewports) {
      for (final (themeName, theme) in _themes) {
        for (final scale in _textScales) {
          // Сценарий A: пустой черновик (скрытая карточка, нет дубля «Новый расчёт»).
          final emptyTag = 'Home(empty)/$vpName/$themeName/x$scale';
          await _collect(failures, emptyTag, () async {
            _setViewport(tester, vpSize);
            await _pumpAndCaptureErrors(
              tester,
              _buildScopedApp(
                theme: theme,
                textScale: scale,
                home: const HomeScreen(),
              ),
              emptyTag,
            );
            _assertNoMastersUi(tester, emptyTag);
            _assertSingleLineAppBar(tester, vpSize, emptyTag);
            expect(find.text('Новый расчёт'), findsOneWidget,
                reason:
                    '[$emptyTag] active draft card must stay hidden when empty');
            _assertInteractiveControls(tester, vpSize, emptyTag);
            _assertRegionBoundsAndNoOverlap(
              tester,
              vpSize,
              find.byType(AppBottomBar),
              '$emptyTag/BottomBar',
            );
            _assertButtonPairConsistent(
              tester,
              _buttonWithText<FilledButton>('Новый расчёт'),
              _buttonWithText<OutlinedButton>('Справочник'),
              emptyTag,
            );
          });

          // Сценарий B: активный черновик + сохранённые блюда.
          final draft = _samplePopulatedDish();
          final saved = [
            healthyDish(id: 's1', title: 'Свекла отварная для салата'),
            dishWith(
              const [Ingredient(id: 's2-i', product: potato, weightGrams: 180)],
              id: 's2',
              title: 'Картофель отварной очищенный',
            ),
          ];
          final fullTag = 'Home(full)/$vpName/$themeName/x$scale';
          await _collect(failures, fullTag, () async {
            _setViewport(tester, vpSize);
            await _pumpAndCaptureErrors(
              tester,
              _buildScopedApp(
                theme: theme,
                textScale: scale,
                home: const HomeScreen(),
                activeDraft: draft,
                savedDishes: saved,
              ),
              fullTag,
            );
            _assertNoMastersUi(tester, fullTag);
            _assertSingleLineAppBar(tester, vpSize, fullTag);
            expect(find.text('Продолжить расчёт'), findsOneWidget,
                reason: '[$fullTag] non-empty draft card must be shown');
            _assertInteractiveControls(tester, vpSize, fullTag);
            _assertRegionBoundsAndNoOverlap(
              tester,
              vpSize,
              find.byType(AppBottomBar),
              '$fullTag/BottomBar',
            );
            _assertButtonPairConsistent(
              tester,
              _buttonWithText<FilledButton>('Новый расчёт'),
              _buttonWithText<OutlinedButton>('Справочник'),
              fullTag,
            );
          });
        }
      }
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  testWidgets(
      'RecipeEditorScreen: single-line AppBar, zero FAB/masters, adaptive dock',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final failures = <String>[];

    for (final (vpName, vpSize) in _viewports) {
      for (final (themeName, theme) in _themes) {
        for (final scale in _textScales) {
          // Пустой рецепт: проверяем отсутствие мастеров и чистое состояние.
          final emptyTag = 'Editor(empty)/$vpName/$themeName/x$scale';
          await _collect(failures, emptyTag, () async {
            _setViewport(tester, vpSize);
            await _pumpAndCaptureErrors(
              tester,
              _buildScopedApp(
                theme: theme,
                textScale: scale,
                home: const RecipeEditorScreen(),
                activeDraft: Dish.withProcess(
                    id: 'empty-ed', process: HeatProcess.boil),
              ),
              emptyTag,
            );
            _assertNoMastersUi(tester, emptyTag);
            _assertSingleLineAppBar(tester, vpSize, emptyTag);
            expect(find.byType(FloatingActionButton), findsNothing,
                reason: '[$emptyTag] FAB removed in v1.1');
            expect(find.text('Рецепт пока пуст', skipOffstage: false),
                findsOneWidget,
                reason: emptyTag);
            final editorScroll =
                find.byType(Scrollable).evaluate().first.renderObject
                    as RenderBox;
            expect(
              editorScroll.size.height,
              greaterThanOrEqualTo(kMinTapTarget),
              reason:
                  '[$emptyTag] Editor Scrollable collapsed: ${editorScroll.size}',
            );
            _assertInteractiveControls(tester, vpSize, emptyTag);
            _assertRegionBoundsAndNoOverlap(
              tester,
              vpSize,
              find.byType(AppBottomBar),
              '$emptyTag/BottomBar',
            );
            _assertButtonPairConsistent(
              tester,
              _buttonWithText<OutlinedButton>('Бланк'),
              _buttonWithText<FilledButton>('Добавить продукт'),
              emptyTag,
            );
          });

          // Наполненный рецепт: несколько ингредиентов + выход + итоги.
          final fullTag = 'Editor(full)/$vpName/$themeName/x$scale';
          await _collect(failures, fullTag, () async {
            _setViewport(tester, vpSize);
            await _pumpAndCaptureErrors(
              tester,
              _buildScopedApp(
                theme: theme,
                textScale: scale,
                home: const RecipeEditorScreen(),
                activeDraft: _samplePopulatedDish(),
              ),
              fullTag,
            );
            _assertNoMastersUi(tester, fullTag);
            _assertSingleLineAppBar(tester, vpSize, fullTag);
            expect(find.byType(FloatingActionButton), findsNothing,
                reason: fullTag);
            _assertInteractiveControls(tester, vpSize, fullTag);
            _assertRegionBoundsAndNoOverlap(
              tester,
              vpSize,
              find.byType(AppBottomBar),
              '$fullTag/BottomBar',
            );
            _assertButtonPairConsistent(
              tester,
              _buttonWithText<OutlinedButton>('Бланк'),
              _buttonWithText<FilledButton>('Добавить продукт'),
              fullTag,
            );
          });
        }
      }
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  testWidgets('SearchProductModal & ProductInfoCardSheet: zero overflow across matrix',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final failures = <String>[];

    for (final (vpName, vpSize) in _viewports) {
      for (final (themeName, theme) in _themes) {
        for (final scale in _textScales) {
          // 1. Модальный лист каталога (3 сегмента: Продукты | Готовые блюда | Все)
          // через реальный showModalBottomSheet.
          final modalTag = 'SearchModal/$vpName/$themeName/x$scale';
          await _collect(failures, modalTag, () async {
            _setViewport(tester, vpSize);
            await _pumpAndCaptureErrors(
              tester,
              _buildScopedApp(
                theme: theme,
                textScale: scale,
                home: Builder(
                  builder: (ctx) => Scaffold(
                    body: Center(
                      child: FilledButton(
                        onPressed: () => SearchProductModal.show(
                          ctx,
                          mode: SearchMode.browseCatalog,
                        ),
                        child: const Text('Открыть поиск'),
                      ),
                    ),
                  ),
                ),
              ),
              modalTag,
              afterPump: () async {
                await tester.tap(find.text('Открыть поиск'));
              },
            );
            final modalScope = find.byType(SearchProductModal);
            expect(modalScope, findsOneWidget, reason: modalTag);
            _assertInteractiveControls(
              tester,
              vpSize,
              modalTag,
              scope: modalScope,
              enforceFullViewportBounds: true,
            );
          });

          // 2. Карточка сведений о продукте (включая предупреждение о битом БЖУ).
          final infoTag = 'ProductInfo/$vpName/$themeName/x$scale';
          await _collect(failures, infoTag, () async {
            _setViewport(tester, vpSize);
            await _pumpAndCaptureErrors(
              tester,
              _buildScopedApp(
                theme: theme,
                textScale: scale,
                home: Scaffold(
                  body: ProductInfoCardSheet(
                    product: corruptProduct,
                    onAddToRecipe: () {},
                  ),
                ),
              ),
              infoTag,
            );
            _assertInteractiveControls(
              tester,
              vpSize,
              infoTag,
              scope: find.byType(ProductInfoCardSheet),
              enforceFullViewportBounds: true,
            );
          });
        }
      }
    }

    // Проверка пустого состояния поиска (empty state на экстремальных экранах).
    for (final (vpName, vpSize) in const [
      ('320x568', Size(320, 568)),
      ('640x320', Size(640, 320)),
      ('800x600', Size(800, 600)),
    ]) {
      for (final scale in const [1.0, 2.0]) {
        final emptyTag = 'SearchEmpty/$vpName/x$scale';
        await _collect(failures, emptyTag, () async {
          _setViewport(tester, vpSize);
          await _pumpAndCaptureErrors(
            tester,
            _buildScopedApp(
              theme: AppTheme.light,
              textScale: scale,
              repo: FakeProductRepo(results: const []),
              home: Builder(
                builder: (ctx) => Scaffold(
                  body: Center(
                    child: FilledButton(
                      onPressed: () => SearchProductModal.show(
                        ctx,
                        mode: SearchMode.pickForRecipe,
                      ),
                      child: const Text('Открыть пустой поиск'),
                    ),
                  ),
                ),
              ),
            ),
            emptyTag,
            afterPump: () async {
              await tester.tap(find.text('Открыть пустой поиск'));
            },
          );
          _assertInteractiveControls(
            tester,
            vpSize,
            emptyTag,
            scope: find.byType(SearchProductModal),
            enforceFullViewportBounds: true,
          );
        });
      }
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  testWidgets('CustomNumpadSheet: keys >=48dp, equal heights, zero overlap',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final failures = <String>[];

    for (final (vpName, vpSize) in _viewports) {
      for (final (themeName, theme) in _themes) {
        for (final scale in _textScales) {
          // 1. Внутри реального showModalBottomSheet(isScrollControlled: true).
          final sheetTag = 'NumpadSheet/$vpName/$themeName/x$scale';
          await _collect(failures, sheetTag, () async {
            _setViewport(tester, vpSize);
            await _pumpAndCaptureErrors(
              tester,
              _buildScopedApp(
                theme: theme,
                textScale: scale,
                home: Builder(
                  builder: (ctx) => Scaffold(
                    body: Center(
                      child: FilledButton(
                        onPressed: () => showModalBottomSheet<void>(
                          context: ctx,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (_) => CustomNumpadSheet(
                            product: _potatoWithMeasures,
                            initialGrams: 250,
                            initialIsGross: true,
                            onConfirm: (_, __) {},
                          ),
                        ),
                        child: const Text('Открыть нумпад'),
                      ),
                    ),
                  ),
                ),
              ),
              sheetTag,
              afterPump: () async {
                await tester.tap(find.text('Открыть нумпад'));
              },
            );
            _assertNumpadStrictLayout(tester, vpSize, sheetTag);
          });

          // 2. В ограниченном по высоте Scaffold.body (полная высота окна).
          final fullTag = 'NumpadBounded/$vpName/$themeName/x$scale';
          await _collect(failures, fullTag, () async {
            _setViewport(tester, vpSize);
            await _pumpAndCaptureErrors(
              tester,
              _buildScopedApp(
                theme: theme,
                textScale: scale,
                home: Scaffold(
                  body: CustomNumpadSheet(
                    product: _potatoWithMeasures,
                    initialGrams: 250,
                    initialIsGross: true,
                    onConfirm: (_, __) {},
                  ),
                ),
              ),
              fullTag,
            );
            _assertNumpadStrictLayout(tester, vpSize, fullTag);
          });
        }
      }
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  testWidgets('BlankPreviewScreen: AppBar & AppBottomBar zero overlap/overflow',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final failures = <String>[];

    for (final (vpName, vpSize) in _viewports) {
      for (final (themeName, theme) in _themes) {
        for (final scale in _textScales) {
          final tag = 'BlankPreview/$vpName/$themeName/x$scale';
          await _collect(failures, tag, () async {
            _setViewport(tester, vpSize);
            await _pumpAndCaptureErrors(
              tester,
              _buildScopedApp(
                theme: theme,
                textScale: scale,
                home: const BlankPreviewScreen(),
                activeDraft: _samplePopulatedDish(),
              ),
              tag,
            );
            _assertSingleLineAppBar(tester, vpSize, tag);
            _assertInteractiveControls(
              tester,
              vpSize,
              tag,
              enforceFullViewportBounds: true,
            );
            _assertRegionBoundsAndNoOverlap(
              tester,
              vpSize,
              find.byType(AppBottomBar),
              '$tag/BottomBar',
            );

            // Кнопки панели масштабирования на одной строке согласованы по высоте.
            _assertButtonPairConsistent(
              tester,
              _iconButtonFor(Icons.zoom_out_rounded),
              _iconButtonFor(Icons.zoom_in_rounded),
              '$tag/ZoomIcons',
            );
            _assertButtonPairConsistent(
              tester,
              _iconButtonFor(Icons.zoom_in_rounded),
              _buttonWithText<TextButton>('По размеру'),
              '$tag/ZoomAndReset',
            );
          });
        }
      }
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  });
}
