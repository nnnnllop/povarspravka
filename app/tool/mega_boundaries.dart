import 'dart:convert';
import 'dart:io';
import '../lib/core/calculation/calculation_engine.dart';
import '../lib/core/calculation/models/dish.dart';
import '../lib/core/calculation/models/ingredient.dart';
import '../lib/core/calculation/models/product.dart';

void main() {
 var rejected=0,accepted=0;
 final now=DateTime.utc(2026);
 const p=Product(id:1,code:'boundary',name:'Boundary',groupId:1,source:'usda',protein:10,fat:10,carbs:10,kcal:170);
 Dish dish(double mass)=>Dish(id:'boundary',ingredients:[Ingredient(id:'i',product:p,weightGrams:mass)],createdAt:now,updatedAt:now);
 final values=<double>[double.nan,double.infinity,double.negativeInfinity,-1,2147483647,2147483648,9223372036854775807.toDouble(),1e308];
 for(final v in values){
  for(final d in [dish(v),dish(100).copyWith(customYieldGrams:v),dish(100).copyWith(retentionProtein:v)]){
   try{CalculationEngine.calculate(d);throw StateError('accepted invalid $v');}on ArgumentError{rejected++;}
  }
 }
 for(final mass in [.001,.1,100000.0,9999999.0]){final r=CalculationEngine.calculate(dish(mass));if(!r.cookedKcal.isFinite||r.cookedKcal<0)throw StateError('bad valid boundary');accepted++;}
 final zeroWaste=dish(100).copyWith(ingredients:[Ingredient(id:'i',product:p.copyWith(wastePct:100),weightGrams:100,isGross:true)]);final r=CalculationEngine.calculate(zeroWaste);if(r.yieldGrams!=0||r.cookedKcal!=0)throw StateError('100 percent waste');accepted++;
 final result={'invalidDomainRejections':rejected,'validBoundaryCases':accepted,'hostScope':'Dart VM Windows x64; no ARM32/ARM64 device execution claimed'};
 File('../audit_artifacts/mega/boundaries_result.json').writeAsStringSync(jsonEncode(result));print(jsonEncode(result));
}
