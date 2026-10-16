import os
import re
import sqlite3
import sys
from typing import List, Dict, Tuple, Optional

# Pre-translation normalization patterns (English)
CLEAN_EN_PATTERNS = [
    (r'\bNFS\b', ''),
    (r'\bNFSMI Recipe No\.[^,]+', ''),
    (r'\bUPC[:\s]*\d+\b', ''),
    (r',?\s*broilers or fryers', ''),
    (r',?\s*broiler or fryers', ''),
    (r'trimmed to 1/8" fat', 'trimmed 1/8" fat'),
    (r'trimmed to 1/4" fat', 'trimmed 1/4" fat'),
    (r'trimmed to 0" fat', 'trimmed 0" fat'),
    (r'\bMEAD JOHNSON\b', 'Mead Johnson'),
    (r'\bABBOTT NUTRITION\b', 'Abbott Nutrition'),
    (r'\bGERBER\b', 'Gerber'),
    (r'\bBEECH-NUT\b', 'Beech-Nut'),
    (r'\bNESTLE\b', 'Nestle'),
    (r'\bCAMPBELL\'?S?\b', 'Campbell'),
    (r'\bKRAFT\b', 'Kraft'),
    (r'\bKELLOGG\'?S?\b', 'Kellogg'),
    (r'\bPOST\b', 'Post'),
    (r'\bGENERAL MILLS\b', 'General Mills'),
]

INVERSION_RULES = [
    (re.compile(r'^Beef,\s*ground,?', re.I), 'Ground beef,'),
    (re.compile(r'^Pork,\s*ground,?', re.I), 'Ground pork,'),
    (re.compile(r'^Turkey,\s*ground,?', re.I), 'Ground turkey,'),
    (re.compile(r'^Chicken,\s*ground,?', re.I), 'Ground chicken,'),
    (re.compile(r'^Lamb,\s*ground,?', re.I), 'Ground lamb,'),
    (re.compile(r'^Veal,\s*ground,?', re.I), 'Ground veal,'),
    (re.compile(r'^Cheese,\s*cottage,?', re.I), 'Cottage cheese,'),
    (re.compile(r'^Cheese,\s*cream,?', re.I), 'Cream cheese,'),
    (re.compile(r'^Cheese,\s*mozzarella,?', re.I), 'Mozzarella cheese,'),
    (re.compile(r'^Cheese,\s*cheddar,?', re.I), 'Cheddar cheese,'),
    (re.compile(r'^Cheese,\s*parmesan,?', re.I), 'Parmesan cheese,'),
    (re.compile(r'^Cheese,\s*feta,?', re.I), 'Feta cheese,'),
    (re.compile(r'^Cheese,\s*ricotta,?', re.I), 'Ricotta cheese,'),
    (re.compile(r'^Cheese,\s*swiss,?', re.I), 'Swiss cheese,'),
    (re.compile(r'^Cheese,\s*blue,?', re.I), 'Blue cheese,'),
    (re.compile(r'^Cheese,\s*provolone,?', re.I), 'Provolone cheese,'),
    (re.compile(r'^Cheese,\s*gouda,?', re.I), 'Gouda cheese,'),
    (re.compile(r'^Cheese,\s*brie,?', re.I), 'Brie cheese,'),
    (re.compile(r'^Cheese,\s*pasteurized process,?', re.I), 'Processed cheese,'),
    (re.compile(r'^Milk,\s*whole,?', re.I), 'Whole milk,'),
    (re.compile(r'^Milk,\s*reduced fat,?', re.I), 'Reduced-fat milk (2%),'),
    (re.compile(r'^Milk,\s*lowfat,?', re.I), 'Low-fat milk (1%),'),
    (re.compile(r'^Milk,\s*nonfat,?', re.I), 'Skim milk (0%),'),
    (re.compile(r'^Butter,\s*without salt,?', re.I), 'Unsalted butter,'),
    (re.compile(r'^Butter,\s*with salt,?', re.I), 'Salted butter,'),
    (re.compile(r'^Oil,\s*olive,?', re.I), 'Olive oil,'),
    (re.compile(r'^Oil,\s*sunflower,?', re.I), 'Sunflower oil,'),
    (re.compile(r'^Oil,\s*canola,?', re.I), 'Canola oil,'),
    (re.compile(r'^Oil,\s*corn,?', re.I), 'Corn oil,'),
    (re.compile(r'^Oil,\s*soybean,?', re.I), 'Soybean oil,'),
    (re.compile(r'^Oil,\s*coconut,?', re.I), 'Coconut oil,'),
    (re.compile(r'^Fish,\s*salmon,?', re.I), 'Salmon fish,'),
    (re.compile(r'^Fish,\s*tuna,?', re.I), 'Tuna fish,'),
    (re.compile(r'^Fish,\s*cod,?', re.I), 'Cod fish,'),
    (re.compile(r'^Fish,\s*trout,?', re.I), 'Trout fish,'),
    (re.compile(r'^Fish,\s*halibut,?', re.I), 'Halibut fish,'),
    (re.compile(r'^Fish,\s*sardine,?', re.I), 'Sardine fish,'),
    (re.compile(r'^Fish,\s*mackerel,?', re.I), 'Mackerel fish,'),
    (re.compile(r'^Yogurt,\s*Greek,?', re.I), 'Greek yogurt,'),
    (re.compile(r'^Corn,\s*sweet,?', re.I), 'Sweet corn,'),
    (re.compile(r'^Rice,\s*white,?', re.I), 'White rice,'),
    (re.compile(r'^Rice,\s*brown,?', re.I), 'Brown rice,'),
    (re.compile(r'^Babyfood,\s*cereal,?', re.I), 'Baby food cereal,'),
    (re.compile(r'^Babyfood,\s*fruit,?', re.I), 'Baby food fruit,'),
    (re.compile(r'^Babyfood,\s*meat,?', re.I), 'Baby food meat,'),
    (re.compile(r'^Babyfood,\s*dinner,?', re.I), 'Baby food dinner,'),
    (re.compile(r'^Babyfood,\s*', re.I), 'Baby food, '),
]

