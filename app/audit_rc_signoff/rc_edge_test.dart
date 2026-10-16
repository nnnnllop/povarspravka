import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/calculation_engine.dart';
import 'package:povarspravka/core/calculation/models/blank_mode.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/product.dart';
import 'package:povarspravka/core/export/pdf_blank_generator.dart';
import 'package:povarspravka/core/export/docx_blank_generator.dart';
import 'package:povarspravka/core/export/xlsx_blank_generator.dart';
import 'package:archive/archive.dart';

final out = Directory('../audit_artifacts/rc_signoff_20261016/edges');
Dish fixture(double weight,{bool zero=false,double retention=1,BlankMode mode=BlankMode.photoCross}) => Dish(
 id:'rc',title:'Суп "Мясо & Овощи" <Детский> \'',showTitleInExport:true,showPer100gRowInExport:true,
 retentionProtein:retention,retentionFat:retention,retentionCarbs:retention,blankMode:mode,
 createdAt:DateTime(2026,10,16),updatedAt:DateTime(2026,10,16),
 ingredients:[Ingredient(id:'rc1',weightGrams:weight,product:Product(id:1,code:zero?'12.1.1':'rc',name:'Продукт 1 " & < > \'',groupId:1,source:'skurikhin',protein:zero?0:100,fat:0,carbs:0,kcal:zero?0:400))]);
String sheet(Dish dish) { final zip=ZipDecoder().decodeBytes(XlsxBlankGenerator.generate(dish));return utf8.decode(zip.findFile('xl/worksheets/sheet1.xml')!.content as List<int>);}
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 setUpAll(()async{await out.create(recursive:true);});
 for(final mass in [0.0,0.1,99999.0]){
  for(final zero in [true,false]){
   test('Finite calculations mass=$mass zero=$zero',(){final c=CalculationEngine.calculate(fixture(mass,zero:zero));expect([c.per100gProtein,c.per100gFat,c.per100gCarbs,c.per100gKcal,c.yieldGrams].every((v)=>v.isFinite),isTrue);if(zero)expect(c.per100gKcal,0);});
  }
 }
 for(final retention in [0.0,1.0]){
  test('Retention $retention',(){final c=CalculationEngine.calculate(fixture(100,retention:retention));expect(c.cookedProtein,100*retention);expect(c.cookedKcal,400*retention);});
 }
 for(final mode in BlankMode.values){
  for(final entry in {'zero':fixture(0,zero:true,mode:mode),'micro':fixture(.1,zero:true,mode:mode),'high':fixture(99999,mode:mode),'round':fixture(.15,mode:mode),'ret0':fixture(100,retention:0,mode:mode),'ret1':fixture(100,mode:mode),'standard':fixture(100,mode:mode).copyWith(retentionProtein:.94,retentionFat:.88,retentionCarbs:.91)}.entries){
   test('Export ${entry.key} ${mode.name}',()async{
    final d=entry.value;final stem='${out.path}/edge_${entry.key}_${mode.name}';
    await File('$stem.pdf').writeAsBytes(await PdfBlankGenerator.generate(d));
    await File('$stem.xlsx').writeAsBytes(XlsxBlankGenerator.generate(d));
    await File('$stem.docx').writeAsBytes(DocxBlankGenerator.generate(d));
    final c=CalculationEngine.calculate(d);await File('$stem.calc.json').writeAsString(jsonEncode({'rawWeight':c.rawTotalWeight,'rawProtein':c.rawTotalProtein,'cookedProtein':c.cookedProtein,'per100Protein':c.per100gProtein,'cookedKcal':c.cookedKcal}));
   });
  }
 }
 test('INVARIANT displayed rounded mass determines same protein in XLSX and engine',(){final d=fixture(.15);final xml=sheet(d);final m=RegExp(r'<c r="E\d+" s="3"><f>[^<]+</f><v>([^<]+)</v>').firstMatch(xml)!;final v=double.parse(m.group(1)!);expect(CalculationEngine.calculate(d).rawTotalProtein,v,reason:'One dish must not change nutrients by export format');});
}
