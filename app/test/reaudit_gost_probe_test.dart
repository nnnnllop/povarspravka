// Точечные пробы расчёта веса и групп потерь (независимо от корпуса).
//
// Задача 2026-11-03: пробы F1–F6 фиксировали дефекты удалённой модели
// выхода (`yield_physics.dart`: разваривание «рис» ×2,5, уварка, обнуление
// воды в бульоне, `isWaterProduct` по подстроке «вода»). Модель удалена,
// пробы переписаны: вес готового блюда только введённый (legacy — сумма
// нетто), а название продукта влияет только на группу потерь.
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/food_classifier.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/heat_process.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/loss_group.dart';
import 'package:povarspravka/core/calculation/models/product.dart';

Product p(String name, {double kal = 100}) => Product(
      id: name.hashCode & 0x7fffffff,
      code: name,
      name: name,
      groupId: 0,
      source: 'x',
      protein: 10,
      fat: 10,
      carbs: 10,
      kcal: kal,
    );

Dish d(List<Ingredient> ings, HeatProcess proc, {double? weight}) =>
    Dish.withProcess(
      id: 'x',
      process: proc,
      ingredients: ings,
      customYieldGrams: weight,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

void main() {
  test('F1 рис и заливка: вес не угадывается, вода не считается дважды', () {
    final rice = Ingredient(id: 'a', product: p('Крупа рисовая'), weightGrams: 100);
    final water = Ingredient(id: 'b', product: p('Вода питьевая'), weightGrams: 500);
    final noWater = d([rice], HeatProcess.boil);
    final withWater = d([rice, water], HeatProcess.boil);
    // Раньше: 250 г (×2,5) и 750 г (×2,5 + заливка) — вода учитывалась дважды.
    expect(noWater.effectiveYieldGrams, 0);
    expect(withWater.effectiveYieldGrams, 0);
    // Повар взвесил кашу — именно этот вес и берётся.
    expect(d([rice, water], HeatProcess.boil, weight: 320).effectiveYieldGrams,
        320);
    // Старый документ: сумма нетто, как до модели выхода.
    expect(d([rice, water], HeatProcess.legacy).effectiveYieldGrams, 600);
  });

  test('F2 имя с «рис» не разваривается — оно задаёт только группу потерь', () {
    const groups = {
      'Крупа рисовая': LossGroup.grainPasta,
      'Рис шлифованный, сырой': LossGroup.grainPasta,
      'Смесь риса с диким рисом, сырая': LossGroup.grainPasta,
      'Мука рисовая диетическая': LossGroup.flourBread,
      'Крупа перловая': LossGroup.grainPasta,
      'Крупа пшено шлифованное': LossGroup.grainPasta,
      'Крупа манная': LossGroup.grainPasta,
      'Крупа ячневая': LossGroup.grainPasta,
      'Крупа овсяная': LossGroup.grainPasta,
    };
    for (final e in groups.entries) {
      final ing = Ingredient(id: 'a', product: p(e.key), weightGrams: 100);
      final dish = d([ing], HeatProcess.boil);
      // ignore: avoid_print
      print('F2 «${e.key}» 100 г, варка -> вес ${dish.effectiveYieldGrams} г, '
          'группа ${ing.lossGroup.name}');
      expect(dish.effectiveYieldGrams, 0, reason: e.key);
      expect(ing.lossGroup, e.value, reason: e.key);
    }
  });

  test('F3 ни один способ обработки не меняет введённый вес', () {
    final ings = [
      Ingredient(id: 'a', product: p('Говядина 1 кат.'), weightGrams: 100),
      Ingredient(id: 'b', product: p('Картофель'), weightGrams: 200),
      Ingredient(id: 'c', product: p('Вода питьевая'), weightGrams: 100),
    ];
    for (final proc in HeatProcess.values) {
      final none = d(ings, proc);
      final entered = d(ings, proc, weight: 350);
      // ignore: avoid_print
      print('F3 ${proc.name}: 100+200+100 -> без веса ${none.effectiveYieldGrams} г, '
          'введено 350 -> ${entered.effectiveYieldGrams} г');
      expect(none.effectiveYieldGrams, proc.isLegacy ? 400 : 0, reason: proc.name);
      expect(entered.effectiveYieldGrams, 350, reason: proc.name);
    }
  });

  test('F4 бульон не обнуляет воду: вес бульона вводит повар', () {
    final ings = [
      Ingredient(id: 'a', product: p('Курица 1 кат.'), weightGrams: 100),
      Ingredient(id: 'b', product: p('Вода питьевая'), weightGrams: 1000),
    ];
    // Раньше: 100 г — вся вода «испарялась», бульон весил как курица.
    expect(d(ings, HeatProcess.stock).effectiveYieldGrams, 0);
    expect(d(ings, HeatProcess.stock, weight: 900).effectiveYieldGrams, 900);
  });

  test('F5 слово «вода» в названии больше не влияет на массу', () {
    // isWaterProduct() искала подстроку «вода» в ЛЮБОМ месте имени; функция
    // удалена вместе с моделью выхода.
    final ings = [
      Ingredient(id: 'a', product: p('Говядина 1 кат.'), weightGrams: 100),
      Ingredient(id: 'b', product: p('Соус «Вода-соус»'), weightGrams: 50),
    ];
    expect(d(ings, HeatProcess.legacy).effectiveYieldGrams, 150,
        reason: 'legacy: сумма нетто всех строк');
    expect(d(ings, HeatProcess.cold, weight: 150).effectiveYieldGrams, 150);
  });

  test('F6 реальные имена базы: группа потерь по названию', () {
    // Бывш. «сколько НЕ-воды попадает под isWaterProduct».
    const names = {
      // «Жирная» — характеристика мяса, а не группа «жиры».
      'Свинина жирная': LossGroup.meat,
      'Вода питьевая': LossGroup.other,
      // Готовый бульон — жидкость, а не сырое мясо.
      'Мясо-костный бульон': LossGroup.other,
      'Мука овсяная': LossGroup.flourBread,
      'Водоросли': LossGroup.vegetable,
      'Водка': LossGroup.other,
      'Водка 40%': LossGroup.other,
      'Простокваша 3,2% жирности': LossGroup.dairy,
      'Молоко сгущенное': LossGroup.dairy,
      'Соус «Вода-соус»': LossGroup.other,
    };
    for (final e in names.entries) {
      final g = FoodClassifier.classifyByName(e.key);
      // ignore: avoid_print
      print('F6 «${e.key}» -> ${g.name}');
      expect(g, e.value, reason: e.key);
    }
  });
}
