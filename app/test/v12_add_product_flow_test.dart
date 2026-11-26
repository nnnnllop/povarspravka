import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/heat_process.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/product.dart';
import 'package:povarspravka/core/theme/app_theme.dart';
import 'package:povarspravka/data/repositories/dish_storage_repository.dart';
import 'package:povarspravka/data/repositories/product_repository.dart';
import 'package:povarspravka/presentation/providers/dish_provider.dart';
import 'package:povarspravka/presentation/providers/search_provider.dart';
import 'package:povarspravka/presentation/screens/recipe_editor_screen.dart';
import 'package:povarspravka/presentation/screens/search_product_modal.dart';
import 'package:povarspravka/presentation/widgets/custom_numpad.dart';

const _potato = Product(
  id: 101,
  code: '01-101',
  name: 'Картофель',
  groupId: 1,
  source: 'skurikhin',
  wastePct: 20,
  protein: 2.0,
  fat: 0.4,
  carbs: 16.3,
  kcal: 77,
);

const _carrot = Product(
  id: 102,
  code: '01-102',
  name: 'Морковь',
  groupId: 1,
  source: 'skurikhin',
  wastePct: 20,
  protein: 1.3,
  fat: 0.1,
  carbs: 6.9,
  kcal: 35,
);

const _readyDish = Product(
  id: 201,
  code: 'd-201',
  name: 'Борщ готовый',
  groupId: 2,
  source: 'skurikhin',
  wastePct: 0,
  protein: 1.8,
  fat: 2.2,
  carbs: 5.4,
  kcal: 49,
  isDish: true,
);

class _FakeRepo extends ProductRepository {
  @override
  Future<List<Product>> searchProducts({
    required String query,
    int? groupId,
    String? source,
    bool? isDish,
    int limit = 50,
  }) async {
    final items = [_potato, _carrot, _readyDish];
    return items.where((p) {
      if (isDish != null && p.isDishOnly != isDish) return false;
      if (source != null && source.isNotEmpty && p.source != source) {
        return false;
      }
      if (query.trim().isEmpty) return false;
      return p.name.toLowerCase().contains(query.trim().toLowerCase());
    }).toList();
  }

  @override
  Future<List<FoodGroup>> getFoodGroups({bool? isDish}) async => [
        const FoodGroup(id: 1, code: 'veg', name: 'Овощи'),
        const FoodGroup(id: 2, code: 'dish', name: 'Блюда'),
      ];

  @override
  Future<List<ProductNutrient>> getNutrientsForProduct(int id) async => [];
}

class _FakeStorage extends DishStorageRepository {
  final DishStorageData data;
  _FakeStorage(this.data);

  @override
  Future<DishStorageData> loadAll() async => data;

  @override
  Future<void> saveAll({
    required Dish? activeDraft,
    required List<Dish> savedDishes,
  }) async {}
}

void main() {
  testWidgets(
      'v1.2 multi-add flow: compact filters, recent list, modal numpad, sticky Done(N)',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = _FakeRepo();
    final savedDish = Dish.withProcess(
      id: 'saved-1',
      title: 'Суп овощной',
      process: HeatProcess.boil,
      ingredients: const [
        Ingredient(id: 's1', product: _carrot, weightGrams: 100),
      ],
    );
    final storage = _FakeStorage(DishStorageData(
      activeDraft: Dish.withProcess(id: 'draft-1', process: HeatProcess.boil),
      savedDishes: [savedDish],
    ));

    await tester.pumpWidget(ProviderScope(
      overrides: [
        dishStorageRepositoryProvider.overrideWithValue(storage),
        productRepositoryProvider.overrideWithValue(repo),
        searchProvider.overrideWith((ref) => SearchNotifier(repo)),
        sourceCountsProvider.overrideWith((ref) async => const SourceCounts(
              skurikhin: 2,
              bls: 1,
            )),
        productNutrientsProvider.overrideWith((ref, id) async => const []),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const RecipeEditorScreen(),
      ),
    ));
    await tester.pumpAndSettle();

    // Открываем модалку добавления продуктов из редактора.
    await tester.tap(find.text('Добавить продукт'));
    await tester.pumpAndSettle();

    expect(find.byType(SearchProductModal), findsOneWidget);
    // Сегментированные «стены» убраны в пользу компактных чипов фильтра.
    expect(find.byType(SegmentedButton<bool?>), findsNothing);
    expect(find.byType(SegmentedButton<String?>), findsNothing);
    expect(find.text('Продукты'), findsOneWidget);
    expect(find.text('Готовые'), findsOneWidget);
    expect(find.byKey(const ValueKey('search-filters-btn')), findsOneWidget);

    // Секция «Недавние и частые» видна сразу при пустом запросе и уважает
    // фильтр «Продукты» (isDish == false): _carrot попадает, _readyDish — нет.
    expect(find.text('Недавние и частые'), findsOneWidget);
    expect(find.text('Морковь'), findsOneWidget);
    expect(find.text('Борщ готовый'), findsNothing);

    // Поиск → выбор продукта → отдельный CustomNumpadSheet → подтверждение.
    await tester.enterText(
      find.descendant(
        of: find.byType(SearchProductModal),
        matching: find.byType(TextField),
      ),
      'картоф',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('Картофель'), findsOneWidget);

    await tester.tap(find.text('Картофель'));
    await tester.pumpAndSettle();

    expect(find.byType(CustomNumpadSheet), findsOneWidget);
    await tester.tap(find.text('Добавить'));
    await tester.pumpAndSettle();

    // После добавления numpad закрылся, а модалка поиска осталась открытой
    // с обновлённым футером «Добавлено» и кнопкой «Готово · 1».
    expect(find.byType(CustomNumpadSheet), findsNothing);
    expect(find.byType(SearchProductModal), findsOneWidget);
    expect(find.textContaining('Добавлено: Картофель'), findsOneWidget);
    expect(find.text('Готово · 1'), findsOneWidget);

    // Возврат к редактору по «Готово · 1».
    await tester.tap(find.text('Готово · 1'));
    await tester.pumpAndSettle();

    expect(find.byType(SearchProductModal), findsNothing);
    expect(find.text('Картофель'), findsOneWidget);
  });

  test('buildRecentProducts ranks session picks first and filters by type/source',
      () {
    final recent = buildRecentProducts(
      sessionRecent: const [_carrot],
      activeIngredients: const [_potato],
      savedDishIngredients: const [
        [_potato, _readyDish],
        [_potato],
      ],
      isDishFilter: false,
      selectedSource: 'skurikhin',
    );

    expect(recent.map((p) => p.id).toList(), [_carrot.id, _potato.id]);
    expect(recent.any((p) => p.isDishOnly), isFalse);
  });
}
