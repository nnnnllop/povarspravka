"""LLM-слой: канонические названия продуктов, синонимы и поиск опечаток.

Модель DeepSeek-V4.1-Flash через api.river.ai. Три прохода:
  1) исправление OCR-опечаток в сырых названиях;
  2) раскрытие «одиноких» прилагательных до полного названия
     («Костромской» -> «Сыр «Костромской»»), с опорой на раздел книги;
  3) ревизия ВСЕХ названий + бытовые синонимы (как продукт ищут в магазине).
Пакетами по 60 названий, ответ — JSON-массив. Ответы кэшируются в JSONL,
поэтому перезапуск продолжает с места остановки.
"""
from __future__ import annotations

import json
import os
import re
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import requests

URL = "https://api.river.ai/v1/chat/completions"
API_KEY_ENV = "RIVER_API_KEY"
MODEL = "deepseek-ai/DeepSeek-V4.1-Flash-1017"

ROOT = Path(__file__).resolve().parents[3]
INSPECT = Path(
    os.environ.get("SKURIKHIN_INSPECT_DIR")
    or (ROOT / "data" / "skurikhin_v2" / "_inspect")
)
CACHE = INSPECT / "names_llm_cache.jsonl"
LOCK = threading.Lock()


def _api_key() -> str:
    key = os.environ.get(API_KEY_ENV, "").strip()
    if not key:
        raise RuntimeError(
            f"Не задана переменная окружения {API_KEY_ENV} для доступа к {URL}"
        )
    return key


def ask(prompt: str, retries: int = 5) -> str:
    api_key = _api_key()
    body = {
        "model": MODEL,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": 8000,
        "temperature": 0,
    }
    last = None
    for attempt in range(retries):
        try:
            r = requests.post(URL, json=body, timeout=240,
                              headers={"Authorization": f"Bearer {api_key}"})
            r.raise_for_status()
            return r.json()["choices"][0]["message"]["content"]
        except Exception as exc:                       # noqa: BLE001
            last = exc
            time.sleep(2 + attempt * 4)
    raise RuntimeError(f"LLM недоступен: {last}")


def extract_json(text: str):
    """Достать JSON-массив из ответа модели."""
    start = text.find("[")
    end = text.rfind("]")
    if start < 0 or end <= start:
        return None
    try:
        return json.loads(text[start:end + 1])
    except json.JSONDecodeError:
        return None


SYSTEM = (
    "Ты — технолог пищевого производства и корректор. Работаешь со справочником "
    "«Химический состав российских пищевых продуктов» (Скурихин, Тутельян, 2002). "
    "Названия продуктов получены автоматическим распознаванием сканов и содержат "
    "ошибки OCR. Отвечай строго JSON-массивом без пояснений и без markdown."
)


# ------------------------------------------------------------------ проход 1
def fix_typos(items: list[dict]) -> dict[int, str]:
    lines = [f"{i}\t{it['section']}\t{it['name']}" for i, it in enumerate(items)]
    prompt = (
        SYSTEM + "\n\nДля каждой строки исправь опечатки OCR в названии продукта. "
        "Правила:\n"
        "- не меняй смысл и порядок слов, только исправляй ошибки;\n"
        "- восстанавливай пробелы («Молокостерилизованное» -> «Молоко "
        "стерилизованное»);\n"
        "- исправляй искажённые слова («Треска кедчена» -> «Треска копченая», "
        "«Хлеб ржский» -> «Хлеб ржаной», «Горбушка» -> «Горбуша», "
        "«Масло какаовелла» -> «Масло какао»);\n"
        "- латинские буквы внутри русских слов заменяй русскими;\n"
        "- если название уже верное, верни его без изменений.\n\n"
        "Формат ответа: [{\"i\": 0, \"name\": \"...\"}, ...] для ВСЕХ строк.\n\n"
        + "\n".join(lines)
    )
    data = extract_json(ask(prompt)) or []
    return {int(d["i"]): str(d["name"]).strip() for d in data
            if isinstance(d, dict) and "i" in d and "name" in d}


