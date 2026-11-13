"""Финальная полировка `data/bls_v4/bls_products.json` перед сборкой базы.

Два дефекта этапа 2, исправляемых здесь:

1. **Категории букв E/U/V/W.** `category` были «черновыми» метками
   (`E: "Безалкогольные напитки (BLS: E)"`, `U: "Говядина"`,
   `V: "Свинина"`, `W: "Птица, дичь, субпродукты, колбасы"`), которые не
   соответствуют содержимому кода BLS: буква `E` — это яйца и макаронные
   изделия (E = «Eier und Eierzeugnisse»), `U` — говядина/телятина/
   баранина, `V` — птица/дичь/субпродукты, `W` — колбасные и мясные
   изделия. Замены задаются в `CATEGORY_OVERRIDES`.

2. **Строчная первая буква названия.** 5 761 из 7 140 продуктов имели
   `name`/`name_ru`, начинающиеся со строчной буквы («цельнозерновой
   хлеб»), потому что переводчик сохранял немецкую манеру письма. В UI
   продукты должны выглядеть единообразно, поэтому первая буква
   поднимается в верхний регистр (`capitalize`).

Модуль идемпотентен: повторный запуск не меняет уже исправленные данные.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
DATA = ROOT / "data" / "bls_v4"
SRC = DATA / "bls_products.json"

# Смешение латиницы и кириллицы в одном слове («Ржанoй», «Шупфнудeln»):
# легко не заметить, но ломает поиск и выглядит как брак (дефект M2).
MIXED_SCRIPT = re.compile(r"[\u0400-\u04FF][A-Za-z]|[A-Za-z][\u0400-\u04FF]")

# Латинские буквы, неотличимые по начертанию от кириллических (и наоборот),
# которые переводчик вставил в русские слова.
HOMOGLYPHS: dict[str, str] = {
    "a": "а", "e": "е", "o": "о", "p": "р", "c": "с", "x": "х",
    "y": "у", "k": "к", "m": "м", "t": "т", "n": "п", "P": "Р",
    "A": "А", "B": "В", "C": "С", "E": "Е", "H": "Н", "K": "К",
    "M": "М", "O": "О", "T": "Т", "X": "Х", "y": "у",
}

# Точечные замены «смешанных» названий и синонимов: ключ — код BLS,
# значение — правильная русская форма.
NAME_FIXES: dict[str, str] = {
    "B6A3000": "Ржаной цельнозерновой хрустящий хлеб с масличными семенами",
    "E605200": "Шупфнудель по-швабски, сырые",
    "X9A3020": "Слойки с начинкой из лосося и шманд, запечённые",
    "Y942132": "Братвурст с картофельным салатом и горчицей",
    "Y943062": "Карривурст с кетчупом карри и булочкой",
    "Y944062": "Карривурст с картофелем фри",
}
SYNONYM_FIXES: dict[str, dict[str, str]] = {
    "B6A1600": {"кrispbread цельнозерновой": "криспбред цельнозерновой"},
    "C530100": {"попped амарант": "поппед амарант"},
    "C530200": {"попped киноа": "поппед киноа"},
    "C531000": {"попped пшеница": "поппед пшеница"},
    "C532000": {"попped рис": "поппед рис"},
    "D7A6500": {"кrapфен": "крапфен"},
    "D9A2500": {"хefezopf цельнозерновой": "хефецопф цельнозерновой"},
    "E605200": {"шупфнудeln": "шупфнудель"},
    "K391200": {"дрaники замороженные": "драники замороженные"},
    "T830102": {"брatherинг": "братеринг"},
    "U109142": {"оxtail тушёный": "окстейл тушёный"},
    "U109182": {"оxtail": "окстейл"},
    "W221300": {"карриwurst": "карривурст"},
    "W221372": {"карриwurst": "карривурст"},
    "W251000": {"биерwurst": "биер-колбаса", "пивная колбасa": "пивная колбаса"},
    "W424000": {"кохшinken свиной": "кохшинкен свиной"},
    "X495363": {"дынная калtschale": "дынная кальтшале"},
    "Y184312": {"оxtail тушёный": "окстейл тушёный"},
    "Y611632": {"брatherинг": "братеринг"},
    "Y692943": {"рагout фин с окунем": "рагу фин с окунем"},
    "Y881842": {"квarkkeulchen": "кварккойльхен"},
    "Y910130": {"печёный картофель с квarkом": "печёный картофель с кварком"},
    "Y942132": {"братwurst с картофельным салатом": "братвурст с картофельным салатом"},
    "Y944062": {"карриwurst с картошкой фри": "карривурст с картошкой фри"},
}

# Синоним-«мусор»: в BLS переводчик положил в синонимы не альтернативное
# название, а описание с отрицанием («Сельдь под шубой нет, салат
# селёдочный с яблоком»). Такой текст поиск не находит и он путает
# пользователя. Код -> оставляемые синонимы (пустой список = снять все).
SYNONYMS_KEEP: dict[str, list[str]] = {
    "X1A8020": ["салат селедочный с яблоком", "сельдь под шубой"],
    "X651063": ["драники", "картофельные оладьи"],
}

# 36 групп продуктов с ОДИНАКОВЫМ русским названием (дефект H4). В BLS это
# разные коды с разным составом («Rind Vorderhesse» и «Rind Hinterhesse» —
# лопатка и огузок), но переводчик дал одинаковые названия. В UI по названию
# не отличить, поэтому уточняем по немецкому оригиналу.
NAME_DISAMBIGUATION: dict[str, str] = {
    # --- пересечение с книгой Скурихина -------------------------------
    # В BLS другие данные того же продукта; в поиске две строки с одинаковым
    # названием не отличить, поэтому у BLS-версии стоит пометка источника.
    "P712000": "Водка (BLS)",
    "F604600": "Сок грейпфрутовый (BLS)",
    "F606600": "Сок мандариновый (BLS)",
    "F110600": "Сок яблочный (BLS)",
    "S530000": "Шоколад молочный (BLS)",
    "S550000": "Шоколад сливочный (BLS)",
    "E111500": "Яичный порошок (BLS)",
    # --- хлеб и крупы ------------------------------------------------
    "B254072": "Пшенично-ржаной тостовый хлеб, поджаренный",
    "B314172": "Пшеничный тостовый хлеб с рожью, поджаренный",
    "B6A2000": "Ржаной хрустящий хлеб (кнэкеброт)",
    "B8B2000": "Ржаной хрустящий хлеб (кнюсперброт)",
    "C136000": "Овсяная крупа мелкого помола (грис)",
    "C137000": "Овсяная крупа дроблёная (грютце)",
    "C146000": "Ячменная крупа мелкого помола (грис)",
    "C236032": "Полба цельным зерном, варёная",
    "C240132": "Эммер (двузернянка) цельным зерном, варёный",
    "C326032": "Гречневая крупа мелкого помола, варёная (грис)",
    "C327032": "Гречневая крупа дроблёная, варёная (грютце)",
    "C422032": "Гречневая крупа крупного помола, варёная (шрот)",
    # --- кондитерские изделия ----------------------------------------
    "D0A3000": "Ореховый бисквитный корж",
    "D0A3100": "Ореховый бисквитный корж на воде",
    "D130100": "Яблочный пирог (песочное тесто)",
    "D731200": "Яблочный пирог американский (пай на песочном тесте)",
    "D7B2000": "Песочное печенье с нуговой начинкой",
    "D7B6100": "Песочное пирожное с нуговой начинкой (мюрбхен)",
    "D7B2100": "Песочное печенье с нуговой начинкой в шоколадной глазури",
    "D7B6200": "Песочное пирожное с нуговой начинкой в шоколадной глазури",
    # --- плоды, овощи, грибы -----------------------------------------
    "F220152": "Слива тушёная",
    "F223152": "Чернослив (венгерка) тушёный",
    "G660132": "Корень сельдерея, варёный",
    "X5A9050": "Сельдерей (овощ) варёный",
    "G710132": "Зелёная фасоль, варёная",
    "X5A8000": "Зелёная фасоль (стручковая) отварная",
    "G710152": "Зелёная фасоль тушёная",
    "X571143": "Зелёная фасоль тушёная с жиром",
    "G760152": "Зелёный горошек тушёный",
    "X570143": "Зелёный горошек тушёный с жиром",
    "K713152": "Лисички тушёные",
    "X512053": "Лисички тушёные с жиром",
    "K718152": "Белые грибы тушёные",
    "X513063": "Белые грибы тушёные с жиром",
    # --- шоколад ------------------------------------------------------
    "S530300": "Молочный шоколад с карамельной начинкой",
    "S539100": "Молочный шоколад (из цельного молока) с карамельной начинкой",
    "S530700": "Молочный шоколад с фруктовой начинкой",
    "S539200": "Молочный шоколад (из цельного молока) с фруктовой начинкой",
    "S530800": "Молочный шоколад с трюфельной начинкой (с алкоголем)",
    "S538700": "Молочный шоколад из цельного молока с трюфельной начинкой "
                "(с алкоголем)",
    "S535000": "Молочный шоколад с нуговой начинкой",
    "S541600": "Молочный шоколад (из цельного молока) с нуговой начинкой",
    "S560000": "Тёмный шоколад (полугорький)",
    "S570000": "Тёмный шоколад горький",
    # --- рыба ---------------------------------------------------------
    "T213132": "Минтай припущенный",
    "T213152": "Минтай тушёный",
    "T305132": "Камбала (золотой боттус) припущенная",
    "T311152": "Камбала (флиндер) тушёная",
    "T309200": "Морской язык, замороженный",
    "T313200": "Морской язык красный (ротцунге), замороженный",
    "T420132": "Форель припущенная",
    "T420152": "Форель тушёная",
    # --- мясо и субпродукты -------------------------------------------
    "U271132": "Говяжья голяшка (передняя) варёная",
    "U291132": "Говяжья голяшка (задняя) варёная",
    "U281142": "Говяжий огузок (окорок), тушёный без жира",
    "U284142": "Говяжий огузок (бедро), тушёный без жира",
    "U382132": "Телячья грудинка варёная",
    "U452132": "Телячья грудинка в бульоне, варёная",
    "U622700": "Свиная корейка (спинная часть), варёно-копчёная с копчением",
    "U622800": "Свиная корейка (спинная часть), варёно-копчёная",
    "U866162": "Баранья лопатка, запечённая без жира",
    "U867162": "Ягнячья лопатка, запечённая без жира",
    "V524132": "Бараний мозг (овца), варёный",
    "V526132": "Бараний мозг (ягнёнок), варёный",
    "V574142": "Баранья почка (овца), тушёная без жира",
    "V575142": "Баранья почка (ягнёнок), тушёная без жира",
    "V594132": "Бараний язык (овца), варёный",
    "V595132": "Бараний язык (ягнёнок), варёный",
    # --- колбасы и клёцки ---------------------------------------------
    "W384100": "Кровяная колбаса с перловой крупой (мелкая)",
    "W384200": "Кровяная колбаса с перловой крупой",
    "X436243": "Клёцки с ветчиной (мелкие)",
    "X981452": "Клёцки с ветчиной",
    "Y184212": "Говядина тушёная (с жиром и солью)",
    "Y184612": "Говядина томлёная (с жиром и солью)",
}

# Буква BLS -> итоговое название категории для UI и `food_group.name`.
CATEGORY_OVERRIDES: dict[str, str] = {
    "E": "Яйца и макаронные изделия",
    "U": "Говядина, телятина, баранина",
    "V": "Птица, дичь, субпродукты",
    "W": "Колбасные и мясные изделия",
}

# Исходные (черновые) метки, которые были в данных до исправления.
LEGACY_CATEGORIES: dict[str, str] = {
    "E": "Безалкогольные напитки (BLS: E)",
    "U": "Говядина",
    "V": "Свинина",
    "W": "Птица, дичь, субпродукты, колбасы",
}


def capitalize(value: str | None) -> str | None:
    """Поднять первую букву в верхний регистр, не трогая остальные."""
    if not value or not value[0].isalpha():
        return value
    return value[0].upper() + value[1:]


def fix_mixed_script(text: str) -> str:
    """Заменить латинские омоглифы в кириллических словах на кириллицу."""
    if not MIXED_SCRIPT.search(text):
        return text
    out: list[str] = []
    token: list[str] = []

    def flush() -> None:
        if not token:
            return
        word = "".join(token)
        token.clear()
        if not MIXED_SCRIPT.search(word):
            out.append(word)
            return
        has_cyr = bool(re.search(r"[\u0400-\u04FF]", word))
        has_lat = bool(re.search(r"[A-Za-z]", word))
        # слово целиком латинское (бренд, «питьевой» артикль) — не трогаем
        if has_cyr and has_lat:
            word = "".join(HOMOGLYPHS.get(ch, ch) for ch in word)
        out.append(word)

    for ch in text:
        if ch.isalpha():
            token.append(ch)
        else:
            flush()
            out.append(ch)
    flush()
    return "".join(out)


def polish_product(item: dict) -> bool:
    """Исправить один продукт на месте. Возвращает True, если что-то менялось."""
    changed = False
    letter = (item.get("category_letter") or "").upper()
    target = CATEGORY_OVERRIDES.get(letter)
    if target and item.get("category") != target:
        item["category"] = target
        changed = True
    code = item.get("code") or ""
    # 1. точное название из таблицы
    fixed_name = NAME_FIXES.get(code) or NAME_DISAMBIGUATION.get(code)
    if fixed_name and item.get("name") != fixed_name:
        item["name"] = fixed_name
        item["name_ru"] = fixed_name
        changed = True
    # 2. подъём первой буквы и латиница внутри кириллицы
    for field in ("name", "name_ru"):
        value = item.get(field)
        if isinstance(value, str):
            fixed = fix_mixed_script(capitalize(value))
            if fixed != value:
                item[field] = fixed
                changed = True
    # 3. синонимы: точечные замены, затем общий проход по латинице
    synonyms = item.get("synonyms")
    if isinstance(synonyms, list) and synonyms:
        repl = SYNONYM_FIXES.get(code) or {}
        keep = SYNONYMS_KEEP.get(code)
        new: list[str] = []
        for syn in synonyms:
            syn2 = repl.get(syn) or fix_mixed_script(syn)
            syn2 = capitalize(syn2)
            if syn2 in item.get("name") or syn2 == item.get("name"):
                continue          # синоним-дубль названия не нужен
            if keep is not None and syn2 not in keep:
                continue
            if syn2 and syn2 not in new:
                new.append(syn2)
        if new != synonyms:
            item["synonyms"] = new
            changed = True
    # 4. шум округления (дефект L2): значения вида 0,002 мг витамина C —
    #    это не результат анализа, а хвост пересчёта. Такие ячейки снимаются,
    #    иначе карточка показывает «C 0,002 мг».
    if drop_float_noise(item):
        changed = True
    # 5. баланс жирных кислот (дефект L4): сумма НЖК и ПНЖК не может
    #    превышать общий жир. В BLS встречаются строки, где при жире 0,0 г
    #    указаны НЖК 0,006 и ПНЖК 0,005 — это округление источника, но
    #    инвариант `sfa + pufa <= fat` должен выполняться, иначе карточка
    #    показывает больше насыщенных+ненасыщенных, чем всего жира.
    if fix_fat_fractions(item):
        changed = True
    return changed


# Порог шума: всё, что меньше, — хвост пересчёта, а не измерение.
NOISE = 0.005


def drop_float_noise(item: dict) -> bool:
    """Снять ячейки нутриентов со значением-шумом (< 0,005)."""
    nutrients = item.get("nutrients")
    if not isinstance(nutrients, dict):
        return False
    changed = False
    for key, cell in list(nutrients.items()):
        if not isinstance(cell, dict):
            continue
        value = cell.get("value")
        if value is None:
            continue
        number = abs(float(value))
        if 0 < number < NOISE:
            cell["value"] = None
            changed = True
    return changed


def _num(nutrients: dict, key: str) -> float | None:
    cell = nutrients.get(key)
    if isinstance(cell, dict):
        value = cell.get("value")
        return None if value is None else float(value)
    if cell is None:
        return None
    return float(cell)


def fix_fat_fractions(item: dict) -> bool:
    """Поднять общий жир до НЖК + ПНЖК, если источник его занизил."""
    nutrients = item.get("nutrients") or {}
    fat = _num(nutrients, "fat")
    sfa = _num(nutrients, "fat_saturated")
    pufa = _num(nutrients, "fat_polyunsaturated")
    if fat is None or sfa is None or pufa is None:
        return False
    total = round(sfa + pufa, 3)
    if total <= fat + 0.0005:
        return False
    cell = nutrients.get("fat")
    if isinstance(cell, dict):
        cell["value"] = total
    else:
        nutrients["fat"] = total
    return True


def polish_payload(payload: dict) -> int:
    """Исправить все продукты. Возвращает число изменённых продуктов."""
    return sum(1 for item in payload.get("products", []) if polish_product(item))


def main() -> None:
    payload = json.loads(SRC.read_text(encoding="utf-8"))
    products = payload["products"]

    before_lower = sum(1 for p in products if (p.get("name") or "")[:1].islower())
    before_cat = {letter: sum(1 for p in products
                              if (p.get("category_letter") or "").upper() == letter
                              and p.get("category") != name)
                  for letter, name in CATEGORY_OVERRIDES.items()}

    changed = polish_payload(payload)

    # Контроль: после правки строчных названий не остаётся, категории едины.
    after_lower = sum(1 for p in products if (p.get("name") or "")[:1].islower())
    after_cat = {letter: sum(1 for p in products
                             if (p.get("category_letter") or "").upper() == letter
                             and p.get("category") != name)
                 for letter, name in CATEGORY_OVERRIDES.items()}
    problems = []
    if after_lower:
        problems.append(f"строчных названий осталось: {after_lower}")
    for letter, count in after_cat.items():
        if count:
            problems.append(f"буква {letter}: {count} продуктов не в своей категории")
    # латиница внутри кириллицы недопустима ни в названиях, ни в синонимах
    mixed = [p.get("code") for p in products
             if MIXED_SCRIPT.search(p.get("name") or "")
             or MIXED_SCRIPT.search(p.get("name_ru") or "")]
    mixed += [p.get("code") for p in products
              for s in (p.get("synonyms") or []) if MIXED_SCRIPT.search(s)]
    if mixed:
        problems.append(f"смешанная латиница/кириллица: {len(mixed)} — {mixed[:8]}")
    # одинаковых названий быть не должно
    seen: dict[str, str] = {}
    dups = []
    for p in products:
        name = p.get("name") or ""
        if name in seen:
            dups.append((name, seen[name], p.get("code")))
        else:
            seen[name] = p.get("code")
    if dups:
        problems.append(f"повторяющихся названий: {len(dups)} — {dups[:5]}")
    # инвариант жирных кислот: НЖК + ПНЖК ≤ жир (дефект L4)
    fat_bad = [p.get("code") for p in products
               if (lambda fat, sfa, pufa: fat is not None and sfa is not None
                   and pufa is not None and sfa + pufa > fat + 0.0005)(
                   _num(p.get("nutrients") or {}, "fat"),
                   _num(p.get("nutrients") or {}, "fat_saturated"),
                   _num(p.get("nutrients") or {}, "fat_polyunsaturated"))]
    if fat_bad:
        problems.append(f"НЖК+ПНЖК > жира: {len(fat_bad)} — {fat_bad[:8]}")
    if problems:
        raise SystemExit("полировка не сошлась: " + "; ".join(problems))

    payload.setdefault("meta", {})["polished"] = {
        "renamed_categories": {letter: {"from": LEGACY_CATEGORIES[letter],
                                        "to": name,
                                        "products": before_cat[letter]}
                               for letter, name in CATEGORY_OVERRIDES.items()},
        "capitalized_names": before_lower,
        "products_changed": changed,
    }
    SRC.write_text(json.dumps(payload, ensure_ascii=False, indent=1),
                   encoding="utf-8")

    print(f"продуктов: {len(products)}")
    print(f"изменено: {changed}")
    print(f"названий со строчной буквы — было {before_lower}, стало {after_lower}")
    for letter, name in CATEGORY_OVERRIDES.items():
        print(f"  {letter}: «{LEGACY_CATEGORIES[letter]}» -> «{name}» "
              f"({before_cat[letter]} шт.)")
    print(f"записан: {SRC}")


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", line_buffering=True)
    main()
