#!/bin/bash

# Tekne TV - Android TV Build Script
# Bu script Android TV için optimize edilmiş APK oluşturur

echo "🎮 Tekne TV - Android TV Build Script"
echo "======================================"

# Flutter versiyonunu kontrol et
echo "📱 Flutter versiyonu kontrol ediliyor..."
flutter --version

# Bağımlılıkları güncelle
echo "📦 Bağımlılıklar güncelleniyor..."
flutter pub get

# Launcher iconları oluştur
echo "🎨 Launcher iconları oluşturuluyor..."
flutter pub run flutter_launcher_icons:main

# Clean build
echo "🧹 Eski build dosyaları temizleniyor..."
flutter clean
flutter pub get

# Android TV için APK oluştur
echo "🔨 Android TV APK oluşturuluyor..."
flutter build apk --target-platform android-arm64 --release

# Build başarılı mı kontrol et
if [ $? -eq 0 ]; then
    echo "✅ Build başarılı!"
    echo "📁 APK dosyası: build/app/outputs/flutter-apk/app-release.apk"
    echo ""
    echo "🎯 Android TV'ye yükleme:"
    echo "   adb install build/app/outputs/flutter-apk/app-release.apk"
    echo ""
    echo "📺 TV Kumandası Kısayolları:"
    echo "   ↑↓ - Kanal listesi navigasyonu"
    echo "   ←→ - Kanal değiştirme"
    echo "   OK/Enter - Seçim"
    echo "   Back/Esc - Geri"
    echo "   🔴 Kırmızı - Yenile"
    echo "   🟢 Yeşil - Tam ekran"
    echo "   🟡 Sarı - Kanal listesi"
    echo "   🔵 Mavi - Kanal bilgisi"
    echo ""
    echo "🎉 Tekne TV Android TV versiyonu hazır!"
else
    echo "❌ Build başarısız!"
    exit 1
fi