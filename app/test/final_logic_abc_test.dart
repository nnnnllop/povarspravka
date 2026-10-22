// Final logic audit - Block A: five reference recipes computed by hand and
// compared digit-for-digit with the real CalculationEngine.
//
// Hand arithmetic is written out in the comments so this file doubles as the
// audit worksheet.  All products are real reference.db rows (values quoted).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/calculation_engine.dart';
import 'package:povarspravka/core/calculation/models/blank_mode.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/product.dart';

Product p({
  String name = 'x',
  double protein = 0,
  double fat = 0,
  double carbs = 0,
  double kcal = 0,
  double waste = 0,
  String source = 'skurikhin',
}) =>
    Product(
      id: name.hashCode,
      code: name,
      name: name,
      groupId: 1,
      source: source,
      wastePct: waste,
      protein: protein,
      fat: fat,
      carbs: carbs,
      kcal: kcal,
    );

Dish dish(List<Ingredient> ings, {double? yieldGrams, double rp = .94, double rf = .88, double rc = .91, BlankMode mode = BlankMode.photoCross}) =>
    Dish(
      id: 'd',
      ingredients: ings,
      customYieldGrams: yieldGrams,
      retentionProtein: rp,
      retentionFat: rf,
      retentionCarbs: rc,
      blankMode: mode,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

void dump(String path, List<Map<String, dynamic>> rows) {
  final f = File(path);
  f.parent.createSync(recursive: true);
  f.writeAsStringSync(const JsonEncoder.withIndent(' ').convert(rows));
}

void main() {
  final out = <Map<String, dynamic>>[];

  // ---------------------------------------------------------------- A1
  // Пюре картофельное (по форме бланка).  Картофель 300 г НЕТТО,
  // масло сливочное «Крестьянское» 15 г, молоко 3,2 % 50 г.  Выход = 365.
  //
  //  300 * 2,00 / 100 = 6,00 ; 300 * 0,40/100 = 1,20 ; 300 * 16,30/100 = 48,90
  //   15 * 0,80 / 100 = 0,12 ;  15 * 72,50/100 = 10,875 -> 10,88 ; 15*1,30/100 = 0,195 -> 0,20
  //   50 * 2,90 / 100 = 1,45 ;  50 * 3,20/100 = 1,60 ;  50 * 4,70/100 = 2,35
  // Итого: 7,57 / 13,68 / 51,45
  // После т.о.: 7,57*0,94 = 7,1158 -> 7,12
  //             13,68*0,88 = 12,0384 -> 12,04
  //             51,45*0,91 = 46,8195 -> 46,82
  // ккал: 7,12*4 + 12,04*9 + 46,82*4 = 28,48 + 108,36 + 187,28 = 324,12 -> 324,1
  // На 100 г: 7,12*100/365 = 1,95 ; 12,04*100/365 = 3,30 ; 46,82*100/365 = 12,83
  //           324,12*100/365 = 88,80 -> 88,8
  test('A1 soup-like blank: recipe, totals, retention, energy, per-100g', () {
    final d = dish([
      Ingredient(id: '1', product: p(name: 'Картофель', protein: 2.0, fat: .40, carbs: 16.30, kcal: 77, waste: 28), weightGrams: 300),
      Ingredient(id: '2', product: p(name: 'Масло сливочное', protein: .80, fat: 72.50, carbs: 1.30, kcal: 661), weightGrams: 15),
      Ingredient(id: '3', product: p(name: 'Молоко 3,2%', protein: 2.90, fat: 3.20, carbs: 4.70, kcal: 60), weightGrams: 50),
    ]);
    final r = CalculationEngine.calculate(d);
    expect(r.rawTotalWeight, 365);
    expect(r.rawTotalProtein, 7.57);
    expect(r.rawTotalFat, 13.68);
    expect(r.rawTotalCarbs, 51.45);
    expect(r.cookedProtein, 7.12);
    expect(r.cookedFat, 12.04);
    expect(r.cookedCarbs, 46.82);
    expect(r.cookedKcal, 324.1);
    expect(r.per100gProtein, 1.95);
    expect(r.per100gFat, 3.30);
    expect(r.per100gCarbs, 12.83);
    expect(r.per100gKcal, 88.8);
    out.add({'id': 'A1', 'ok': true,
      'vals': [r.rawTotalProtein, r.rawTotalFat, r.rawTotalCarbs,
               r.cookedProtein, r.cookedFat, r.cookedCarbs, r.cookedKcal,
               r.per100gProtein, r.per100gFat, r.per100gCarbs, r.per100gKcal]});
  });

  // ---------------------------------------------------------------- A2
  // Салат без тепловой обработки, сохранность 100/100/100.
  // Огурцы грунтовые 150, томаты грунтовые 150, масло подсолнечное 15. Выход 315.
  //  1,20/0,15/3,75 ; 1,65/0,30/5,70 ; 0/14,985->14,99/0
  //  Итого 2,85 / 15,44 / 9,45 ; т.о. = те же
  //  ккал = 2,85*4 + 15,44*9 + 9,45*4 = 11,4 + 138,96 + 37,8 = 188,16 -> 188,2
  //  на 100 г: 0,90 / 4,90 / 3,00 ; 188,16*100/315 = 59,73 -> 59,7
  test('A2 cold dish keeps 100/100/100 retention', () {
    final d = dish([
      Ingredient(id: '1', product: p(name: 'Огурцы', protein: .80, fat: .10, carbs: 2.50, kcal: 14), weightGrams: 150),
      Ingredient(id: '2', product: p(name: 'Томаты', protein: 1.10, fat: .20, carbs: 3.80, kcal: 24), weightGrams: 150),
      Ingredient(id: '3', product: p(name: 'Масло подсолнечное', protein: 0, fat: 99.90, carbs: 0, kcal: 899), weightGrams: 15),
    ], rp: 1, rf: 1, rc: 1);
    final r = CalculationEngine.calculate(d);
    expect(r.rawTotalProtein, 2.85);
    expect(r.rawTotalFat, 15.44);
    expect(r.rawTotalCarbs, 9.45);
    expect(r.cookedProtein, 2.85);
    expect(r.cookedFat, 15.44);
    expect(r.cookedCarbs, 9.45);
    expect(r.cookedKcal, 188.2);
    expect(r.per100gProtein, .90);
    expect(r.per100gFat, 4.90);
    expect(r.per100gCarbs, 3.00);
    expect(r.per100gKcal, 59.7);
    out.add({'id': 'A2', 'ok': true,
      'vals': [r.cookedProtein, r.cookedFat, r.cookedCarbs, r.cookedKcal,
               r.per100gProtein, r.per100gFat, r.per100gCarbs, r.per100gKcal]});
  });

  // ---------------------------------------------------------------- A3
  // Разбавление: сумма нетто 600 г, выход 1000 г (добавлена вода).
  // Картофель 300, морковь 150, лук 100, масло 20, сметана 30 -> 600.
  //  картофель 6,00/1,20/48,90 ; морковь 150*1,30/100=1,95 ; 150*0,10/100=0,15 ;
  //            150*6,90/100=10,35 ; лук 100*1,40/100=1,40 ; 100*0,20/100=0,20 ;
  //            100*8,20/100=8,20 ; масло 20*0,80/100=0,16 ; 20*72,50/100=14,50 ;
  //            20*1,30/100=0,26 ; сметана 30*2,50/100=0,75 ; 30*20/100=6,00 ;
  //            30*3,40/100=1,02
  //  Итого Б = 6,00+1,95+1,40+0,16+0,75 = 10,26
  //        Ж = 1,20+0,15+0,20+14,50+6,00 = 22,05
  //        У = 48,90+10,35+8,20+0,26+1,02 = 68,73
  //  После т.о.: 10,26*0,94 = 9,6444 -> 9,64 ; 22,05*0,88 = 19,404 -> 19,40
  //              68,73*0,91 = 62,5443 -> 62,54
  //  ккал = 9,64*4 + 19,40*9 + 62,54*4 = 38,56 + 174,6 + 250,16 = 463,32 -> 463,3
  //  На 100 г (выход 1000): 0,96 / 1,94 / 6,25 ; 46,33 -> 46,3
  test('A3 dilution: total mass of nutrients unchanged, per-100g falls', () {
    final d = dish([
      Ingredient(id: '1', product: p(name: 'Картофель', protein: 2.0, fat: .40, carbs: 16.30), weightGrams: 300),
      Ingredient(id: '2', product: p(name: 'Морковь', protein: 1.30, fat: .10, carbs: 6.90), weightGrams: 150),
      Ingredient(id: '3', product: p(name: 'Лук', protein: 1.40, fat: .20, carbs: 8.20), weightGrams: 100),
      Ingredient(id: '4', product: p(name: 'Масло сливочное', protein: .80, fat: 72.50, carbs: 1.30), weightGrams: 20),
      Ingredient(id: '5', product: p(name: 'Сметана 20%', protein: 2.50, fat: 20.00, carbs: 3.40), weightGrams: 30),
    ], yieldGrams: 1000);
    final r = CalculationEngine.calculate(d);
    expect(r.rawTotalWeight, 600);
    expect(r.rawTotalProtein, 10.26);
    expect(r.rawTotalFat, 22.05);
    expect(r.rawTotalCarbs, 68.73);
    expect(r.cookedProtein, 9.64);
    expect(r.cookedFat, 19.40);
    expect(r.cookedCarbs, 62.54);
    expect(r.cookedKcal, 463.3);
    expect(r.per100gProtein, .96);
    expect(r.per100gFat, 1.94);
    expect(r.per100gCarbs, 6.25);
    expect(r.per100gKcal, 46.3);
    out.add({'id': 'A3', 'ok': true,
      'vals': [r.rawTotalProtein, r.rawTotalFat, r.rawTotalCarbs,
               r.cookedProtein, r.cookedFat, r.cookedCarbs, r.cookedKcal,
               r.per100gProtein, r.per100gFat, r.per100gCarbs, r.per100gKcal]});
  });

  // ---------------------------------------------------------------- A4
  // Уварка: сумма нетто 1000 г, выход 750 г.  Говядина 600 + лук 100 +
  // хлеб 80 + молоко 120 + масло 100 = 1000.
  //  говядина 600*18,60/100 = 111,60 ; 600*16,00/100 = 96,00 ; 0
  //  лук      100*1,40/100 = 1,40 ; 0,20 ; 8,20
  //  хлеб     80*7,60/100 = 6,08 ; 80*0,80/100 = 0,64 ; 80*49,20/100 = 39,36
  //  молоко   120*2,90/100 = 3,48 ; 120*3,20/100 = 3,84 ; 120*4,70/100 = 5,64
  //  масло    100*0,80/100 = 0,80 ; 100*72,50/100 = 72,50 ; 100*1,30/100 = 1,30
  //  Итого Б = 111,60+1,40+6,08+3,48+0,80 = 123,36
  //        Ж = 96,00+0,20+0,64+3,84+72,50 = 173,18
  //        У = 0+8,20+39,36+5,64+1,30 = 54,50
  //  После т.о.: 123,36*0,94 = 115,9584 -> 115,96
  //              173,18*0,88 = 152,3984 -> 152,40
  //              54,50*0,91  = 49,595 -> 49,60
  //  ккал = 115,96*4 + 152,40*9 + 49,60*4 = 463,84 + 1371,6 + 198,4 = 2033,84 -> 2033,8
  //  На 100 г (выход 750): 115,96*100/750 = 15,46 ; 152,40*100/750 = 20,32
  //                        49,60*100/750 = 6,61 ; 2033,84*100/750 = 271,18 -> 271,2
  test('A4 simmering: per-100g rises with shrink', () {
    final d = dish([
      Ingredient(id: '1', product: p(name: 'Говядина 1 кат.', protein: 18.60, fat: 16.00, carbs: 0), weightGrams: 600),
      Ingredient(id: '2', product: p(name: 'Лук', protein: 1.40, fat: .20, carbs: 8.20), weightGrams: 100),
      Ingredient(id: '3', product: p(name: 'Хлеб пшеничный', protein: 7.60, fat: .80, carbs: 49.20), weightGrams: 80),
      Ingredient(id: '4', product: p(name: 'Молоко 3,2%', protein: 2.90, fat: 3.20, carbs: 4.70), weightGrams: 120),
      Ingredient(id: '5', product: p(name: 'Масло сливочное', protein: .80, fat: 72.50, carbs: 1.30), weightGrams: 100),
    ], yieldGrams: 750);
    final r = CalculationEngine.calculate(d);
    expect(r.rawTotalWeight, 1000);
    expect(r.rawTotalProtein, 123.36);
    expect(r.rawTotalFat, 173.18);
    expect(r.rawTotalCarbs, 54.50);
    expect(r.cookedProtein, 115.96);
    expect(r.cookedFat, 152.40);
    expect(r.cookedCarbs, 49.60);
    expect(r.cookedKcal, 2033.8);
    expect(r.per100gProtein, 15.46);
    expect(r.per100gFat, 20.32);
    expect(r.per100gCarbs, 6.61);
    expect(r.per100gKcal, 271.2);
    out.add({'id': 'A4', 'ok': true,
      'vals': [r.rawTotalProtein, r.rawTotalFat, r.rawTotalCarbs,
               r.cookedProtein, r.cookedFat, r.cookedCarbs, r.cookedKcal,
               r.per100gProtein, r.per100gFat, r.per100gCarbs, r.per100gKcal]});
  });

  // ---------------------------------------------------------------- A5
  // Брутто/нетто: картофель брутто 400 при отходах 25 % -> нетто 300;
  // свёкла брутто 250 при 20 % -> нетто 200; масло нетто 30 (0 %).
  //  400*75/100 = 300 ; 250*80/100 = 200 ; 30.
  //  Б в блюде: 300*2,00/100 = 6,00 ; 200*1,50/100 = 3,00 ; 30*0,80/100 = 0,24
  //  Ж: 1,20 ; 0,20 ; 21,75
  //  У: 48,90 ; 17,60 ; 0,39
  //  Итого Б = 9,24 ; Ж = 23,15 ; У = 66,89 ; масса нетто 530
  //  После т.о.: 9,24*0,94 = 8,6856 -> 8,69 ; 23,15*0,88 = 20,372 -> 20,37
  //              66,89*0,91 = 60,8699 -> 60,87
  //  ккал = 8,69*4 + 20,37*9 + 60,87*4 = 34,76 + 183,33 + 243,48 = 461,57 -> 461,6
  //  На 100 г (выход = 530): 8,69*100/530 = 1,6396 -> 1,64 ;
  //    20,37*100/530 = 3,8434 -> 3,84 ; 60,87*100/530 = 11,4849 -> 11,48
  //    (11,4849 < 11,485, поэтому HALF-UP даёт 11,48, а не 11,49)
  //    461,57*100/530 = 87,0887 -> 87,1
  test('A5 gross/net with waste; net is what enters the billet', () {
    final d = dish([
      Ingredient(id: '1', product: p(name: 'Картофель', protein: 2.0, fat: .40, carbs: 16.30, waste: 25), weightGrams: 400, isGross: true),
      Ingredient(id: '2', product: p(name: 'Свекла', protein: 1.50, fat: .10, carbs: 8.80, waste: 20), weightGrams: 250, isGross: true),
      Ingredient(id: '3', product: p(name: 'Масло сливочное', protein: .80, fat: 72.50, carbs: 1.30), weightGrams: 30),
    ]);
    final r = CalculationEngine.calculate(d);
    expect(d.ingredients[0].netGramsRounded, 300);
    expect(d.ingredients[1].netGramsRounded, 200);
    expect(d.ingredients[2].netGramsRounded, 30);
    expect(r.rawTotalWeight, 530);
    expect(r.rawTotalProtein, 9.24);
    expect(r.rawTotalFat, 23.15);
    expect(r.rawTotalCarbs, 66.89);
    expect(r.cookedProtein, 8.69);
    expect(r.cookedFat, 20.37);
    expect(r.cookedCarbs, 60.87);
    expect(r.cookedKcal, 461.6);
    expect(r.per100gProtein, 1.64);
    expect(r.per100gFat, 3.84);
    expect(r.per100gCarbs, 11.48);
    expect(r.per100gKcal, 87.1);
    out.add({'id': 'A5', 'ok': true,
      'vals': [r.rawTotalWeight, r.rawTotalProtein, r.rawTotalFat,
               r.rawTotalCarbs, r.cookedProtein, r.cookedFat, r.cookedCarbs,
               r.cookedKcal, r.per100gProtein, r.per100gFat,
               r.per100gCarbs, r.per100gKcal]});
  });

  // ---------------------------------------------------------------- B
  // Mode switch: "photoCross" vs "detailed" must not change cooked values.
  test('B1 blank mode does not change any cooked number', () {
    final ings = [
      Ingredient(id: '1', product: p(name: 'Говядина', protein: 18.60, fat: 16.00, carbs: 0), weightGrams: 600),
    ];
    final a = CalculationEngine.calculate(dish(ings, yieldGrams: 750));
    final b = CalculationEngine.calculate(
        dish(ings, yieldGrams: 750, mode: BlankMode.detailed));
    expect(a.cookedProtein, b.cookedProtein);
    expect(a.cookedFat, b.cookedFat);
    expect(a.cookedCarbs, b.cookedCarbs);
    expect(a.cookedKcal, b.cookedKcal);
  });

  // Ratio: portion must not contradict the whole dish (A4 recipe, 750 g).
  test('B2 portion is consistent with whole dish', () {
    final r = CalculationEngine.calculate(dish([
      Ingredient(id: '1', product: p(name: 'Говядина 1 кат.', protein: 18.60, fat: 16.00, carbs: 0), weightGrams: 600),
      Ingredient(id: '2', product: p(name: 'Лук', protein: 1.40, fat: .20, carbs: 8.20), weightGrams: 100),
      Ingredient(id: '3', product: p(name: 'Хлеб пшеничный', protein: 7.60, fat: .80, carbs: 49.20), weightGrams: 80),
      Ingredient(id: '4', product: p(name: 'Молоко 3,2%', protein: 2.90, fat: 3.20, carbs: 4.70), weightGrams: 120),
      Ingredient(id: '5', product: p(name: 'Масло сливочное', protein: .80, fat: 72.50, carbs: 1.30), weightGrams: 100),
    ], yieldGrams: 750));
    final portion = r.portion(150);
    // 115,96 * 150/750 = 23,192 -> 23,19 ; 152,40*150/750 = 30,48
    // 49,60*150/750 = 9,92 ; 2033,84*150/750 = 406,768 -> 406,8
    expect(portion.protein, 23.19);
    expect(portion.fat, 30.48);
    expect(portion.carbs, 9.92);
    expect(portion.kcal, 406.8);
  });

  dump(r'C:\projects\povarspravka\audit\signoff\a_results.json', out);
}
