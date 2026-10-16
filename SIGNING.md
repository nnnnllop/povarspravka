# Релизная подпись APK «Поварская справка»

## 1. Конфигурация подписи (Production)

Сборка Release APK использует схему **APK Signature Scheme v2**. В проекте реализован строгий механизм **fail-closed**: при сборке `:app:assembleRelease` без валидного `key.properties` процесс завершается с ошибкой `org.gradle.api.GradleException`, предотвращая случайную публикацию с Debug-ключами.

### Параметры сертификата
- **Alias:** `povarspravka`
- **Distinguished Name (DN):** `CN=PovarSpravka, OU=Culinary Tech, O=PovarSpravka, L=Moscow, ST=Moscow, C=RU`
- **Алгоритм ключа:** RSA 2048 bit
- **Certificate SHA-256 Digest:** `e2a2c4779383adddea9b590a32712265f15490893ed7c7632d488d8322c4d0e2`
- **Certificate SHA-1 Digest:** `dd011be031224282d14765ca081c881558a16617`
- **Public Key SHA-256 Digest:** `cd1549f55cd7a61b38dbfeb9a626292d3fc915c0b7593db6dca455e5e594705a`

---

## 2. Настройка окружения для сборки

Для сборки подписанного релизного APK создайте файл `app/android/key.properties` на основе шаблона `app/android/key.properties.example`:

```properties
storePassword=<пароль_хранилища>
keyPassword=<пароль_ключа>
keyAlias=povarspravka
storeFile=<имя_файла_хранилища>.jks
```

Поместите файл хранилища ключей (`.jks`) в каталог `app/android/`.

> **Безопасность:** Файлы `key.properties` и `*.jks` внесены в `.gitignore` и ни при каких обстоятельствах не должны попадать в публичный репозиторий. Резервная копия ключей хранится локально у разработчика.

---

## 3. Сборка и проверка релиза

### Сборка
```bash
cd app
flutter build apk --release
```

### Верификация подписи
```bash
apksigner verify --verbose --print-certs build/app/outputs/flutter-apk/app-release.apk
```

Ожидаемый вывод:
```text
Verifies
Verified using v1 scheme (JAR signing): false
Verified using v2 scheme (APK Signature Scheme v2): true
Number of signers: 1
Signer #1 certificate DN: CN=PovarSpravka, OU=Culinary Tech, O=PovarSpravka, L=Moscow, ST=Moscow, C=RU
```

### Проверка разрешений
```bash
aapt dump permissions build/app/outputs/flutter-apk/app-release.apk
```

Ожидаемый вывод:
```text
package: ru.povarspravka.app
permission: ru.povarspravka.app.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION
uses-permission: name='ru.povarspravka.app.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION'
```
(Опасные runtime-разрешения и `INTERNET` отсутствуют, приложение работает полностью офлайн).
