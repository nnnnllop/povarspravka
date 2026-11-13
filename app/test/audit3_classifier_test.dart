import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/food_classifier.dart';
import 'package:povarspravka/core/calculation/models/loss_group.dart';
import 'support/reference_db.dart';
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 test('C01 all 8261 actual classifier exhaustive export',()async{
  final ps=await loadAllReferenceProducts();expect(ps,hasLength(8261));
  final counts={for(final g in LossGroup.values)g.name:0};
  final rows=<Map<String,Object?>>[];
  for(final p in ps){final g=FoodClassifier.classify(p);counts[g.name]=counts[g.name]!+1;rows.add({'id':p.id,'name':p.name,'group_id':p.groupId,'source':p.source,'is_dish':p.isDishOnly,'loss_group':g.name});expect(FoodClassifier.classify(p),g);}
  expect(counts.values.reduce((a,b)=>a+b),8261);
  final path=Platform.environment['AUDIT3_OUT'];
  if(path!=null){await File('$path/classifier_all.json').writeAsString(jsonEncode(rows));await File('$path/classifier_distribution.json').writeAsString(jsonEncode(counts));}
  print('AUDIT3_DISTRIBUTION ${jsonEncode(counts)}');
 });
}
