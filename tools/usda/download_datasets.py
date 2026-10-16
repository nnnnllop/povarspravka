import os
import zipfile
import requests

CACHE_DIR = os.path.join("tools", "usda", "cache")
os.makedirs(CACHE_DIR, exist_ok=True)

headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
}

datasets = [
    ("sr_legacy", "https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_sr_legacy_food_csv_2018-04.zip"),
    ("foundation", "https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_foundation_food_csv_2024-10-31.zip")
]

for name, url in datasets:
    zip_path = os.path.join(CACHE_DIR, f"{name}.zip")
    extract_dir = os.path.join(CACHE_DIR, name)
    
    if not os.path.exists(zip_path):
        print(f"Downloading {name} from {url}...")
        resp = requests.get(url, headers=headers, stream=True)
        resp.raise_for_status()
        with open(zip_path, "wb") as f:
            for chunk in resp.iter_content(chunk_size=65536):
                f.write(chunk)
        print(f"Saved {zip_path} ({os.path.getsize(zip_path)} bytes)")
    else:
        print(f"Already exists: {zip_path}")
        
    os.makedirs(extract_dir, exist_ok=True)
    with zipfile.ZipFile(zip_path, 'r') as zf:
        zf.extractall(extract_dir)
        print(f"Extracted {name} to {extract_dir}:")
        for member in zf.namelist():
            print(f"  - {member}")
