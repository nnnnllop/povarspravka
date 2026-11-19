import '../calculation_math.dart';
import '../calculation_validation.dart';
import 'blank_mode.dart';
import 'heat_process.dart';
import 'ingredient.dart';

/// Стандартные категории библиотеки «Мои блюда».
class DishCategories {
  const DishCategories._();

  static const String first = 'first';
  static const String main = 'main';
  static const String side = 'side';
  static const String salad = 'salad';
  static const String sauce = 'sauce';
  static const String bakery = 'bakery';
  static const String drink = 'drink';

  static const List<({String id, String label})> all = [
    (id: first, label: 'Первые'),
    (id: main, label: 'Горячее'),
    (id: side, label: 'Гарниры'),
    (id: salad, label: 'Салаты'),
    (id: sauce, label: 'Соусы и ПФ'),
    (id: bakery, label: 'Выпечка'),
    (id: drink, label: 'Напитки'),
  ];

  static String? normalize(Object? raw) {
    if (raw is! String) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    for (final item in all) {
      if (item.id == trimmed) return item.id;
    }
    return null;
  }

  static String? labelOf(String? id) {
    if (id == null) return null;
    for (final item in all) {
      if (item.id == id) return item.label;
    }
    return null;
  }
}

class Dish {
  final String id;
  final String title;
  final String? category;
  final bool showTitleInExport;
  final bool showPer100gRowInExport;
  final List<Ingredient> ingredients;
  /// Вес готового блюда, введённый поваром (г). Приложение его не угадывает.
  final double? customYieldGrams;

  /// Тройка сохранности Б/Ж/У режима [HeatProcess.legacy] (по умолчанию
  /// [kLegacyRetentionProtein] / [kLegacyRetentionFat] / [kLegacyRetentionCarbs]).
  ///
  /// Для любого другого способа тройка НЕ используется: потери берутся
  /// из таблицы потерь по группе каждого ингредиента (`loss_table.dart`).
  /// Значения хранятся, чтобы возврат в legacy давал прежние числа.
  final double retentionProtein;
  final double retentionFat;
  final double retentionCarbs;
  final BlankMode blankMode;

  /// Способ тепловой обработки блюда: задаёт ТОЛЬКО потери Б/Ж/У.
  ///
  /// [HeatProcess.legacy] — документ старого формата (без ключа `process`):
  /// тройка сохранности и выход = сумма нетто, если вес не введён. Такие
  /// документы читаются и считаются ровно как раньше. Новое блюдо —
  /// [HeatProcess.cold] ([Dish.withProcess]).
  final HeatProcess process;

  final DateTime createdAt;
  final DateTime updatedAt;

