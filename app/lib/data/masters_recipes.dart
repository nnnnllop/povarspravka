import '../core/calculation/models/dish.dart';
import '../core/calculation/models/heat_process.dart';
import '../core/calculation/models/ingredient.dart';
import '../core/calculation/models/product.dart';

/// Модель эталонной технологической карты из Сборника рецептур
class MasterRecipe {
  final String id;
  final String name;
  final String standardCode; // например, «Рецептура № 165 (Марчук)»
  final String category;
  final String description;
  final double expectedYieldGrams;
  final String culinaryProcess;
  final List<MasterIngredientItem> ingredients;

  const MasterRecipe({
    required this.id,
    required this.name,
    required this.standardCode,
    required this.category,
    required this.description,
    required this.expectedYieldGrams,
    required this.culinaryProcess,
    required this.ingredients,
  });

  /// Способ тепловой обработки карты — строка таблицы потерь (`LossTable`).
  ///
  /// Выводится из [culinaryProcess]: карты Сборника уже описывают способ
  /// обработки словами, дублировать его отдельным полем не нужно. Супы, каши
  /// и припускание — варка; вес готового блюда — выход карты
  /// ([expectedYieldGrams]), он не вычисляется.
  HeatProcess get heatProcess {
    final c = culinaryProcess.toLowerCase();
    if (c.contains('суп')) return HeatProcess.boil;
    if (c.contains('каш') || c.contains('круп')) return HeatProcess.boil;
    if (c.contains('жарк')) return HeatProcess.fry;
    if (c.contains('запек')) return HeatProcess.bake;
    if (c.contains('тушен')) return HeatProcess.stew;
    if (c.contains('пар')) return HeatProcess.steam;
    if (c.contains('отварив') ||
        c.contains('отварн') ||
        c.contains('варк') ||
        c.contains('припуск') ||
        c.contains('соус')) {
      return HeatProcess.boil;
    }
    if (c.contains('бульон') || c.contains('отвар')) return HeatProcess.stock;
    if (c.contains('холод') || c.contains('салат')) return HeatProcess.cold;
    return HeatProcess.cold;
  }

  /// Создает объект Dish, готовый для расчета в калькуляторе
  Dish toDish() {
    final now = DateTime.now();
    return Dish.withProcess(
      id: 'master_${id}_${now.millisecondsSinceEpoch}',
      process: heatProcess,
      title: name,
      customYieldGrams: expectedYieldGrams,
      showTitleInExport: true,
      ingredients: ingredients.map((item) => item.toIngredient()).toList(),
      createdAt: now,
      updatedAt: now,
    );
  }
}

class MasterIngredientItem {
  final int productId;
  final String name;
  final double weightGrams; // введено в брутто или нетто
  final bool isGross;
  final double wastePct;
  final double protein;
  final double fat;
  final double carbs;
  final double kcal;
  final String source;

  const MasterIngredientItem({
    required this.productId,
    required this.name,
    required this.weightGrams,
    required this.isGross,
    required this.wastePct,
    required this.protein,
    required this.fat,
    required this.carbs,
    required this.kcal,
    this.source = 'skurikhin',
  });

  /// `group_id` продуктов карт в `assets/db/reference.db` (таблица `product`,
  /// группы Скурихина 1…12). Неизвестный продукт → `0` (группа по названию).
  static const Map<int, int> referenceGroupIds = {
    53: 1, 82: 1, // молоко, творог
    159: 2, // яйцо
    174: 3, 183: 3, // говядина, свинина
    509: 5, 533: 5, // масло сливочное, подсолнечное
    561: 6, 562: 6, 654: 6, // мука, хлеб, крупа гречневая
    712: 8, 738: 8, 742: 8, 768: 8, 779: 8, 818: 8, // овощи, картофель
    930: 10, // сахар
    20002: 12, // вода
  };

  Ingredient toIngredient() {
    final product = Product(
      id: productId,
      code: '$productId',
      // Группа справочника — основа классификатора потерь. Раньше здесь стояла
      // группа 1 («Молоко») для всех ингредиентов.
      groupId: referenceGroupIds[productId] ?? 0,
      name: name,
      source: source,
      protein: protein,
      fat: fat,
      carbs: carbs,
      kcal: kcal,
      wastePct: wastePct,
    );
    return Ingredient(
      id: 'ing_${productId}_${DateTime.now().microsecondsSinceEpoch}',
      product: product,
      weightGrams: weightGrams,
      isGross: isGross,
    );
  }
}

