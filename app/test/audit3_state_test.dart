// Regression requirements. U01 is expected to fail until persistence is visible.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/calculation_engine.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/presentation/providers/dish_provider.dart';
import 'package:povarspravka/presentation/screens/recipe_editor_screen.dart';
import 'reaudit_state_support.dart';
class Audit3FailStorage extends RecordingStorage {
 @override Future<void> saveAll({required Dish? activeDraft,required List<Dish> savedDishes})async{throw const FileSystemException('AUDIT3 disk full');}
}
void main(){TestWidgetsFlutterBinding.ensureInitialized();
 testWidgets('U01 failed autosave must be visible to cook', (tester)async{phoneSize(tester);final n=DishNotifier(storage:Audit3FailStorage());await n.flushPendingSaves();final h=Harness(dish:n);await tester.pumpWidget(h.wrap(const RecipeEditorScreen()));await tester.pumpAndSettle();n.addIngredient(beet,100);await tester.pump();await expectLater(n.flushPendingSaves(),throwsA(isA<FileSystemException>()));await tester.pumpAndSettle();expect(n.lastPersistenceError,isA<FileSystemException>());expect(CalculationEngine.calculate(n.state).cookedProtein,greaterThan(0));final text=visibleText(tester);print('AUDIT3_U01 visible=$text');expect(RegExp('не удалось сохран|ошибка сохран|не сохранён|не сохранен',caseSensitive:false).hasMatch(text),isTrue,reason:'Failed autosave must not be debugPrint-only');});
 test('U02 edit before load and undo ingredient retains content',()async{final s=SlowLoadStorage(stored:healthyDish());final n=DishNotifier(storage:s);addTearDown(n.dispose);n.addIngredient(beet,200);s.releaseLoad();await n.flushPendingSaves();expect(n.state.ingredients.single.weightGrams,200);final a=n.state.ingredients.single;n.removeIngredient(a.id);n.restoreIngredient(a,0);await n.flushPendingSaves();expect(n.state.ingredients.single.id,a.id);expect(n.state.ingredients.single.weightGrams,200);});
}
