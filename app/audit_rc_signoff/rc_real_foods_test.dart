import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/calculation_engine.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/product.dart';
void main(){
 final foods=(jsonDecode(File('../audit_artifacts/rc_signoff_20261016/real_zero_foods.json').readAsStringSync()) as List).cast<Map<String,dynamic>>();
 for(final food in foods){for(final mass in [0.0,0.1]){
  test('Real database ${food['code']} mass=$mass',(){
   final dish=Dish(id:'real',createdAt:DateTime(2026),updatedAt:DateTime(2026),ingredients:[Ingredient(id:'real',weightGrams:mass,product:Product.fromMap(food))]);
   final c=CalculationEngine.calculate(dish);
   expect([c.cookedKcal,c.per100gKcal,c.per100gProtein,c.per100gFat,c.per100gCarbs,c.yieldGrams].every((v)=>v.isFinite),isTrue);
   if(mass==0)expect(c.per100gKcal,0);
  });
 }}
}
