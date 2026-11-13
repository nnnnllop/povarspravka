import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/calculation_engine.dart';
import 'package:povarspravka/core/calculation/loss_table.dart';
import 'package:povarspravka/core/calculation/models/heat_process.dart';
import 'package:povarspravka/core/export/docx_blank_generator.dart';
import 'package:povarspravka/core/export/xlsx_blank_generator.dart';
import 'package:povarspravka/core/export/pdf_blank_generator.dart';
import 'audit3_core_test.dart' show dish;
String xml(List<int> b,String name)=>utf8.decode(ZipDecoder().decodeBytes(b).findFile(name)!.content as List<int>);
void main(){TestWidgetsFlutterBinding.ensureInitialized();
 test('E01 three exports same two yield states and legacy',()async{final out=Platform.environment['AUDIT3_OUT'];final evidence=<Map<String,dynamic>>[];
 for(final mode in ['weighted','missing','legacy']){final d=dish(process:mode=='legacy'?HeatProcess.legacy:HeatProcess.boil,weight:mode=='weighted'?200:null).copyWith(showPer100gRowInExport:true);final r=CalculationEngine.calculate(d);final a=DocxBlankGenerator.generate(d);final b=XlsxBlankGenerator.generate(d);final c=await PdfBlankGenerator.generate(d);final dx=xml(a,'word/document.xml');final sx=xml(b,'xl/worksheets/sheet1.xml');
 expect(dx.contains(kNotGostNotice),mode!='legacy');expect(sx.contains(kNotGostNotice),mode!='legacy');expect(String.fromCharCodes(c.take(5)),'%PDF-');
 for(final n in [r.cookedProtein,r.cookedFat,r.cookedCarbs]){expect(dx,contains(CalculationEngine.formatMacro(n)));}
 final dd='<w:t xml:space="preserve">—</w:t>'.allMatches(dx).length;final xd='<t>—</t>'.allMatches(sx).length;evidence.add({'mode':mode,'cooked':[r.cookedProtein,r.cookedFat,r.cookedCarbs,r.cookedKcal],'per100':[r.per100gProtein,r.per100gFat,r.per100gCarbs,r.per100gKcal],'docx_dashes':dd,'xlsx_dashes':xd});
 if(out!=null){final p=Directory('$out/exports');await p.create(recursive:true);await File('${p.path}/$mode.docx').writeAsBytes(a);await File('${p.path}/$mode.xlsx').writeAsBytes(b);await File('${p.path}/$mode.pdf').writeAsBytes(c);}}
 expect((evidence[1]['docx_dashes'] as int)-(evidence[0]['docx_dashes'] as int),5);expect((evidence[1]['xlsx_dashes'] as int)-(evidence[0]['xlsx_dashes'] as int),5);
 if(out!=null)await File('$out/export_evidence.json').writeAsString(jsonEncode(evidence));});}