/// Эталонные раскладки из официального Сборника рецептур блюд и кулинарных изделий
/// для предприятий общественного питания (под ред. Ф. Л. Марчука, ГОСТ/СанПиН).
class MastersRecipesCatalog {
  static const List<MasterRecipe> recipes = [
    MasterRecipe(
      id: 'borscht_165',
      name: 'Борщ с капустой и картофелем',
      standardCode: 'Марчук, рец. № 165',
      category: 'Супы',
      description: 'Классический борщ по 2-й колонке сборника рецептур. Потери массы при варке 15-20%; потери Б/Ж/У — по таблице для каждого продукта.',
      expectedYieldGrams: 1000.0,
      culinaryProcess: 'Варка супов',
      ingredients: [
        MasterIngredientItem(
          productId: 779,
          name: 'Свекла',
          weightGrams: 200.0,
          isGross: true,
          wastePct: 20.0,
          protein: 1.5,
          fat: 0.1,
          carbs: 8.8,
          kcal: 42.0,
          source: 'skurikhin',
        ),
        MasterIngredientItem(
          productId: 712,
          name: 'Капуста белокочанная',
          weightGrams: 150.0,
          isGross: true,
          wastePct: 20.0,
          protein: 1.8,
          fat: 0.1,
          carbs: 4.7,
          kcal: 28.0,
          source: 'skurikhin',
        ),
        MasterIngredientItem(
          productId: 742,
          name: 'Картофель',
          weightGrams: 160.0,
          isGross: true,
          wastePct: 28.0,
          protein: 2.0,
          fat: 0.4,
          carbs: 16.3,
          kcal: 77.0,
          source: 'skurikhin',
        ),
        MasterIngredientItem(
          productId: 768,
          name: 'Морковь',
          weightGrams: 50.0,
          isGross: true,
          wastePct: 20.0,
          protein: 1.3,
          fat: 0.1,
          carbs: 6.9,
          kcal: 35.0,
          source: 'skurikhin',
        ),
        MasterIngredientItem(
          productId: 738,
          name: 'Лук репчатый',
          weightGrams: 48.0,
          isGross: true,
          wastePct: 16.0,
          protein: 1.4,
          fat: 0.2,
          carbs: 8.2,
          kcal: 41.0,
          source: 'skurikhin',
        ),
        MasterIngredientItem(
          productId: 818,
          name: 'Томатная паста. Консервы',
          weightGrams: 30.0,
          isGross: false,
          wastePct: 0.0,
          protein: 4.8,
          fat: 0.0,
          carbs: 19.0,
          kcal: 102.0,
          source: 'skurikhin',
        ),
        MasterIngredientItem(
          productId: 533,
          name: 'Масло подсолнечное',
          weightGrams: 20.0,
          isGross: false,
          wastePct: 0.0,
          protein: 0.0,
          fat: 99.9,
          carbs: 0.0,
          kcal: 899.0,
          source: 'skurikhin',
        ),
        MasterIngredientItem(
          productId: 930,
          name: 'Сахар-песок',
          weightGrams: 10.0,
          isGross: false,
          wastePct: 0.0,
          protein: 0.0,
          fat: 0.0,
          carbs: 99.8,
          kcal: 399.0,
          source: 'skurikhin',
        ),
        MasterIngredientItem(
          productId: 20002,
          name: 'Вода питьевая',
          weightGrams: 700.0,
          isGross: false,
          wastePct: 0.0,
          protein: 0.0,
          fat: 0.0,
          carbs: 0.0,
          kcal: 0.0,
          source: 'supplement',
        ),
      ],
    ),
    MasterRecipe(
      id: 'puree_694',
      name: 'Пюре картофельное',
      standardCode: 'Марчук, рец. № 694',
      category: 'Гарниры',
      description: 'Готовится из отварного горячего картофеля с добавлением растопленного сливочного масла и прогретого молока. Уварка картофеля около 3%.',
      expectedYieldGrams: 250.0,
      culinaryProcess: 'Варка / припускание',
      ingredients: [
        MasterIngredientItem(
          productId: 742,
          name: 'Картофель',
          weightGrams: 320.0,
          isGross: true,
          wastePct: 28.0,
          protein: 2.0,
          fat: 0.4,
          carbs: 16.3,
          kcal: 77.0,
          source: 'skurikhin',
        ),
        MasterIngredientItem(
          productId: 53,
          name: 'Молоко пастеризованное 3,2% жирности',
          weightGrams: 38.0,
          isGross: false,
          wastePct: 0.0,
          protein: 2.9,
          fat: 3.2,
          carbs: 4.7,
          kcal: 60.0,
          source: 'skurikhin',
        ),
        MasterIngredientItem(
          productId: 509,
          name: 'Масло сливочное несоленое «Крестьянское»',
          weightGrams: 15.0,
          isGross: false,
          wastePct: 0.0,
          protein: 0.8,
          fat: 72.5,
          carbs: 1.3,
          kcal: 661.0,
          source: 'skurikhin',
        ),
      ],
    ),
    MasterRecipe(
      id: 'buckwheat_438',
      name: 'Каша гречневая рассыпчатая',
      standardCode: 'Марчук, рец. № 438',
      category: 'Каши',
      description: 'Приварок гречневой крупы ядрицы составляет +110%. На 100 г крупы расходуется 150 г воды. Выход 210 г.',
      expectedYieldGrams: 210.0,
      culinaryProcess: 'Варка каш',
      ingredients: [
        MasterIngredientItem(
          productId: 654,
          name: 'Крупа гречневая ядрица',
          weightGrams: 100.0,
          isGross: false,
          wastePct: 0.0,
          protein: 12.6,
          fat: 3.3,
          carbs: 57.1,
          kcal: 308.0,
          source: 'skurikhin',
        ),
        MasterIngredientItem(
          productId: 20002,
          name: 'Вода питьевая',
          weightGrams: 150.0,
          isGross: false,
          wastePct: 0.0,
          protein: 0.0,
          fat: 0.0,
          carbs: 0.0,
          kcal: 0.0,
          source: 'supplement',
        ),
        MasterIngredientItem(
          productId: 509,
          name: 'Масло сливочное несоленое «Крестьянское»',
          weightGrams: 10.0,
          isGross: false,
          wastePct: 0.0,
          protein: 0.8,
          fat: 72.5,
          carbs: 1.3,
          kcal: 661.0,
          source: 'skurikhin',
        ),
      ],
    ),
    MasterRecipe(
      id: 'cutlets_598',
      name: 'Котлеты домашние',
      standardCode: 'Марчук, рец. № 598',
      category: 'Мясные блюда',
      description: 'Котлетная масса из говядины и свинины с пшеничным хлебом. Потери массы при жарке основным способом — 19%.',
      expectedYieldGrams: 150.0,
      culinaryProcess: 'Жарка основным способом',
      ingredients: [
        MasterIngredientItem(
          productId: 174,
          name: 'Говядина 1 кат.',
          weightGrams: 90.0,
          isGross: false,
          wastePct: 0.0,
          protein: 18.6,
          fat: 16.0,
          carbs: 0.0,
          kcal: 218.0,
          source: 'skurikhin',
        ),
        MasterIngredientItem(
          productId: 183,
          name: 'Свинина мясная',
          weightGrams: 50.0,
          isGross: false,
          wastePct: 15.0,
          protein: 14.3,
          fat: 33.3,
          carbs: 0.0,
          kcal: 357.0,
          source: 'skurikhin',
        ),
        MasterIngredientItem(
          productId: 562,
          name: 'Хлеб пшеничный формовой',
          weightGrams: 28.0,
          isGross: false,
          wastePct: 0.0,
          protein: 7.6,
          fat: 0.8,
          carbs: 49.2,
          kcal: 235.0,
          source: 'skurikhin',
        ),
        MasterIngredientItem(
          productId: 20002,
          name: 'Вода питьевая',
          weightGrams: 35.0,
          isGross: false,
          wastePct: 0.0,
          protein: 0.0,
          fat: 0.0,
          carbs: 0.0,
          kcal: 0.0,
          source: 'supplement',
        ),
        MasterIngredientItem(
          productId: 533,
          name: 'Масло подсолнечное',
          weightGrams: 10.0,
          isGross: false,
          wastePct: 0.0,
          protein: 0.0,
          fat: 99.9,
          carbs: 0.0,
          kcal: 899.0,
          source: 'skurikhin',
        ),
      ],
    ),
    MasterRecipe(
      id: 'syrniki_493',
      name: 'Сырники из творога',
      standardCode: 'Марчук, рец. № 493',
      category: 'Блюда из творога',
      description: 'Творог растирают с мукой, сахаром и яйцом. Жарят с двух сторон до золотистой корочки. Потери при жарке около 10%.',
      expectedYieldGrams: 175.0,
      culinaryProcess: 'Жарка основным способом',
      ingredients: [
        MasterIngredientItem(
          productId: 82,
          name: 'Творог полужирный 9,0% жирности',
          weightGrams: 150.0,
          isGross: false,
          wastePct: 0.0,
          protein: 18.0,
          fat: 9.0,
          carbs: 3.0,
          kcal: 169.0,
          source: 'skurikhin',
        ),
        MasterIngredientItem(
          // Дефект D13: в пекарском рецепте стояла мука высшего сорта для
          // МАКАРОННЫХ изделий (6.1.2.1), у неё другой состав. Для хлеба —
          // 6.1.3.1 «Мука высшего сорта (хлеб)»: Б 10,3 / Ж 1,1 / У 70,6 /
          // 334 ккал на 100 г.
          productId: 561,
          name: 'Мука высшего сорта (хлеб)',
          weightGrams: 22.0,
          isGross: false,
          wastePct: 0.0,
          protein: 10.3,
          fat: 1.1,
          carbs: 70.6,
          kcal: 334.0,
          source: 'skurikhin',
        ),
        MasterIngredientItem(
          productId: 159,
          name: 'Яйцо куриное',
          weightGrams: 12.0,
          isGross: false,
          wastePct: 13.0,
          protein: 12.7,
          fat: 11.5,
          carbs: 0.7,
          kcal: 157.0,
          source: 'skurikhin',
        ),
        MasterIngredientItem(
          productId: 930,
          name: 'Сахар-песок',
          weightGrams: 15.0,
          isGross: false,
          wastePct: 0.0,
          protein: 0.0,
          fat: 0.0,
          carbs: 99.8,
          kcal: 399.0,
          source: 'skurikhin',
        ),
        MasterIngredientItem(
          productId: 509,
          name: 'Масло сливочное несоленое «Крестьянское»',
          weightGrams: 10.0,
          isGross: false,
          wastePct: 0.0,
          protein: 0.8,
          fat: 72.5,
          carbs: 1.3,
          kcal: 661.0,
          source: 'skurikhin',
        ),
      ],
    ),
    MasterRecipe(
      id: 'omelette_466',
      name: 'Омлет натуральный',
      standardCode: 'Марчук, рец. № 466',
      category: 'Блюда из яиц',
      description: 'Яйца смешивают с молоком и солью, выливают на сковороду со сливочным маслом и запекают при 180°C.',
      expectedYieldGrams: 145.0,
      culinaryProcess: 'Запекание',
      ingredients: [
        MasterIngredientItem(
          productId: 159,
          name: 'Яйцо куриное',
          weightGrams: 110.0,
          isGross: false,
          wastePct: 13.0,
          protein: 12.7,
          fat: 11.5,
          carbs: 0.7,
          kcal: 157.0,
          source: 'skurikhin',
        ),
        MasterIngredientItem(
          productId: 53,
          name: 'Молоко пастеризованное 3,2% жирности',
          weightGrams: 35.0,
          isGross: false,
          wastePct: 0.0,
          protein: 2.9,
          fat: 3.2,
          carbs: 4.7,
          kcal: 60.0,
          source: 'skurikhin',
        ),
        MasterIngredientItem(
          productId: 509,
          name: 'Масло сливочное несоленое «Крестьянское»',
          weightGrams: 10.0,
          isGross: false,
          wastePct: 0.0,
          protein: 0.8,
          fat: 72.5,
          carbs: 1.3,
          kcal: 661.0,
          source: 'skurikhin',
        ),
      ],
    ),
  ];
}
