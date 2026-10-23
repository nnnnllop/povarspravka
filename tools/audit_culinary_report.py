import sys
import sqlite3
from decimal import Decimal, ROUND_HALF_UP

sys.stdout.reconfigure(encoding='utf-8')
con = sqlite3.connect('app/assets/db/reference.db')
cur = con.cursor()

def r1(v): 
    return float(Decimal(str(v)).quantize(Decimal('0.1'), rounding=ROUND_HALF_UP))

def r2(v): 
    return float(Decimal(str(v)).quantize(Decimal('0.01'), rounding=ROUND_HALF_UP))

def waste_adj(v, w, d=1):
    res = (Decimal(str(v)) * (Decimal('100') - Decimal(str(w)))) / Decimal('100')
    fmt = '0.' + '0'*d if d > 0 else '0'
    return float(res.quantize(Decimal(fmt), rounding=ROUND_HALF_UP))

def energy(p, f, c):
    tot = Decimal(str(p)) * 4 + Decimal(str(f)) * 9 + Decimal(str(c)) * 4
    return float(tot.quantize(Decimal('0.1'), rounding=ROUND_HALF_UP))

def ratio_round(v, div, d):
    res = (Decimal(str(v)) * Decimal('100')) / Decimal(str(div))
    fmt = '0.' + '0'*d if d > 0 else '0'
    return float(res.quantize(Decimal(fmt), rounding=ROUND_HALF_UP))

def run_recipe(name, ings, custom_yield, ret=(0.94, 0.88, 0.91)):
    raw_net = 0.0
    raw_p = 0.0
    raw_f = 0.0
    raw_c = 0.0
    raw_k = 0.0
    
    ing_details = []
    for pid, weight, is_gross, w_override in ings:
        row = cur.execute('SELECT name, protein, fat, carbs, kcal, waste_pct FROM product WHERE id=?', (pid,)).fetchone()
        pname, pp, pf, pc, pk, pw = row
        waste = w_override if w_override is not None else (pw if pw is not None else 0.0)
        net = waste_adj(weight, waste, 1) if is_gross else r1(weight)
        
        pdish = r2(net * r2(pp) / 100.0)
        fdish = r2(net * r2(pf) / 100.0)
        cdish = r2(net * r2(pc) / 100.0)
        kdish = energy(pdish, fdish, cdish)
        
        raw_net += net
        raw_p += pdish
        raw_f += fdish
        raw_c += cdish
        raw_k += kdish
        ing_details.append((pname, weight, is_gross, waste, net, pdish, fdish, cdish, kdish))
        
    raw_net = r1(raw_net)
    raw_p = r2(raw_p)
    raw_f = r2(raw_f)
    raw_c = r2(raw_c)
    raw_k = r1(raw_k)
    
    cp = r2(Decimal(str(raw_p)) * Decimal(str(ret[0])))
    cf = r2(Decimal(str(raw_f)) * Decimal(str(ret[1])))
    cc = r2(Decimal(str(raw_c)) * Decimal(str(ret[2])))
    ck = energy(cp, cf, cc)
    
    yg = r1(custom_yield) if custom_yield else raw_net
    p100 = ratio_round(cp, yg, 2)
    f100 = ratio_round(cf, yg, 2)
    c100 = ratio_round(cc, yg, 2)
    k100 = ratio_round(ck, yg, 1)
    
    return {
        'name': name,
        'raw_net': raw_net,
        'raw_p': raw_p, 'raw_f': raw_f, 'raw_c': raw_c, 'raw_k': raw_k,
        'yield': yg,
        'cooked_p': cp, 'cooked_f': cf, 'cooked_c': cc, 'cooked_k': ck,
        'p100': p100, 'f100': f100, 'c100': c100, 'k100': k100,
        'ings': ing_details
    }

# 1. Борщ с капустой и картофелем (Марчук №173, выход 1000 г)
r_borsh = run_recipe('1. Борщ с капустой и картофелем', [
    (775, 150.0, True, 20.0), # Свекла
    (706, 100.0, True, 20.0), # Капуста
    (737, 106.7, True, 25.0), # Картофель (брутто 106.7 -> нетто 80)
    (764, 50.0, True, 20.0),  # Морковь
    (733, 47.6, True, 16.0),  # Лук (брутто 47.6 -> нетто 40)
    (813, 30.0, False, None), # Томатное пюре
    (525, 20.0, False, None), # Масло подсолнечное (кулинарный жир)
    (925, 10.0, False, None), # Сахар
], 1000.0)

# 2. Котлеты рубленые из говядины (Марчук №658, полуфабрикат 125г -> выход 100г)
r_kotlet = run_recipe('2. Котлеты рубленые из говядины', [
    (174, 106.7, True, 25.0), # говядина 1 кат net 80
    (554, 20.0, False, None),  # хлеб пшеничный 20
    (525, 5.0, False, None),   # масло для жарки 5
], 100.0)

# 3. Каша гречневая рассыпчатая (Марчук №417, выход 1000г)
r_kasha = run_recipe('3. Каша гречневая рассыпчатая', [
    (646, 440.0, False, None), # гречка ядрица net 440
    (501, 30.0, False, None),  # масло сливочное 30
], 1000.0)

# 4. Сырники из творога (Марчук №486, выход 150г)
r_syrnik = run_recipe('4. Сырники из творога', [
    (82, 140.0, False, None), # творог 9% 140г
    (575, 18.0, False, None), # мука пшеничная 18г
    (159, 4.0, False, None),  # яйцо куриное 4г
    (925, 15.0, False, None), # сахар 15г
    (525, 5.0, False, None),  # масло растительное 5г
], 150.0)

# 5. Компот из сухофруктов (Марчук №862, выход 1000г)
r_kompot = run_recipe('5. Компот из сухофруктов', [
    (872, 142.0, True, 12.0), # яблоки сушеные net 125
    (925, 100.0, False, None), # сахар 100г
], 1000.0)

for res in [r_borsh, r_kotlet, r_kasha, r_syrnik, r_kompot]:
    print(f"=== {res['name']} ===")
    print(f"  Сырье (нетто суммарное): {res['raw_net']} г")
    print(f"  Выход готового блюда:    {res['yield']} г")
    print(f"  Все блюдо (после т.о.):  Б={res['cooked_p']} г, Ж={res['cooked_f']} г, У={res['cooked_c']} г, ЭЦ={res['cooked_k']} ккал")
    print(f"  На 100 г готового блюда: Б={res['p100']} г, Ж={res['f100']} г, У={res['c100']} г, ЭЦ={res['k100']} ккал")
    print()