# ------------------------------------------------------------------ проход 2
def expand_names(items: list[dict]) -> dict[int, str]:
    lines = [f"{i}\t{it['section']}\t{it['name']}" for i, it in enumerate(items)]
    prompt = (
        SYSTEM + "\n\nНазвание продукта дано отдельно от своего родового слова, "
        "которое видно в столбце раздела. Восстанови ПОЛНОЕ название, добавив "
        "родовое слово из раздела.\n"
        "Примеры: раздел «СЫРЫ» + «Костромской» -> «Сыр «Костромской»»; "
        "раздел «МОРОЖЕНОЕ» + «Молочное» -> «Мороженое молочное»; "
        "раздел «КОЛБАСЫ» + «Докторская» -> «Колбаса вареная «Докторская»»; "
        "раздел «КАПУСТА» + «Краснокочанная» -> «Капуста краснокочанная»; "
        "раздел «КАРАМЕЛЬ» + «Леденцовая» -> «Карамель леденцовая»; "
        "раздел «ОРЕХИ» + «Грецкий» -> «Орех грецкий»; "
        "раздел «СОКИ» + «Яблочный» -> «Сок яблочный».\n"
        "Правила: не добавляй сорт, жирность и прочие данные, которых нет в "
        "названии; название должно остаться узнаваемым для этого продукта.\n\n"
        "Формат ответа: [{\"i\": 0, \"name\": \"...\"}, ...] для ВСЕХ строк.\n\n"
        + "\n".join(lines)
    )
    data = extract_json(ask(prompt)) or []
    return {int(d["i"]): str(d["name"]).strip() for d in data
            if isinstance(d, dict) and "i" in d and "name" in d}


# ------------------------------------------------------------------ проход 3
def review_and_synonyms(items: list[dict]) -> dict[int, dict]:
    """Проверить КАЖДОЕ название и дать бытовые синонимы."""
    lines = [f"{i}\t{it['section']}\t{it['name']}" for i, it in enumerate(items)]
    prompt = (
        SYSTEM + "\n\nДля каждой строки:\n"
        "1) проверь название на опечатки, искажённые слова и потерянные пробелы. "
        "Исправляй ТОЛЬКО очевидные ошибки OCR: «Горбушка» -> «Горбуша» (рыба), "
        "«получерствые» -> «полудесертные» (вина), «десятные» -> «десертные»; "
        "не переписывай корректные названия и не добавляй детали, которых нет;\n"
        "2) дай 1–3 бытовых синонима — как этот продукт называют покупатели и как "
        "его ищут в магазине/поиске (например «Сыр «Российский»» -> [\"российский "
        "сыр\", \"сыр российский\"]; «Сок яблочный» -> [\"яблочный сок\"]). "
        "Если название невозможно разобрать, оставь массив синонимов пустым.\n"
        "Синонимы пиши строчными буквами по-русски, без кавычек-ёлочек.\n\n"
        "Формат ответа: [{\"i\": 0, \"name\": \"...\", \"synonyms\": [\"...\"]},"
        " ...] для ВСЕХ строк.\n\n"
        + "\n".join(lines)
    )
    data = extract_json(ask(prompt)) or []
    out: dict[int, dict] = {}
    for d in data:
        if not isinstance(d, dict) or "i" not in d:
            continue
        syn = d.get("synonyms") or []
        if isinstance(syn, str):
            syn = [syn]
        syn = [str(s).strip().strip("«»\"'").lower() for s in syn if str(s).strip()]
        out[int(d["i"])] = {"name": str(d.get("name") or "").strip(),
                            "synonyms": syn[:3]}
    return out


