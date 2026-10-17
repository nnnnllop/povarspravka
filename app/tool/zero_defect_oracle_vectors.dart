import 'dart:convert';
import 'dart:io';
import 'dart:math';
import '../lib/core/calculation/calculation_math.dart';
void main() {
 final random=Random(20261017); final rows=<Map<String,dynamic>>[];
 for(var i=0;i<5000;i++) {
  final a=(random.nextInt(200000001)-100000000)/100.0;
  final b=(random.nextInt(200001)-100000)/1000.0;
  final divisor=(random.nextInt(1000000)+1)/100.0;
  final p=(random.nextInt(200001)-100000)/1000.0;
  final f=(random.nextInt(200001)-100000)/1000.0;
  final c=(random.nextInt(200001)-100000)/1000.0;
  final waste=random.nextInt(100000)/1000.0;
  final mass=random.nextInt(100000001)/100.0;
  final terms=List.generate(20,(_)=>(random.nextInt(200001)-100000)/100.0);
  rows.add({'a':a,'b':b,'divisor':divisor,'p':p,'f':f,'c':c,'waste':waste,'mass':mass,'terms':terms,
    'product':CalculationMath.productRounded(a,b,2),
    'ratio':CalculationMath.ratioRounded(a,divisor,2),
    'energy':CalculationMath.energy(p,f,c),
    'net':CalculationMath.wasteAdjusted(mass,waste,1),
    'sum':CalculationMath.sumRounded(terms,2)});
 }
 final file=File('../audit_artifacts/zero_defect_oracle_vectors.json');file.writeAsStringSync(jsonEncode(rows));
 print('seed=20261017; vectors=${rows.length}; operations=${rows.length*5}; output=${file.path}');
}
