import '../calculation_math.dart';
import 'blank_mode.dart';
import 'ingredient.dart';

class Dish {
  final String id;
  final String title;
  final bool showTitleInExport;
  final bool showPer100gRowInExport;
  final List<Ingredient> ingredients;
  final double? customYieldGrams; // Пользовательский выход блюда
  final double retentionProtein; // Сохранность белка (0.94)
  final double retentionFat; // Сохранность жира (0.88)
  final double retentionCarbs; // Сохранность углеводов (0.91)
  final BlankMode blankMode;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Dish({
    required this.id,
    this.title = '',
    this.showTitleInExport = false,
    this.showPer100gRowInExport = false,
    this.ingredients = const [],
    this.customYieldGrams,
    this.retentionProtein = 0.94,
    this.retentionFat = 0.88,
    this.retentionCarbs = 0.91,
    this.blankMode = BlankMode.photoCross,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Итоговая масса сырья (нетто), отображаемая в бланке
  double get totalRawNetGrams => CalculationMath.round1(
      ingredients.fold(0.0, (sum, item) => sum + item.netGramsRounded));

  /// Выход готового блюда (пользовательский либо равен сумме сырья)
  double get effectiveYieldGrams =>
      (customYieldGrams != null && customYieldGrams! > 0)
          ? CalculationMath.round1(customYieldGrams!)
          : totalRawNetGrams;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'showTitleInExport': showTitleInExport,
        'showPer100gRowInExport': showPer100gRowInExport,
        'ingredients': ingredients.map((e) => e.toJson()).toList(),
        'customYieldGrams': customYieldGrams,
        'retentionProtein': retentionProtein,
        'retentionFat': retentionFat,
        'retentionCarbs': retentionCarbs,
        'blankMode': blankMode.name,
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

    return Dish(
      id: json['id'] as String? ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      title: json['title'] as String? ?? '',
      showTitleInExport: json['showTitleInExport'] as bool? ?? false,
      showPer100gRowInExport: json['showPer100gRowInExport'] as bool? ?? false,
      ingredients: rawIngredients
          .whereType<Map<String, dynamic>>()
          .map(Ingredient.fromJson)
          .toList(),
      customYieldGrams: (json['customYieldGrams'] as num?)?.toDouble(),
      retentionProtein: (json['retentionProtein'] as num?)?.toDouble() ?? 0.94,
      retentionFat: (json['retentionFat'] as num?)?.toDouble() ?? 0.88,
      retentionCarbs: (json['retentionCarbs'] as num?)?.toDouble() ?? 0.91,
      blankMode: mode,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Dish copyWith({
    String? id,
    String? title,
    bool? showTitleInExport,
    bool? showPer100gRowInExport,
    List<Ingredient>? ingredients,
    double? customYieldGrams,
    bool clearCustomYield = false,
    double? retentionProtein,
    double? retentionFat,
    double? retentionCarbs,
    BlankMode? blankMode,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Dish(
      id: id ?? this.id,
      title: title ?? this.title,
      showTitleInExport: showTitleInExport ?? this.showTitleInExport,
      showPer100gRowInExport:
          showPer100gRowInExport ?? this.showPer100gRowInExport,
      ingredients: ingredients ?? this.ingredients,
      customYieldGrams: clearCustomYield
          ? null
          : (customYieldGrams ?? this.customYieldGrams),
      retentionProtein: retentionProtein ?? this.retentionProtein,
      retentionFat: retentionFat ?? this.retentionFat,
      retentionCarbs: retentionCarbs ?? this.retentionCarbs,
      blankMode: blankMode ?? this.blankMode,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