# ------------------------------------------------------------------ каркас
def cached_prompt(tag: str, prompt_key: str, prompt: str) -> list[dict]:
    """Прочитать ответ из кэша или спросить модель и дописать кэш."""
    with LOCK:
        if CACHE.exists():
            for line in CACHE.read_text(encoding="utf-8").splitlines():
                if not line.strip():
                    continue
                rec = json.loads(line)
                if rec.get("key") == prompt_key:
                    return rec.get("data") or []
    text = ask(prompt)
    data = extract_json(text) or []
    with LOCK:
        with CACHE.open("a", encoding="utf-8") as fh:
            fh.write(json.dumps({"key": prompt_key, "tag": tag, "data": data},
                                ensure_ascii=False) + "\n")
    return data


def run_parallel(chunks: list[list[int]], worker, workers: int = 8) -> dict[int, dict]:
    """chunks — список пакетов индексов; worker(chunk) -> {i: {...}}."""
    result: dict[int, dict] = {}
    done = 0

    def task(chunk: list[int]):
        return chunk, worker(chunk)

    with ThreadPoolExecutor(max_workers=workers) as pool:
        for chunk, got in pool.map(task, chunks):
            done += len(chunk)
            result.update(got)
            print(f"  {done}/{sum(len(c) for c in chunks)}", flush=True)
    return result


