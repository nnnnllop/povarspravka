// Same test executes against current source and the recorded HEAD in an isolated TEMP clone.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/calculation_engine.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
void main(){TestWidgetsFlutterBinding.ensureInitialized();final old=Platform.environment['AUDIT3_OLD']=='1';
test('DG01 real historical decoder round trip of new fields',()async{final j=<String,dynamic>{'id':'audit3-downgrade','title':'new document','process':'cold','customYieldGrams':200,'createdAt':'2025-01-01T00:00:00.000Z','updatedAt':'2025-01-01T00:00:00.000Z','ingredients':[{'id':'i','weightGrams':100,'isGross':false,'group':'fish','process':'steam','product':{'id':90001,'code':'a3','name':'Говядина сырая','group_id':3,'source':'audit3','protein':20,'fat':10,'carbs':30,'kcal':290,'waste_pct':0}}]};final d=Dish.fromJson(j);final round=d.toJson();final r=CalculationEngine.calculate(d);final actual=[r.cookedProtein,r.cookedFat,r.cookedCarbs,r.cookedKcal];expect(actual,old?[18.8,8.8,27.3,263.6]:[18,9,30,273]);expect(round.containsKey('process'),!old);expect((round['ingredients'] as List).single.containsKey('group'),!old);final out=Platform.environment['AUDIT3_OUT'];if(out!=null)await File('$out/downgrade_${old?'old':'current'}.json').writeAsString(jsonEncode({'old':old,'round':round,'actual':actual}));});}
