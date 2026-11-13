// Independent audit 3. Literal expectations transcribed from MR appendix 4,
// not read from COEFFICIENT_SOURCES or the application's loss constants.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/calculation_engine.dart';
import 'package:povarspravka/core/calculation/calculation_math.dart';
import 'package:povarspravka/core/calculation/loss_table.dart';
import 'package:povarspravka/core/calculation/food_classifier.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/product.dart';
import 'package:povarspravka/core/calculation/models/heat_process.dart';
import 'package:povarspravka/core/calculation/models/loss_group.dart';
import 'package:povarspravka/presentation/providers/dish_provider.dart';

Product product({String name='Говядина сырая',int group=3,double p=20,double f=10,double c=30,double waste=0,bool ready=false}) => Product(id:90001,code:'audit3',name:name,groupId:group,source:'audit3',protein:p,fat:f,carbs:c,kcal:999,wastePct:waste,isDish:ready);
Ingredient ing({String id='a',Product? item,double grams=100,bool gross=false,LossGroup? group,HeatProcess? process}) => Ingredient(id:id,product:item??product(),weightGrams:grams,isGross:gross,groupOverride:group,processOverride:process);
Dish dish({HeatProcess process=HeatProcess.boil,List<Ingredient>? items,double? weight}) => Dish.withProcess(id:'audit3',process:process,ingredients:items??[ing()],customYieldGrams:weight,createdAt:DateTime.utc(2025),updatedAt:DateTime.utc(2025));
List<double> macros(Dish d) { final r=CalculationEngine.calculate(d);return [r.cookedProtein,r.cookedFat,r.cookedCarbs,r.cookedKcal]; }
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 final source=<String,List<num>>{
 'boil/meat':[10,25,0], 'boil/fish':[10,10,0],
 'boil/grainPasta':[2,2,5], 'boil/legumes':[2,2,5], 'boil/rootTuber':[2,2,5], 'boil/vegetable':[2,2,2], 'boil/fruitBerry':[2,2,2], 'boil/flourBread':[2,2,5],
 'stew/meat':[5,5,0],
 'fry/meat':[10,30,0], 'fry/fish':[10,20,0], 'fry/grainPasta':[5,10,10], 'fry/legumes':[5,10,10], 'fry/rootTuber':[5,10,10], 'fry/vegetable':[5,10,20], 'fry/fruitBerry':[5,10,20], 'fry/flourBread':[5,10,10], 'bake/dairy':[5,5,5]};
 for(final e in source.entries){test('S01 source ${e.key}',(){final k=e.key.split('/');final l=LossTable.lossFor(LossGroup.values.byName(k[1]),HeatProcess.values.byName(k[0]));expect([l.protein,l.fat,l.carbs],e.value);expect(l.unverified,isEmpty);});}
 for(final g in LossGroup.values){test('B01 cold exact ${g.name}',(){expect(macros(dish(process:HeatProcess.cold,items:[ing(group:g)])),[20,10,30,290]);});}
 test('B02 mixed ingredient process exact',(){final d=dish(items:[ing(),ing(id:'b',item:product(name:'Капуста',group:8,p:2,f:1,c:9),grams:200,process:HeatProcess.fry)]);expect(macros(d),[21.8,9.3,44.4,348.5]);});
 test('B03 legacy exact historic coefficients',(){expect(macros(dish(process:HeatProcess.legacy)),[18.8,8.8,27.3,263.6]);});
 test('B04 legacy custom coefficients retained',(){expect(macros(dish(process:HeatProcess.legacy).copyWith(retentionProtein:.5,retentionFat:.25,retentionCarbs:.75)),[10,2.5,22.5,152.5]);});
 test('B05 no yield undefined per100 and portion',(){final r=CalculationEngine.calculate(dish());expect(r.yieldGrams,0);expect(r.hasYield,isFalse);expect(()=>r.portion(100),throwsStateError);});
 test('B06 per100 explicit weight',(){final r=CalculationEngine.calculate(dish(weight:200));expect([r.per100gProtein,r.per100gFat,r.per100gCarbs,r.per100gKcal],[9,3.75,15,129.8]);});
 test('B07 portion exact',(){final r=CalculationEngine.calculate(dish(weight:200)).portion(50);expect([r.protein,r.fat,r.carbs,r.kcal],[4.5,1.88,7.5,64.9]);});
 for(final x in [0.0,.1,-1.0,double.nan,double.infinity,10000000.0]){test('B08 invalid yield $x rejected',(){expect(()=>CalculationEngine.calculate(dish(weight:x)),throwsArgumentError);});}
 test('B09 large valid yield',(){final r=CalculationEngine.calculate(dish(weight:9999999));expect(r.hasYield,isTrue);expect(r.per100gProtein,0);});
 test('B10 yield less than nutrients is input not crash',(){final r=CalculationEngine.calculate(dish(weight:1));expect(r.per100gProtein,1800);});
 test('B11 gross net before losses',(){expect(macros(dish(items:[ing(item:product(waste:25),gross:true,grams:200)])),[27,11.25,45,389.3]);});
 test('B12 gross inverse precision',(){expect(Ingredient.netFromGross(200,25),150);expect(Ingredient.grossFromNet(150,25),200);});
 test('B13 deterministic and permutation',(){final a=ing(grams:137.3);final b=ing(id:'b',grams:91.7);final x=macros(dish(items:[a,b]));expect(macros(dish(items:[b,a])),x);expect(macros(dish(items:[a,b])),x);});
 test('B14 round half up',(){expect(CalculationMath.round2(2.675),2.68);expect(CalculationMath.round1(.15),.2);});
 test('B15 idempotent JSON save load save',(){final d=dish(items:[ing(group:LossGroup.fish,process:HeatProcess.steam)],weight:180);final j=jsonEncode(d.toJson());expect(jsonEncode(Dish.fromJson(jsonDecode(j)).toJson()),j);expect(macros(Dish.fromJson(jsonDecode(j))),macros(d));});
 test('B16 ready product no double heat',(){expect(macros(dish(items:[ing(item:product(ready:true))])),[20,10,30,290]);});
 test('B17 ready explicit heat overrides',(){expect(macros(dish(items:[ing(item:product(ready:true),process:HeatProcess.fry)])),[18,7,30,255]);});
 test('B18 group override affects numbers',(){expect(macros(dish(items:[ing(group:LossGroup.fish)])),[18,9,30,273]);});
 test('B19 dish process preserves ingredient override',(){final a=ing(process:HeatProcess.fry);expect(macros(dish(process:HeatProcess.boil,items:[a])),macros(dish(process:HeatProcess.steam,items:[a])));});
 for(final field in ['protein','fat','carbs','waste_pct']){for(final x in [-1.0,double.nan,double.infinity]){test('B20 invalid $field $x',(){final m=product().toJson();m[field]=x;final p=Product.fromJson(m);expect(()=>CalculationEngine.calculate(dish(items:[ing(item:p)])),throwsArgumentError);});}}
 test('B21 nonfinite weight rejected',(){expect(()=>CalculationEngine.calculate(dish(items:[ing(grams:double.nan)])),throwsArgumentError);});
 test('B22 all 84 cells and percent bounds',(){expect(LossTable.table.length,6);for(final row in LossTable.table.values){expect(row.keys.toSet(),LossGroup.values.toSet());for(final l in row.values){for(final n in [l.protein,l.fat,l.carbs]){expect(n,inInclusiveRange(0,100));}}}});
 test('B23 known group ids not name substrings',(){expect(FoodClassifier.classifyRaw(3,'Свинина жирная'),LossGroup.meat);expect(FoodClassifier.classifyRaw(9,'Инжир'),LossGroup.fruitBerry);expect(FoodClassifier.classifyRaw(8,'Капуста сырая'),LossGroup.vegetable);expect(FoodClassifier.classifyRaw(1,'Сыр российский'),LossGroup.dairy);expect(FoodClassifier.classifyRaw(3,'Говядина нежирная'),LossGroup.meat);});
 test('B24 unknown and empty group fallback',(){expect(FoodClassifier.classifyRaw(987654,'Говядина'),LossGroup.meat);expect(FoodClassifier.classifyRaw(0,''),LossGroup.other);expect(Product.fromMap({'id':1,'code':'x','name':'Соль','group_id':null,'protein':0,'fat':0,'carbs':0}).groupId,0);});
 test('B25 notifier new cold and reset cold',()async{final n=DishNotifier();addTearDown(n.dispose);await n.flushPendingSaves();expect(n.state.process,HeatProcess.cold);n.setHeatProcess(HeatProcess.fry);n.createNewDish();expect(n.state.process,HeatProcess.cold);await n.flushPendingSaves();});
 test('B26 notifier invalid and cleared weight',()async{final n=DishNotifier();addTearDown(n.dispose);await n.flushPendingSaves();n.setCustomYield(200);n.setCustomYield(0);expect(n.state.customYieldGrams,200);n.setCustomYield(null);expect(n.state.customYieldGrams,isNull);await n.flushPendingSaves();});
 test('B27 stock literal arithmetic',(){expect(macros(dish(process:HeatProcess.stock)),[2,2.5,0,30.5]);});
 test('B28 cold zero nutrients',(){expect(macros(dish(process:HeatProcess.cold,items:[ing(item:product(p:0,f:0,c:0))])),[0,0,0,0]);});
 test('B29 legacy old JSON no process',(){final j=dish(process:HeatProcess.legacy).toJson();expect(j.containsKey('process'),isFalse);final d=Dish.fromJson(j);expect(d.process,HeatProcess.legacy);expect(d.effectiveYieldGrams,100);expect(macros(d),[18.8,8.8,27.3,263.6]);});
 test('B30 line sum cooked macros',(){final r=CalculationEngine.calculate(dish(items:[ing(),ing(id:'b',grams:11.1)]));expect(r.cookedProtein,CalculationMath.sumRounded(r.lines.map((x)=>x.cookedProtein),2));expect(r.cookedFat,CalculationMath.sumRounded(r.lines.map((x)=>x.cookedFat),2));expect(r.cookedCarbs,CalculationMath.sumRounded(r.lines.map((x)=>x.cookedCarbs),2));});
 test('S02 flags 18 fully 1 partial 65 unverified',(){final cells=LossTable.table.values.expand((x)=>x.values).toList();expect(cells.where((x)=>x.unverified.isEmpty).length,18);expect(cells.where((x)=>x.unverified.length==3).length,65);expect(cells.where((x)=>x.unverified.isNotEmpty&&x.unverified.length<3).length,1);});
}
