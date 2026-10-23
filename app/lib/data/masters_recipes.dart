import '../core/calculation/models/dish.dart';
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
  final double retentionProtein;
  final double retentionFat;
  final double retentionCarbs;
  final String culinaryProcess;
  final List<MasterIngredientItem> ingredients;

  const MasterRecipe({
    required this.id,
    required this.name,
    required this.standardCode,
    required this.category,
    required this.description,
    required this.expectedYieldGrams,
    this.retentionProtein = 0.94,
    this.retentionFat = 0.88,
    this.retentionCarbs = 0.91,
    required this.culinaryProcess,
    required this.ingredients,
  });

  /// Создает объект Dish, готовый для расчета в калькуляторе
  Dish toDish() {
    final now = DateTime.now();
    return Dish(
      id: 'master_${id}_${now.millisecondsSinceEpoch}',
      title: name,
      customYieldGrams: expectedYieldGrams,
      showTitleInExport: true,
      retentionProtein: retentionProtein,
      retentionFat: retentionFat,
      retentionCarbs: retentionCarbs,
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

  Ingredient toIngredient() {
    final product = Product(
      id: productId,
      code: '$productId',
      groupId: 1,
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
      description: 'Классический борщ по 2-й колонке сборника рецептур. Потери при варке 15-20%, сохранность 94/88/91%.',
      expectedYieldGrams: 1000.0,
      retentionProtein: 0.94,
      retentionFat: 0.88,
      retentionCarbs: 0.91,
      culinaryProcess: 'Варка супов',
      ingredients: [
        MasterIngredientItem(
          productId: 80105012,
          name: 'Свекла',
          weightGrams: 200.0,
          isGross: true,
          wastePct: 20.0,
          protein: 1.5,
          fat: 0.1,
          carbs: 8.8,
          kcal: 42.0,
        ),
        MasterIngredientItem(
          productId: 801020101,
          name: 'Капуста белокочанная свежая',
          weightGrams: 150.0,
          isGross: true,
          wastePct: 20.0,
          protein: 1.8,
          fat: 0.1,
          carbs: 4.7,
          kcal: 27.0,
        ),
        MasterIngredientItem(
          productId: 80104001,
          name: 'Картофель',
          weightGrams: 160.0,
          isGross: true,
          wastePct: 25.0,
          protein: 2.0,
          fat: 0.4,
          carbs: 16.3,
          kcal: 77.0,
        ),
        MasterIngredientItem(
          productId: 80105001,
          name: 'Морковь красная',
          weightGrams: 50.0,
          isGross: true,
          wastePct: 20.0,
          protein: 1.3,
          fat: 0.1,
          carbs: 6.9,
          kcal: 35.0,
        ),
        MasterIngredientItem(
          productId: 80103001,
          name: 'Лук репчатый',
          weightGrams: 48.0,
          isGross: true,
          wastePct: 16.0,
          protein: 1.4,
          fat: 0.2,
          carbs: 8.2,
          kcal: 41.0,
        ),
        MasterIngredientItem(
          productId: 12020005,
          name: 'Томатная паста 25-28%',
          weightGrams: 30.0,
          isGross: false,
          wastePct: 0.0,
          protein: 4.8,
          fat: 0.0,
          carbs: 19.0,
          kcal: 102.0,
        ),
        MasterIngredientItem(
          productId: 5040001,
          name: 'Масло подсолнечное',
          weightGrams: 20.0,
          isGross: false,
          wastePct: 0.0,
          protein: 0.0,
          fat: 99.9,
          carbs: 0.0,
          kcal: 899.0,
        ),
        MasterIngredientItem(
          productId: 10070001,
          name: 'Сахар-песок',
          weightGrams: 10.0,
          isGross: false,
          wastePct: 0.0,
          protein: 0.0,
          fat: 0.0,
          carbs: 99.8,
          kcal: 399.0,
        ),
        MasterIngredientItem(
          productId: 13010001,
          name: 'Вода питьевая',
          weightGrams: 700.0,
          isGross: false,
          wastePct: 0.0,
          protein: 0.0,
          fat: 0.0,
          carbs: 0.0,
          kcal: 0.0,
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
      retentionProtein: 0.94,
      retentionFat: 0.88,
      retentionCarbs: 0.91,
      culinaryProcess: 'Варка / припускание',
      ingredients: [
        MasterIngredientItem(
          productId: 80104001,
          name: 'Картофель',
          weightGrams: 320.0,
          isGross: true,
          wastePct: 25.0, // 240 г нетто
          protein: 2.0,
          fat: 0.4,
          carbs: 16.3,
          kcal: 77.0,
        ),
        MasterIngredientItem(
          productId: 10101001,
          name: 'Молоко пастеризованное 3,2% жирности',
          weightGrams: 38.0,
          isGross: false,
          wastePct: 0.0,
          protein: 2.9,
          fat: 3.2,
          carbs: 4.7,
          kcal: 59.0,
        ),
        MasterIngredientItem(
          productId: 5010005,
          name: 'Масло сливочное несоленое «Крестьянское»',
          weightGrams: 15.0,
          isGross: false,
          wastePct: 0.0,
          protein: 0.8,
          fat: 72.5,
          carbs: 1.4,
          kcal: 661.0,
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
      retentionProtein: 0.94,
      retentionFat: 0.88,
      retentionCarbs: 0.91,
      culinaryProcess: 'Варка каш',
      ingredients: [
        MasterIngredientItem(
          productId: 60101001,
          name: 'Крупа гречневая ядрица',
          weightGrams: 100.0,
          isGross: false,
          wastePct: 0.0,
          protein: 12.6,
          fat: 3.3,
          carbs: 62.1,
          kcal: 313.0,
        ),
        MasterIngredientItem(
          productId: 13010001,
          name: 'Вода питьевая',
          weightGrams: 150.0,
          isGross: false,
          wastePct: 0.0,
          protein: 0.0,
          fat: 0.0,
          carbs: 0.0,
          kcal: 0.0,
        ),
        MasterIngredientItem(
          productId: 5010005,
          name: 'Масло сливочное несоленое «Крестьянское»',
          weightGrams: 10.0,
          isGross: false,
          wastePct: 0.0,
          protein: 0.8,
          fat: 72.5,
          carbs: 1.4,
          kcal: 661.0,
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
      retentionProtein: 0.92,
      retentionFat: 0.95,
      retentionCarbs: 0.93,
      culinaryProcess: 'Жарка основным способом',
      ingredients: [
        MasterIngredientItem(
          productId: 30101001,
          name: 'Говядина 1 категории',
          weightGrams: 90.0,
          isGross: false,
          wastePct: 0.0,
          protein: 18.6,
          fat: 16.0,
          carbs: 0.0,
          kcal: 218.0,
        ),
        MasterIngredientItem(
          productId: 30301001,
          name: 'Свинина мясная',
          weightGrams: 50.0,
          isGross: false,
          wastePct: 0.0,
          protein: 14.6,
          fat: 33.0,
          carbs: 0.0,
          kcal: 355.0,
        ),
        MasterIngredientItem(
          productId: 110101001,
          name: 'Хлеб пшеничный из муки 1 сорта',
          weightGrams: 28.0,
          isGross: false,
          wastePct: 0.0,
          protein: 7.7,
          fat: 1.2,
          carbs: 48.3,
          kcal: 242.0,
        ),
        MasterIngredientItem(
          productId: 13010001,
          name: 'Вода питьевая',
          weightGrams: 35.0,
          isGross: false,
          wastePct: 0.0,
          protein: 0.0,
          fat: 0.0,
          carbs: 0.0,
          kcal: 0.0,
        ),
        MasterIngredientItem(
          productId: 5040001,
          name: 'Масло подсолнечное',
          weightGrams: 10.0,
          isGross: false,
          wastePct: 0.0,
          protein: 0.0,
          fat: 99.9,
          carbs: 0.0,
          kcal: 899.0,
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
      retentionProtein: 0.92,
      retentionFat: 0.95,
      retentionCarbs: 0.93,
      culinaryProcess: 'Жарка основным способом',
      ingredients: [
        MasterIngredientItem(
          productId: 10401001,
          name: 'Творог полужирный 9% жирности',
          weightGrams: 150.0,
          isGross: false,
          wastePct: 0.0,
          protein: 16.7,
          fat: 9.0,
          carbs: 2.0,
          kcal: 159.0,
        ),
        MasterIngredientItem(
          productId: 60201001,
          name: 'Мука пшеничная высшего сорта',
          weightGrams: 22.0,
          isGross: false,
          wastePct: 0.0,
          protein: 10.3,
          fat: 1.1,
          carbs: 70.6,
          kcal: 334.0,
        ),
        MasterIngredientItem(
          productId: 20101001,
          name: 'Яйцо куриное',
          weightGrams: 12.0, // четверть яйца
          isGross: false,
          wastePct: 0.0,
          protein: 12.7,
          fat: 11.5,
          carbs: 0.7,
          kcal: 157.0,
        ),
        MasterIngredientItem(
          productId: 10070001,
          name: 'Сахар-песок',
          weightGrams: 15.0,
          isGross: false,
          wastePct: 0.0,
          protein: 0.0,
          fat: 0.0,
          carbs: 99.8,
          kcal: 399.0,
        ),
        MasterIngredientItem(
          productId: 5010005,
          name: 'Масло сливочное несоленое «Крестьянское»',
          weightGrams: 10.0,
          isGross: false,
          wastePct: 0.0,
          protein: 0.8,
          fat: 72.5,
          carbs: 1.4,
          kcal: 661.0,
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
      retentionProtein: 0.92,
      retentionFat: 0.90,
      retentionCarbs: 0.95,
      culinaryProcess: 'Запекание',
      ingredients: [
        MasterIngredientItem(
          productId: 20101001,
          name: 'Яйцо куриное',
          weightGrams: 110.0, // 2-3 яйца
          isGross: false,
          wastePct: 0.0,
          protein: 12.7,
          fat: 11.5,
          carbs: 0.7,
          kcal: 157.0,
        ),
        MasterIngredientItem(
          productId: 10101001,
          name: 'Молоко пастеризованное 3,2% жирности',
          weightGrams: 35.0,
          isGross: false,
          wastePct: 0.0,
          protein: 2.9,
          fat: 3.2,
          carbs: 4.7,
          kcal: 59.0,
        ),
        MasterIngredientItem(
          productId: 5010005,
          name: 'Масло сливочное несоленое «Крестьянское»',
          weightGrams: 10.0,
          isGross: false,
          wastePct: 0.0,
          protein: 0.8,
          fat: 72.5,
          carbs: 1.4,
          kcal: 661.0,
        ),
      ],
    ),
  ];
}