# Post-translation Russian cleanup patterns
POST_RU_PATTERNS = [
    # Meat & poultry terminology
    (re.compile(r'\b(говядина|свинина|индейка|курица|баранина|телятина),\s*земля\b', re.I), r'\1 фарш'),
    (re.compile(r'\bГовядина,\s*(\d+%\s*постное мясо[^\,]+)', re.I), r'Говяжий фарш, \1'),
    (re.compile(r'\bМясная говядина\b', re.I), 'Говяжий фарш'),
    (re.compile(r'\bмясная говядина\b', re.I), 'говяжий фарш'),
    (re.compile(r'\bговядина фарш\b', re.I), 'говяжий фарш'),
    (re.compile(r'\bГовядина фарш\b', re.I), 'Говяжий фарш'),
    (re.compile(r'\bсвинина фарш\b', re.I), 'свиной фарш'),
    (re.compile(r'\bСвинина фарш\b', re.I), 'Свиной фарш'),
    (re.compile(r'\bкурица фарш\b', re.I), 'куриный фарш'),
    (re.compile(r'\bКурица фарш\b', re.I), 'Куриный фарш'),
    (re.compile(r'\bиндейка фарш\b', re.I), 'фарш из индейки'),
    (re.compile(r'\bИндейка фарш\b', re.I), 'Фарш из индейки'),
    (re.compile(r'\bтолько мясо\b', re.I), 'только мякоть'),
    (re.compile(r'\bмякоть и мясо\b', re.I), 'мякоть'),
    (re.compile(r'\bмясо и кожа\b', re.I), 'мякоть и кожура'),
    (re.compile(r'\bмясо и кожура\b', re.I), 'мякоть и кожура'),

    # Dairy & cheeses
    (re.compile(r'\bХлопковый сыр\b', re.I), 'Творог'),
    (re.compile(r'\bхлопкового сыра\b', re.I), 'творога'),
    (re.compile(r'\bхлопковый сыр\b', re.I), 'творог'),
    (re.compile(r'\bКоттеджный сыр\b', re.I), 'Творог'),
    (re.compile(r'\bкоттеджный сыр\b', re.I), 'творог'),
    (re.compile(r'\bнесоленое масло\b', re.I), 'несоленое сливочное масло'),
    (re.compile(r'\bНесоленое масло\b', re.I), 'Несоленое сливочное масло'),
    (re.compile(r'\bсоленое масло\b', re.I), 'соленое сливочное масло'),
    (re.compile(r'\bСоленое масло\b', re.I), 'Соленое сливочное масло'),

    # Plant-based & fruits/vegetables
    (re.compile(r'\bс кожей\b', re.I), 'с кожурой'),
    (re.compile(r'\bбез кожи\b', re.I), 'без кожуры'),
    (re.compile(r'\bКолраби\b', re.I), 'Кольраби'),
    (re.compile(r'\bколраби\b', re.I), 'кольраби'),

    # Brand fixes
    (re.compile(r'\bСМЕРТЬ ДЖОНСОН\b', re.I), 'Mead Johnson'),
    (re.compile(r'\bсмерть джонсон\b', re.I), 'Mead Johnson'),

    # Culinary adjectives & state
    (re.compile(r'\bкоммерчески приготовленный\b', re.I), 'промышленного производства'),
    (re.compile(r'\bкоммерчески готовый\b', re.I), 'промышленного производства'),
    (re.compile(r'\bготовый к употреблению\b', re.I), 'готовый к употреблению'),
    (re.compile(r'\bнеприготовленный\b', re.I), 'в сухом виде'),
    (re.compile(r'\bотделимая только постная\b', re.I), 'только постная часть'),
    (re.compile(r'\bотделимая постная и жир\b', re.I), 'постная часть с жиром'),

    # Formatting & cleanup
    (re.compile(r'\s*;\s*', re.I), ', '),
    (re.compile(r'\s*,\s*', re.I), ', '),
    (re.compile(r',\s*,', re.I), ','),
    (re.compile(r'\s+', re.I), ' '),
]

