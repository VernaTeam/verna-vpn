# Verna VPN App — Setup Guide

## ساختار پروژه

```
verna_vpn/
├── lib/
│   ├── main.dart                          # Entry point
│   ├── core/
│   │   ├── theme/app_theme.dart           # Material 3 themes + ThemeMode provider
│   │   └── l10n/app_strings.dart          # FA/EN strings
│   └── features/
│       ├── configs/
│       │   ├── domain/vpn_config.dart     # Entity + enums
│       │   ├── data/
│       │   │   ├── config_api_client.dart # API + MOCK data
│       │   │   └── config_repository.dart # Cache layer
│       │   └── presentation/
│       │       ├── providers/configs_provider.dart  # Riverpod state
│       │       ├── screens/
│       │       │   ├── splash_screen.dart
│       │       │   ├── home_screen.dart
│       │       │   └── config_detail_screen.dart
│       │       └── widgets/
│       │           ├── config_card.dart
│       │           ├── filter_bottom_sheet.dart
│       │           └── stats_bar.dart
│       └── about/
│           └── presentation/screens/about_screen.dart
├── android/
│   └── app/src/main/
│       ├── AndroidManifest.xml
│       └── res/xml/network_security_config.xml
└── pubspec.yaml
```

---

## مرحله ۱ — نصب

```bash
# نصب Flutter (اگه نداری)
# https://docs.flutter.dev/get-started/install

# بررسی محیط
flutter doctor

# نصب dependencies
cd verna_vpn
flutter pub get
```

---

## مرحله ۲ — فونت Vazirmatn

```bash
mkdir -p assets/fonts assets/images

# دانلود از:
# https://github.com/rastikerdar/vazirmatn/releases
# فایل‌های لازم:
# - Vazirmatn-Regular.ttf
# - Vazirmatn-Medium.ttf
# - Vazirmatn-Bold.ttf
# → در assets/fonts/ قرار بده
```

**یا** اگه نخوای font local باشه، در `pubspec.yaml` بخش fonts رو حذف کن
و در `app_theme.dart` مقدار `_fontFamily` رو به `'Roboto'` تغییر بده.

---

## مرحله ۳ — اجرا با mock data

```bash
flutter run
```

اپ با mock data اجرا میشه — نیازی به سرور نیست.

---

## مرحله ۴ — وصل کردن به API واقعی

در فایل `lib/features/configs/data/config_api_client.dart`:

```dart
// خط ۷ رو تغییر بده:
const bool _useMock = false;  // ← اینجا
```

---

## مرحله ۵ — Build APK

```bash
# Debug APK
flutter build apk --debug

# Release APK (نیاز به keystore داره)
flutter build apk --release

# APK آماده در:
# build/app/outputs/flutter-apk/app-release.apk
```

---

## مرحله ۶ — Keystore برای release

```bash
keytool -genkey -v \
  -keystore verna.keystore \
  -alias verna \
  -keyalg RSA -keysize 2048 \
  -validity 10000

# در android/key.properties:
storePassword=YOUR_STORE_PASS
keyPassword=YOUR_KEY_PASS
keyAlias=verna
storeFile=../../verna.keystore
```

---

## Feature-ها

| Feature | وضعیت |
|---------|--------|
| Splash screen | ✅ |
| Home با tabs | ✅ |
| کارت کانفیگ | ✅ |
| Copy URI | ✅ |
| Filter bottom sheet | ✅ |
| جستجو | ✅ |
| Ping color indicator | ✅ |
| Dark/Light theme | ✅ |
| RTL فارسی | ✅ |
| آفلاین cache (15 min TTL) | ✅ |
| Config detail screen | ✅ |
| About screen | ✅ |
| File download | 🔜 فاز ۳ |
| Push notification | 🔜 آینده |

---

## وصل کردن به FastAPI (فاز ۳)

وقتی سرور آماده شد:
1. `_useMock = false` در `config_api_client.dart`
2. برای file download، این packages رو اضافه کن:
   ```yaml
   path_provider: ^2.1.4
   open_filex: ^4.5.0
   url_launcher: ^6.2.6
   ```
3. `_downloadFile()` در `config_card.dart` و `config_detail_screen.dart` رو implement کن
