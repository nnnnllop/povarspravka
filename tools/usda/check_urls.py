import requests

headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
}

urls = [
    'https://fdc.nal.usda.gov/download-datasets.html',
    'https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_sr_legacy_food_csv_2018-04.zip',
    'https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_sr_legacy_food_csv_2019-04-02.zip',
    'https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_foundation_food_csv_2024-10-31.zip',
    'https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_foundation_food_csv_2023-10-26.zip',
    'https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_csv_2024-10-31.zip',
    'https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_csv_2023-10-26.zip',
    'https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_csv_2022-10-28.zip',
]

for url in urls:
    try:
        r = requests.head(url, headers=headers, timeout=10, allow_redirects=True)
        size = r.headers.get("content-length", "?")
        print(f"{r.status_code} ({size} bytes): {url}")
    except Exception as e:
        print(f"Error {url}: {e}")