class TranslationCache:
    """Persistent SQLite cache for translated food names."""
    def __init__(self, db_path: str):
        self.db_path = db_path
        os.makedirs(os.path.dirname(os.path.abspath(db_path)), exist_ok=True)
        self.conn = sqlite3.connect(db_path)
        self._init_db()

    def _init_db(self):
        with self.conn:
            self.conn.execute("""
                CREATE TABLE IF NOT EXISTS translations (
                    source_en TEXT PRIMARY KEY,
                    cleaned_en TEXT,
                    translated_ru TEXT
                )
            """)
            self.conn.execute("CREATE INDEX IF NOT EXISTS idx_source ON translations(source_en)")

    def get(self, source_en: str) -> Optional[str]:
        cur = self.conn.cursor()
        cur.execute("SELECT translated_ru FROM translations WHERE source_en = ?", (source_en,))
        row = cur.fetchone()
        return row[0] if row else None

    def get_many(self, sources: List[str]) -> Dict[str, str]:
        results = {}
        batch_size = 900
        for i in range(0, len(sources), batch_size):
            chunk = sources[i:i + batch_size]
            placeholders = ','.join('?' * len(chunk))
            cur = self.conn.cursor()
            cur.execute(f"SELECT source_en, translated_ru FROM translations WHERE source_en IN ({placeholders})", chunk)
            for row in cur.fetchall():
                results[row[0]] = row[1]
        return results

    def set_many(self, records: List[Tuple[str, str, str]]):
        if not records:
            return
        with self.conn:
            self.conn.executemany("""
                INSERT OR REPLACE INTO translations (source_en, cleaned_en, translated_ru)
                VALUES (?, ?, ?)
            """, records)

    def close(self):
        self.conn.close()


