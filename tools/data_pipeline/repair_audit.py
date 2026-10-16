"""Non-destructive D01/D02 migration of the unified catalogue; retains IDs and USDA.
Run from project root: python -m tools.data_pipeline.repair_audit
"""
from pathlib import Path
import sqlite3, re, shutil, json, os, hashlib, datetime
from .skurikhin.config import KNOWN_CANONICAL_NAMES, SKURIKHIN_SYNONYMS
from .skurikhin.database_builder import normalize_text, export_csv

ROOT=Path(__file__).resolve().parents[2]
DB=ROOT/'tools/data_pipeline/output/reference.db'
MACROS={'7.1.7':(34.9,17.3,17.3,364.0),'7.1.11':(21.0,2.0,47.0,298.0),'7.1.12':(2.5,0.3,3.0,23.0)}

def repair_culinary(text):
    text=re.sub(r'барабанная\s+палочка\s+турция', 'Голень индейки', text, flags=re.I)
    text=re.sub(r'\bтурция\b', lambda m: 'Индейка' if m[0][0].isupper() else 'индейка', text, flags=re.I)
    text=re.sub(r'запчасти для розничной торговли','кулинарные отрубы/части тушки',text,flags=re.I)
    text=re.sub(r'рыба,\s*голень','Рыба семейства горбылевых (горбыль)',text,flags=re.I)
    text=re.sub(r'барабан\s+рыба','Рыба семейства горбылевых (горбыль)',text,flags=re.I)
    text=re.sub(r'внутри\s+барабан\w*\s+эму','Внутри голени эму',text,flags=re.I)
    text=re.sub(r'барабанн\w*\s+палоч\w*','голень',text,flags=re.I)
    text=re.sub(r'кожа\s*\(?барабан\w*\s+и\s+бедр\w*\)?','кожа (голени и бедра)',text,flags=re.I)
    return text

