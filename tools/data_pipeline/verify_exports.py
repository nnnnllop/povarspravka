"""Independent Decimal oracle for XLSX formula caches and PyMuPDF PDF checks.
Run after flutter test: python -m tools.data_pipeline.verify_exports
"""
from decimal import Decimal as D, ROUND_HALF_UP, getcontext
from pathlib import Path
import zipfile, xml.etree.ElementTree as ET, ast, re, json
getcontext().prec=45
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'audit_artifacts/exports'
NS={'s':'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
def rounded(v,n): return v.quantize(D(1).scaleb(-n),rounding=ROUND_HALF_UP)
def calc(expression,values):
    if expression.startswith('ROUND('):
        match=re.fullmatch(r'ROUND\((.*),(\d+)\)',expression)
        assert match,expression
        return rounded(calc(match[1],values),int(match[2]))
    if expression.startswith('SUM('):
        match=re.fullmatch(r'SUM\(([A-Z]+)(\d+):([A-Z]+)(\d+)\)',expression)
        assert match and match[1]==match[3],expression
        return sum((values.get(f'{match[1]}{i}',D(0)) for i in range(int(match[2]),int(match[4])+1)),D(0))
    expression=re.sub(r'\b[A-Z]+\d+\b',lambda m:str(values.get(m[0],D(0))),expression)
    tree=ast.parse(expression,mode='eval')
    def walk(node):
        if isinstance(node,ast.Expression):return walk(node.body)
        if isinstance(node,ast.Constant) and isinstance(node.value,(int,float)):
            return D(ast.get_source_segment(expression,node))
        if isinstance(node,ast.UnaryOp) and isinstance(node.op,ast.USub):return -walk(node.operand)
        if isinstance(node,ast.BinOp):
            a,b=walk(node.left),walk(node.right)
            if isinstance(node.op,ast.Add):return a+b
            if isinstance(node.op,ast.Sub):return a-b
            if isinstance(node.op,ast.Mult):return a*b
            if isinstance(node.op,ast.Div):return a/b
        raise ValueError(ast.dump(node))
    return walk(tree)

def synthetic():
    for n in [1,5,20]:
        rows=[]
        for i in range(n):
            w=rounded(D('0.3') if i==0 else D('123.4567')+i*D('3.14159'),1)
            macros=[rounded(D(x),2) for x in ['15.0','7.89123','35.6789']]
            cache=[rounded(w*m/100,2) for m in macros]
            for m,v in zip(macros,cache):
                # Integer-rational model used by Dart, independent of the Decimal oracle.
                numerator=int(w*10)*int(m*100)
                actual=D((numerator*2+1000)//2000)/100
                assert actual==v,(n,i,w,m,v,actual)
            rows.append(cache)
        print(f'SYNTHETIC Decimal {n} rows: OK ({n*3} nutrient cells)')

def xlsx():
    files=sorted(OUT.glob('*.xlsx'));assert len(files)==6,len(files)
    checked=0
    for file in files:
        with zipfile.ZipFile(file) as z: sheet=ET.fromstring(z.read('xl/worksheets/sheet1.xml'))
        cells=sheet.findall('.//s:sheetData/s:row/s:c',NS)
        values={c.attrib['r']:D(c.find('s:v',NS).text) for c in cells if c.find('s:v',NS) is not None}
        count=0
        for c in cells:
            f=c.find('s:f',NS)
            if f is None:continue
            expected=calc(f.text,values);actual=values[c.attrib['r']]
            assert expected==actual,(file.name,c.attrib['r'],f.text,expected,actual)
            count+=1
        print(f'XLSX {file.name}: {count} formulas equal cached values exactly: OK')
        checked+=count
    return checked

def pdf():
    import pymupdf
    files=sorted(OUT.glob('*.pdf'));assert len(files)==14,len(files)
    results=[]
    for file in files:
        n=int(file.stem.rsplit('_',1)[1]);expected=max(1,(n+17)//18)
        with pymupdf.open(file) as doc:
            assert len(doc)==expected,(file.name,len(doc),expected)
            all_text=''
            for i,page in enumerate(doc):
                text=page.get_text();all_text+=text
                assert 'Наименование' in text,(file.name,i,'missing header')
                assert 'Аудит экспорта' in text,(file.name,i,'missing title')
                if i<len(doc)-1:
                    assert 'Продолжение на следующей странице' in text,(file.name,i)
                    assert 'После тепловой обработки' not in text,(file.name,i)
                else: assert 'После тепловой обработки' in text,(file.name,i)
                for word in page.get_text('words'):
                    assert word[0]>=0 and word[1]>=0 and word[2]<=page.rect.width+0.1 and word[3]<=page.rect.height+0.1,(file.name,i,word)
            for index in range(1,n+1):
                assert re.search(rf'Продукт {index}\b',all_text),(file.name,'missing ingredient',index)
            results.append({'file':file.name,'ingredients':n,'pages':len(doc),'status':'OK'})
            print(f'PDF {file.name}: {n} ingredients, {len(doc)} pages; headers, final totals, ingredient coverage and bounds: OK')
    return results

if __name__=='__main__':
    synthetic();checked=xlsx();pages=pdf()
    (ROOT/'audit_artifacts/export_verification.json').write_text(json.dumps({'xlsx_formulas_checked':checked,'pdf':pages},ensure_ascii=False,indent=2),encoding='utf-8')
    print('ALL EXPORT CHECKS PASSED')