  const Dish({
    required this.id,
    this.title = '',
    this.category,
    this.showTitleInExport = false,
    this.showPer100gRowInExport = false,
    this.ingredients = const [],
    this.customYieldGrams,
    this.retentionProtein = kLegacyRetentionProtein,
    this.retentionFat = kLegacyRetentionFat,
    this.retentionCarbs = kLegacyRetentionCarbs,
    this.blankMode = BlankMode.photoCross,
    this.process = HeatProcess.legacy,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Новое блюдо со способом обработки [process].
  ///
  /// Потери считаются по таблице (`LossTable`) для группы каждого
  /// ингредиента; тройка сохранности получает значения legacy по
  /// умолчанию и используется, только если повар переключит блюдо
  /// в [HeatProcess.legacy].
  factory Dish.withProcess({
    required String id,
    required HeatProcess process,
    String title = '',
    String? category,
    List<Ingredient> ingredients = const [],
    double? customYieldGrams,
    BlankMode blankMode = BlankMode.photoCross,
    bool showTitleInExport = false,
    bool showPer100gRowInExport = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    final now = DateTime.now();
    return Dish(
      id: id,
      title: title,
      category: DishCategories.normalize(category),
      showTitleInExport: showTitleInExport,
      showPer100gRowInExport: showPer100gRowInExport,
      ingredients: ingredients,
      customYieldGrams: customYieldGrams,
      blankMode: blankMode,
      process: process,
      createdAt: createdAt ?? now,
      updatedAt: updatedAt ?? now,
    );
  }

  /// Итоговая масса сырья (нетто), отображаемая в бланке
  double get totalRawNetGrams => CalculationMath.sumRounded(
      ingredients.map((item) => item.netGramsRounded), 1);

  /// Вес готового блюда введён поваром и допустим
  /// (≥ [CalculationValidation.minCustomYieldGrams]).
  bool get hasCustomYield {
    final custom = customYieldGrams;
    return custom != null &&
        custom.isFinite &&
        custom >= CalculationValidation.minCustomYieldGrams;
  }

  /// Выход готового блюда (г) — знаменатель «на 100 г» и «на порцию».
  ///
  /// Только вес, введённый поваром ([customYieldGrams]); приложение его не
  /// угадывает (развариваемость, уварка и экстракция удалены вместе с
  /// `yield_physics.dart`, задача 2026-11-03). Веса нет:
  ///  * [HeatProcess.legacy] — сумма нетто, как до упрощения (старые
  ///    документы дают прежние числа);
  ///  * любой другой способ — `0`: результат считается на всё блюдо, а
  ///    вместо «на 100 г» экран просит «укажите вес готового блюда».
  ///
  /// Порог введённого веса — тот же [CalculationValidation.minCustomYieldGrams],
  /// что и у валидатора (RA-23: раньше здесь был свой порог 0,1 г).
  double get effectiveYieldGrams {
    if (hasCustomYield) return CalculationMath.round1(customYieldGrams!);
    return process.isLegacy ? totalRawNetGrams : 0.0;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        if (category != null && category!.isNotEmpty) 'category': category,
        'showTitleInExport': showTitleInExport,
        'showPer100gRowInExport': showPer100gRowInExport,
        'ingredients': ingredients.map((e) => e.toJson()).toList(),
        'customYieldGrams': customYieldGrams,
        'retentionProtein': retentionProtein,
        'retentionFat': retentionFat,
        'retentionCarbs': retentionCarbs,
        'blankMode': blankMode.name,
        // Пишем технологию ТОЛЬКО если она явная: документ старого формата
        // должен оставаться побайтово прежним (тесты совместимости).
        if (!process.isLegacy) 'process': process.name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Dish.fromJson(Map<String, dynamic> json) {
    final rawIngredients = json['ingredients'] as List<dynamic>? ?? const [];
    final modeName = json['blankMode'] as String? ?? BlankMode.photoCross.name;
    final mode = BlankMode.values.firstWhere(
      (m) => m.name == modeName,
      orElse: () => BlankMode.photoCross,
    );
    // Обратная совместимость: нет ключа `process` (или имя неизвестно) →
    // документ старого формата, и он обязан считаться как раньше. Имена
    // промежуточной модели (`soup`, `grain`, `fryMain`) читаются как варка/жарка.
    final process = HeatProcess.fromJsonName(json['process']);

    return Dish(
      id: json['id'] as String? ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      title: json['title'] as String? ?? '',
      category: DishCategories.normalize(json['category']),
      showTitleInExport: json['showTitleInExport'] as bool? ?? false,
      showPer100gRowInExport: json['showPer100gRowInExport'] as bool? ?? false,
      ingredients: rawIngredients
          .whereType<Map<String, dynamic>>()
          .map(Ingredient.fromJson)
          .toList(),
      customYieldGrams: (json['customYieldGrams'] as num?)?.toDouble(),
      retentionProtein: (json['retentionProtein'] as num?)?.toDouble() ??
          kLegacyRetentionProtein,
      retentionFat:
          (json['retentionFat'] as num?)?.toDouble() ?? kLegacyRetentionFat,
      retentionCarbs:
          (json['retentionCarbs'] as num?)?.toDouble() ?? kLegacyRetentionCarbs,
      blankMode: mode,
      process: process,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Dish copyWith({
    String? id,
    String? title,
    String? category,
    bool clearCategory = false,
    bool? showTitleInExport,
    bool? showPer100gRowInExport,
    List<Ingredient>? ingredients,
    double? customYieldGrams,
    bool clearCustomYield = false,
    double? retentionProtein,
    double? retentionFat,
    double? retentionCarbs,
    BlankMode? blankMode,
    HeatProcess? process,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Dish(
      id: id ?? this.id,
      title: title ?? this.title,
      category: clearCategory
          ? null
          : (category != null
              ? DishCategories.normalize(category)
              : this.category),
      showTitleInExport: showTitleInExport ?? this.showTitleInExport,
      showPer100gRowInExport:
          showPer100gRowInExport ?? this.showPer100gRowInExport,
      ingredients: ingredients ?? this.ingredients,
      customYieldGrams:
          clearCustomYield ? null : (customYieldGrams ?? this.customYieldGrams),
      retentionProtein: retentionProtein ?? this.retentionProtein,
      retentionFat: retentionFat ?? this.retentionFat,
      retentionCarbs: retentionCarbs ?? this.retentionCarbs,
      blankMode: blankMode ?? this.blankMode,
      process: process ?? this.process,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