class UsdaTranslator:
    """Translator engine with English normalization, neural batching, and Russian cleanup."""
    def __init__(self, cache_db_path: str):
        self.cache = TranslationCache(cache_db_path)
        self.ctranslator = None
        self.tokenizer = None
        self._init_neural_engine()

    def _init_neural_engine(self):
        try:
            import argostranslate.translate
            import ctranslate2
            languages = argostranslate.translate.get_installed_languages()
            en = next(filter(lambda x: x.code == 'en', languages))
            ru = next(filter(lambda x: x.code == 'ru', languages))
            pkg_tr = en.get_translation(ru).underlying
            model_path = str(pkg_tr.pkg.package_path / 'model')
            self.tokenizer = pkg_tr.pkg.tokenizer
            self.ctranslator = ctranslate2.Translator(
                model_path,
                device='cpu',
                inter_threads=4,
                intra_threads=4,
                compute_type='default'
            )
        except Exception as e:
            print(f"Warning: Could not initialize local neural translator: {e}")

    @staticmethod
    def normalize_english(name: str) -> str:
        cleaned = name.strip()
        for pattern, repl in CLEAN_EN_PATTERNS:
            cleaned = re.sub(pattern, repl, cleaned)
        for regex, repl in INVERSION_RULES:
            if regex.search(cleaned):
                cleaned = regex.sub(repl, cleaned)
                break
        cleaned = re.sub(r'\s*,\s*', ', ', cleaned)
        cleaned = re.sub(r'\s+', ' ', cleaned).strip(' ,')
        return cleaned

    @staticmethod
    def cleanup_russian(name: str, category: str = '') -> str:
        cleaned = name.strip()
        for regex, repl in POST_RU_PATTERNS:
            cleaned = regex.sub(repl, cleaned)
        cleaned = cleaned.strip(' ,;:')
        if cleaned:
            cleaned = cleaned[0].upper() + cleaned[1:]
        return cleaned

    def translate_batch(self, descriptions: List[str], batch_size: int = 128) -> Dict[str, str]:
        """Translates a list of original English descriptions into Russian."""
        # 1. Check cache first
        cached_results = self.cache.get_many(descriptions)
        missing = [d for d in descriptions if d not in cached_results]

        if not missing:
            return cached_results

        print(f"Translating {len(missing)} new items (already cached: {len(cached_results)})...")

        # 2. Normalize missing items
        norm_map = {d: self.normalize_english(d) for d in missing}
        unique_norms = list(set(norm_map.values()))

        # 3. Translate unique normalized strings with local CTranslate2
        norm_to_ru = {}
        if self.ctranslator and self.tokenizer:
            total = len(unique_norms)
            for i in range(0, total, batch_size):
                chunk = unique_norms[i:i + batch_size]
                tokenized = [self.tokenizer.encode(text) for text in chunk]
                batches = self.ctranslator.translate_batch(
                    tokenized,
                    max_batch_size=batch_size,
                    batch_type='examples',
                    beam_size=1,
                    num_hypotheses=1,
                    length_penalty=0.2
                )
                decoded = [self.tokenizer.decode(b.hypotheses[0]) for b in batches]
                for original_norm, raw_ru in zip(chunk, decoded):
                    norm_to_ru[original_norm] = self.cleanup_russian(raw_ru)
                if (i + batch_size) % 1024 < batch_size or (i + batch_size) >= total:
                    print(f"  Translated {min(i + batch_size, total)} / {total} unique items...")
        else:
            # Fallback to deep-translator MyMemory / Google if CTranslate2 unavailable
            from deep_translator import MyMemoryTranslator
            t = MyMemoryTranslator(source='en-US', target='ru-RU')
            for norm in unique_norms:
                try:
                    res = t.translate(norm)
                    norm_to_ru[norm] = self.cleanup_russian(res)
                except Exception:
                    norm_to_ru[norm] = norm

        # 4. Map back to original descriptions and prepare cache records
        new_records = []
        for orig in missing:
            norm = norm_map[orig]
            ru = norm_to_ru.get(norm, norm)
            cached_results[orig] = ru
            new_records.append((orig, norm, ru))

        # 5. Save to cache
        self.cache.set_many(new_records)
        print(f"Cached {len(new_records)} translations to SQLite.")

        return cached_results