def main() -> None:
    _api_key()
    raw_path = INSPECT / "assembled_raw.json"
    products = json.loads(raw_path.read_text(encoding="utf-8"))["products"]
    for p in products:
        sp = p.get("section_path") or []
        p["table_name"] = sp[0] if sp else ""
        p["section_path"] = " / ".join(sp)
    real = [p for p in products if p["code"].count(".") >= 2]
    print(f"продуктов: {len(real)}", flush=True)

    def batch_items(idx):
        return [{"section": real[i]["section_path"], "name": real[i]["name_raw"]}
                for i in idx]

    def chunk_key(tag, idx):
        return tag + "|" + "|".join(real[i]["code"] + real[i]["name_raw"] for i in idx)

    BATCH = 60
    index = list(range(len(real)))
    chunks = [index[i:i + BATCH] for i in range(0, len(index), BATCH)]

    # ---- проход 1: опечатки ------------------------------------------
    print("проход 1: исправление опечаток OCR", flush=True)

    def w1(chunk):
        items = batch_items(chunk)
        key = chunk_key("typo", chunk)
        lines = [f"{k}\t{it['section']}\t{it['name']}" for k, it in enumerate(items)]
        prompt = (
            SYSTEM + "\n\nДля каждой строки исправь опечатки OCR в названии "
            "продукта. Правила:\n- не меняй смысл и порядок слов;\n"
            "- восстанавливай пробелы;\n"
            "- исправляй искажённые слова («Горбушка» -> «Горбуша», «Масло "
            "какаовелла» -> «Масло какао», «получерствые» -> «полудесертные»);\n"
            "- латинские буквы заменяй русскими;\n"
            "- верное название возвращай без изменений.\n\n"
            "Формат: [{\"i\": 0, \"name\": \"...\"}, ...] для ВСЕХ строк.\n\n"
            + "\n".join(lines))
        data = cached_prompt("typo", key, prompt)
        return {chunk[int(d["i"])]: {"name": str(d.get("name") or "").strip()}
                for d in data if isinstance(d, dict) and "i" in d
                and str(d.get("i")).isdigit() and int(d["i"]) < len(chunk)}

    got1 = run_parallel(chunks, w1)
    for i, p in enumerate(real):
        p["name_fixed"] = (got1.get(i) or {}).get("name") or p["name_raw"]

    # ---- проход 2: раскрытие названий ---------------------------------
    print("проход 2: раскрытие названий по разделу", flush=True)
    need = [i for i, p in enumerate(real) if len(p["name_fixed"].split()) <= 2]
    chunks2 = [need[i:i + BATCH] for i in range(0, len(need), BATCH)]

    def w2(chunk):
        items = [{"section": real[i]["section_path"], "name": real[i]["name_fixed"]}
                 for i in chunk]
        key = chunk_key("expand", chunk)
        lines = [f"{k}\t{it['section']}\t{it['name']}" for k, it in enumerate(items)]
        prompt = (
            SYSTEM + "\n\nНазвание продукта дано отдельно от родового слова, "
            "которое видно в столбце раздела. Восстанови ПОЛНОЕ название.\n"
            "Примеры: «СЫРЫ» + «Костромской» -> «Сыр «Костромской»»; "
            "«МОРОЖЕНОЕ» + «Молочное» -> «Мороженое молочное»; "
            "«КАПУСТА» + «Краснокочанная» -> «Капуста краснокочанная».\n"
            "Не добавляй сорт и жирность. Формат: [{\"i\": 0, \"name\": \"...\"},"
            " ...] для ВСЕХ строк.\n\n" + "\n".join(lines))
        data = cached_prompt("expand", key, prompt)
        return {chunk[int(d["i"])]: {"name": str(d.get("name") or "").strip()}
                for d in data if isinstance(d, dict) and "i" in d
                and str(d.get("i")).isdigit() and int(d["i"]) < len(chunk)}

    got2 = run_parallel(chunks2, w2)
    for i, p in enumerate(real):
        p["name"] = (got2.get(i) or {}).get("name") or p["name_fixed"]

    # ---- проход 3: ревизия всех названий + синонимы -------------------
    print("проход 3: ревизия всех названий и синонимы", flush=True)

    def w3(chunk):
        items = [{"section": real[i]["section_path"], "name": real[i]["name"]}
                 for i in chunk]
        key = chunk_key("review", chunk)
        lines = [f"{k}\t{it['section']}\t{it['name']}" for k, it in enumerate(items)]
        prompt = (
            SYSTEM + "\n\nДля каждой строки:\n"
            "1) исправь ТОЛЬКО очевидные опечатки OCR в названии (например "
            "«Горбушка» -> «Горбуша» для рыбы); корректные названия не трогай;\n"
            "2) дай 1–3 бытовых синонима: как продукт называют покупатели и как "
            "его ищут в магазине («Сыр «Российский»» -> [\"российский сыр\"]).\n"
            "Синонимы строчными буквами по-русски, без ёлочек.\n\n"
            "Формат: [{\"i\": 0, \"name\": \"...\", \"synonyms\": [\"...\"]}, ...]"
            " для ВСЕХ строк.\n\n" + "\n".join(lines))
        data = cached_prompt("review", key, prompt)
        out = {}
        for d in data:
            if not isinstance(d, dict) or "i" not in d:
                continue
            if not str(d.get("i")).isdigit() or int(d["i"]) >= len(chunk):
                continue
            syn = d.get("synonyms") or []
            if isinstance(syn, str):
                syn = [syn]
            syn = [str(s).strip().strip("«»\"'").lower() for s in syn if str(s).strip()]
            out[chunk[int(d["i"])]] = {"name": str(d.get("name") or "").strip(),
                                       "synonyms": syn[:3]}
        return out

    got3 = run_parallel(chunks, w3)
    for i, p in enumerate(real):
        rec = got3.get(i) or {}
        if rec.get("name"):
            p["name"] = rec["name"]
        p["synonyms"] = rec.get("synonyms") or []

    out = INSPECT / "names_llm.json"
    out.write_text(json.dumps(
        [{"code": p["code"], "name_raw": p["name_raw"],
          "name_fixed": p["name_fixed"], "name": p["name"],
          "synonyms": p.get("synonyms") or [],
          "section": p["section_path"]} for p in real],
        ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"записано: {out}")
    changed = sum(1 for p in real if p["name"] != p["name_raw"])
    with_syn = sum(1 for p in real if p.get("synonyms"))
    print(f"изменено названий: {changed} из {len(real)}")
    print(f"с синонимами: {with_syn} из {len(real)}")


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", line_buffering=True)
    main()