def main():
    backup=ROOT/'audit_artifacts'/('db_backup_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S'))
    backup.mkdir(parents=True,exist_ok=False)
    temp=DB.with_suffix('.audit.tmp.db')
    if temp.exists(): os.remove(temp)
    with sqlite3.connect(DB) as src, sqlite3.connect(backup/'reference.db') as dst:
        src.backup(dst)
    src.close();dst.close()
    shutil.copy2(backup/'reference.db',temp)
    asset=ROOT/'app/assets/db/reference.db'
    with sqlite3.connect(asset) as src, sqlite3.connect(backup/'asset_reference.db') as dst:
        src.backup(dst)
    src.close();dst.close()
    with sqlite3.connect(temp) as c:
        before=c.execute('select source,count(*) from product group by source').fetchall()
        c.execute('PRAGMA foreign_keys=ON')
        for code,values in MACROS.items():
            actual=c.execute('select protein,fat,carbs,kcal from product where code=?',(code,)).fetchone()
            assert actual==values,(code,actual,values) # Never fabricate nutrient values.
            name=KNOWN_CANONICAL_NAMES[code]
            c.execute('update product set name=?,name_norm=? where code=?',(name,normalize_text(name),code))
        # Rebuild only Skurikhin synonyms, using the versioned source configuration.
        c.execute("delete from synonym where product_id in (select id from product where source='skurikhin')")
        for pid,code in c.execute("select id,code from product where source='skurikhin'").fetchall():
            for syn_code,syn in SKURIKHIN_SYNONYMS:
                if code==syn_code or code.startswith(syn_code+'.'):
                    c.execute('insert into synonym(product_id,synonym,synonym_norm) values(?,?,?)',(pid,syn,normalize_text(syn)))
        changed=0
        for pid,name in c.execute("select id,name from product where source='usda'").fetchall():
            fixed=repair_culinary(name)
            if fixed!=name:
                c.execute('update product set name=?,name_norm=? where id=?',(fixed,normalize_text(fixed),pid));changed+=1
            else:
                c.execute('update product set name_norm=? where id=?',(normalize_text(name),pid))
        for sid,syn in c.execute("select s.id,s.synonym from synonym s join product p on p.id=s.product_id where p.source='usda'").fetchall():
            fixed=repair_culinary(syn)
            if fixed!=syn:
                c.execute('update synonym set synonym=?,synonym_norm=? where id=?',(fixed,normalize_text(fixed),sid))
            else:
                c.execute('update synonym set synonym_norm=? where id=?',(normalize_text(syn),sid))
        # Extra safety for any residual drumstick synonyms
        c.execute("update synonym set synonym='Куриная голень', synonym_norm='куриная голень' where synonym like '%барабанн%палоч%' or synonym_norm like '%барабанн%палоч%'")
        c.execute("update synonym set synonym='Кожа (голени и бедра) курица', synonym_norm='кожа голени и бедра курица' where synonym like '%барабан%бедр%' or synonym_norm like '%барабан%бедр%'")
        c.execute("update synonym set synonym='Внутри голени эму', synonym_norm='внутри голени эму' where synonym like '%барабан%эму%' or synonym_norm like '%барабан%эму%'")
        c.execute("update synonym set synonym='Рыба семейства горбылевых (горбыль)', synonym_norm='рыба семейства горбылевых горбыль' where synonym like '%барабан%рыба%' or synonym_norm like '%барабан%рыба%'")

        # Completely clean and rebuild FTS
        c.execute('delete from product_fts')
        c.execute('''insert into product_fts(rowid,product_id,name,name_norm)
            select p.id,p.id,p.name,p.name_norm || ' ' || coalesce((
                select group_concat(s.synonym_norm,' ') from synonym s where s.product_id=p.id),'')
            from product p order by p.id''')
        c.execute("insert into product_fts(product_fts) values('optimize')")
        assert c.execute('select source,count(*) from product group by source').fetchall()==before
        assert c.execute('select count(*) from product_fts where rowid != cast(product_id as integer)').fetchone()[0]==0
        assert c.execute("select count(*) from product where name like '%Турция%' or name like '%Рыба, голень%'").fetchone()[0]==0
        first=c.execute('''select p.code,p.name from product_fts f join product p on p.id=cast(f.product_id as integer)
            where product_fts match '"гречка"*' limit 1''').fetchone()
        assert first==('6.6.4','Гречиха крупа ядрица'),first
        assert c.execute('PRAGMA integrity_check').fetchone()[0]=='ok'
        assert not c.execute('PRAGMA foreign_key_check').fetchall()
        rx=re.compile(r'\bтурци\w*|барабанн\w*\s+палоч\w*|бобы,\s*окунь', re.I)
        for row in c.execute('select c2 from product_fts_content').fetchall():
            assert not rx.search(row[0] or ''), f"FTS content match: {row[0]}"
        assert c.execute('select count(*) from product_fts where product_fts match \'"барабанная палочка"\'').fetchone()[0]==0
        assert c.execute('select count(*) from product_fts where product_fts match \'"голень"*\'').fetchone()[0]>=35
        print('COUNTS',before,'USDA names repaired',changed)
        print('LEGUMES',c.execute("select code,name,protein,fat,carbs,kcal from product where code in ('7.1.7','7.1.11','7.1.12') order by code").fetchall())
        print('FTS FIRST',first)
        print('FTS ROWID MISMATCHES 0; invalid translations 0; integrity_check ok; foreign_key_check ok')
        c.commit()
        c.execute('PRAGMA wal_checkpoint(TRUNCATE)')
        c.execute('PRAGMA journal_mode=DELETE')
    c.close()
    # Checkpoint the old file before replacement so stale WAL cannot replay over it.
    with sqlite3.connect(DB) as old:
        old.execute('PRAGMA wal_checkpoint(TRUNCATE)')
        old.execute('PRAGMA journal_mode=DELETE')
    old.close()
    os.replace(temp,DB)
    with sqlite3.connect(asset) as old:
        old.execute('PRAGMA wal_checkpoint(TRUNCATE)')
        old.execute('PRAGMA journal_mode=DELETE')
    old.close()
    asset_temp=asset.with_suffix('.tmp')
    shutil.copy2(DB,asset_temp);os.replace(asset_temp,asset)
    # Update the exported Skurikhin datasets without re-extracting or dropping USDA.
    jp=ROOT/'tools/data_pipeline/output/skurikhin_products.json'
    cp=jp.with_suffix('.csv')
    shutil.copy2(jp,backup/jp.name);shutil.copy2(cp,backup/cp.name)
    products=json.loads(jp.read_text(encoding='utf-8'))
    for product in products:
        if product['code'] in MACROS: product['name']=KNOWN_CANONICAL_NAMES[product['code']]
    jp.write_text(json.dumps(products,ensure_ascii=False,indent=2),encoding='utf-8')
    export_csv(products,cp)
    assert DB.read_bytes()==asset.read_bytes()
    print('DEPLOY SHA256',hashlib.sha256(DB.read_bytes()).hexdigest())
    print('BACKUP',backup)

if __name__=='__main__':main()
