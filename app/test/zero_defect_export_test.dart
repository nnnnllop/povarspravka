import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/export/export_service.dart';
import 'package:povarspravka/core/export/xlsx_blank_generator.dart';
import 'culinary_logic_test.dart' show fixture;
String sheet(Dish d) => utf8.decode(ZipDecoder().decodeBytes(XlsxBlankGenerator.generate(d)).findFile('xl/worksheets/sheet1.xml')!.content as List<int>);
void main() {
 TestWidgetsFlutterBinding.ensureInitialized();
 test('ZD09 retention explanations are formulas linked to editable retention cells', () {
   final xml = XmlDocument.parse(sheet(fixture(100).copyWith(retentionProtein:.935)));
   final explanation = xml.findAllElements('c').firstWhere((c)=>c.innerText.contains('= Сумма белков'));
   expect(explanation.getElement('f'), isNotNull);
   expect(explanation.getElement('f')!.innerText, contains('TEXT(D'));
 });
 test('ZD10 long Unicode filename can be exported without component overflow', () async {
   final dir=await Directory.systemTemp.createTemp('zd_share_');
   const pathChannel=MethodChannel('plugins.flutter.io/path_provider');
   const shareChannel=MethodChannel('dev.fluttercommunity.plus/share');
   final paths=<String>[];
   TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(pathChannel,(call) async => dir.path);
   TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(shareChannel,(call) async { if(call.method=='shareFiles'){paths.addAll(((call.arguments as Map)['paths'] as List).cast<String>());}return 'ok'; });
   try {
     final d=fixture(100).copyWith(title:List.filled(220,'Я').join());
     await Future.wait(List.generate(5,(_)=>ExportService.shareFile(d,ExportType.xlsx)));
     expect(paths.length,5); expect(paths.toSet().length,5);
     for(final path in paths){expect(await File(path).exists(),isTrue);expect(utf8.encode(File(path).uri.pathSegments.last).length,lessThanOrEqualTo(100));}
   } finally {
     TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(pathChannel,null);
     TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(shareChannel,null);
     await dir.delete(recursive:true);
   }
 });
}
