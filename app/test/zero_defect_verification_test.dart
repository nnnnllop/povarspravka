import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/calculation_math.dart';
import 'package:povarspravka/core/calculation/calculation_engine.dart';
import 'package:povarspravka/core/calculation/calculation_validation.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/data/repositories/dish_storage_repository.dart';
import 'package:povarspravka/presentation/providers/dish_provider.dart';
import 'culinary_logic_test.dart' show beet, fixture;

class GateStorage extends DishStorageRepository {
  final gates = <Completer<void>>[];
  final payloads = <List<Dish>>[];
  final drafts = <Dish?>[];
  bool fail = false;
  @override
  Future<void> saveAll({required Dish? activeDraft, required List<Dish> savedDishes}) async {
    payloads.add(List.of(savedDishes)); drafts.add(activeDraft);
    if (fail) throw StateError('injected I/O failure');
    final gate = Completer<void>(); gates.add(gate); await gate.future;
  }
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('ZD01 zero multiplier must not conceal NaN or Infinity', () {
    for (final invalid in [double.nan, double.infinity, double.negativeInfinity]) {
      expect(() => CalculationMath.productRounded(0, invalid, 2), throwsArgumentError);
      expect(() => CalculationMath.productRounded(invalid, 0, 2), throwsArgumentError);
    }
  });
  test('ZD02 energy rounds the weighted sum once, symmetrically HALF-UP', () {
    expect(CalculationMath.energy(.014, 0, 0), .1); // .056 -> .1, not .04 -> 0
    expect(CalculationMath.energy(-.02, 0, 0), -.1);
    expect(() => CalculationMath.energy(double.infinity, 0, 0), throwsArgumentError);
  });
  test('ZD03 gross/net final precision must not double-round', () {
    final ing = Ingredient(id: 'boundary', product: beet.copyWith(wastePct: .1), weightGrams: .05005, isGross: true);
    // Exact decimal result .04999995 < .05: final HALF-UP at .1 g is zero.
    expect(ing.netGramsRounded, 0);
  });
  test('ZD04 exact product mass bound has no 0.05g loophole', () {
    final p = beet.copyWith(protein: 100, fat: .01, carbs: 0);
    expect(() => CalculationValidation.product(p), throwsArgumentError);
  });
  test('ZD05 cooked mass cannot exceed yield, even by .01g', () {
    final d = fixture(.1, yieldGrams: .1).copyWith(retentionProtein: 1,retentionFat: 1,retentionCarbs: 1,ingredients: [
      Ingredient(id: 'p',weightGrams: .1,product: beet.copyWith(protein: 35,fat: 35,carbs: 30))]);
    // Printed macro rows: .04+.04+.03=.11 > .1g.
    expect(() => CalculationEngine.calculate(d), throwsArgumentError);
  });
  test('ZD06 zero-mass ingredient round-trips as valid draft data', () async {
    final d = fixture(0);
    final storage = DishStorageRepository();
    await storage.saveAll(activeDraft: d, savedDishes: []);
    expect((await storage.loadAll()).activeDraft!.ingredients.single.weightGrams, 0);
    expect(Ingredient.fromJson(d.ingredients.single.toJson()).weightGrams, 0);
  });
  test('ZD07 concurrent library saves preserve both recipes', () async {
    final s = GateStorage(); final n = SavedDishesNotifier(s); addTearDown(n.dispose);
    final a = n.saveDish(fixture(100).copyWith(id:'a'));
    final b = n.saveDish(fixture(200).copyWith(id:'b'));
    await Future<void>.delayed(Duration.zero);
    s.gates.first.complete(); await a;
    await Future<void>.delayed(Duration.zero);
    for (final g in s.gates) { if (!g.isCompleted) g.complete(); }
    await b;
    expect(n.state.map((d)=>d.id).toSet(), {'a','b'});
    expect(s.payloads.last.map((d)=>d.id).toSet(), {'a','b'});
  });
  test('ZD08 failed draft write cannot poison a later library save', () async {
    final s = GateStorage(); final n = SavedDishesNotifier(s); addTearDown(n.dispose);
    final initial = fixture(100); n.setInitialDishes([],initial);
    s.fail = true;
    await expectLater(n.updateDraftReference(fixture(200)), throwsStateError);
    s.fail = false;
    final save = n.saveDish(initial);
    await Future<void>.delayed(Duration.zero);
    s.gates.single.complete(); await save;
    expect(s.drafts.last!.ingredients.single.weightGrams, 100);
  });
  test('Scenario grid: waste, mass, no heat and dilution preserve displayed totals', () {
    for (final waste in [0.0,.1,.5,1.5,25.0,80.0,99.9,100.0]) {
      for (final mass in [.01,.05,.1,.6,.7,100000.0,1000000.0]) {
        final d = fixture(mass).copyWith(retentionProtein:1,retentionFat:1,retentionCarbs:1,ingredients:[Ingredient(id:'grid',product:beet.copyWith(wastePct:waste),weightGrams:mass,isGross:true)]);
        final r = CalculationEngine.calculate(d);
        expect(r.yieldGrams.isFinite,isTrue); expect(r.cookedKcal.isFinite,isTrue);
        expect(r.rawTotalWeight,d.ingredients.single.netGramsRounded);
      }
    }
    for (final n in [0,1,60]) {
      final d = fixture(100).copyWith(ingredients:List.generate(n,(i)=>Ingredient(id:'$i',product:beet,weightGrams:100)));
      final r = CalculationEngine.calculate(d); expect(r.rawTotalWeight,100.0*n);
    }
    for (final y in [10.0,1000.0]) {
      final r=CalculationEngine.calculate(fixture(100,yieldGrams:y)); expect(r.per100gProtein,CalculationMath.ratioRounded(r.cookedProtein,y,2));
    }
    final water=fixture(100).copyWith(ingredients:[Ingredient(id:'water',product:beet.copyWith(protein:0,fat:0,carbs:0,kcal:0),weightGrams:100)]);
    expect(CalculationEngine.calculate(water).cookedKcal,0);
    for (final text in ['0,01','0,05','0,1','0,6','0,7']) {expect(CalculationEngine.parseInputDouble(text),double.parse(text.replaceAll(',','.')));}
  });

  test('R01 UUIDv4 format compliant and unique across instances', () async {
    final s = GateStorage();
    final n = SavedDishesNotifier(s);
    final dn = DishNotifier(storage: s, savedDishesNotifier: n);
    final uuidRegex = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
    expect(uuidRegex.hasMatch(dn.state.id), isTrue);
    dn.addIngredient(beet, 100);
    expect(uuidRegex.hasMatch(dn.state.ingredients.single.id), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    dn.dispose();
    n.dispose();
  });

  test('DB01 products with nutrients > 100g are detected and rejected by CalculationValidation', () {
    final sealOil = beet.copyWith(
      name: 'Масло, бородатая тюлень',
      protein: 0.56,
      fat: 99.6,
      carbs: 0.0,
      hasExplicitProtein: true,
      hasExplicitFat: true,
      hasExplicitCarbs: true,
    );
    expect(() => CalculationValidation.product(sealOil), throwsArgumentError);
  });
}
