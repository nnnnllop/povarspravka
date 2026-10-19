import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/export/xlsx_blank_generator.dart';
import '../test/culinary_logic_test.dart' show fixture;
void main(){test('ST_Xstring boundary fixtures',(){
 final cases=['_x0041_x0042_','_x005F_x0041_','_x0041__x0042_','_X0041_'];
 for(var i=0;i<cases.length;i++){
 final d=fixture(100).copyWith(title:cases[i],showTitleInExport:true);
 File('../audit_artifacts/mega/deep_unicode/xstring_$i.xlsx').writeAsBytesSync(XlsxBlankGenerator.generate(d));
 }
});}
