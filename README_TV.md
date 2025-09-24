# Tekne TV - Android TV Uygulaması

Bu uygulama, tekne'nin lig TV hayratı'nın tamamen Android TV'lere odaklanmış versiyonudur. Televizyon kumandası ile tam navigasyon desteği sunar.

## 🎮 TV Kumandası Kısayolları

### Temel Navigasyon
- **↑↓** - Kanal listesinde gezinme
- **←→** - Kanal değiştirme (önceki/sonraki)
- **OK/Enter** - Seçim yapma veya yardım gösterme
- **Back/Esc** - Geri gitme veya çıkış
- **Play/Pause** - Kontrolleri gösterme/gizleme

### Kanal Kontrolü
- **CH+/CH-** - Sonraki/önceki kanal
- **F1** - Kanal listesini yenile
- **F2** - Tam ekran açma/kapama
- **F3** - Kanal bilgisi gösterme

### Renkli Tuşlar
- **🔴 Kırmızı** - Kanal listesini yenile
- **🟢 Yeşil** - Tam ekran aç/kapat
- **🟡 Sarı** - Kanal listesini aç/kapat
- **🔵 Mavi** - Kanal bilgisi

## 🖥️ TV Optimizasyonları

### UI/UX
- Büyük, okunabilir fontlar
- TV ekranları için optimize edilmiş düzen
- Yüksek kontrast renkler
- 10 feet deneyimi (uzaktan izleme)
- Odak yönetimi ile kolay navigasyon

### Performans
- Android TV Leanback desteği
- Donanım hızlandırması
- Düşük gecikme süresi
- Optimize edilmiş video oynatma

### Özellikler
- M3U stream desteği
- Tam ekran video oynatma
- Kanal listesi ile hızlı geçiş
- Otomatik kanal yükleme
- TV kumandası ile tam kontrol

## 🚀 Kurulum

### Gereksinimler
- Android TV cihazı
- Android 5.0+ (API 21+)
- İnternet bağlantısı

### Derleme
```bash
flutter build apk --target-platform android-arm64
```

### Yükleme
1. APK dosyasını Android TV'ye yükleyin
2. Uygulamayı Android TV ana ekranından başlatın
3. TV kumandası ile navigasyon yapın

## 📱 Uyumluluk

- **Android TV** - Tam destek
- **Google TV** - Tam destek  
- **Fire TV** - Tam destek
- **NVIDIA Shield** - Tam destek
- **Xiaomi Mi Box** - Tam destek
- **Diğer Android TV cihazları** - Tam destek

## 🎯 Kullanım

1. Uygulamayı başlatın
2. Kanallar otomatik olarak yüklenir
3. TV kumandası ile navigasyon yapın
4. Kanal listesi için **Sarı** tuşa basın
5. Kanal değiştirmek için **←→** tuşlarını kullanın
6. Tam ekran için **Yeşil** tuşa basın

## 🔧 Teknik Detaylar

### Flutter Sürümü
- Flutter 3.9.2+
- Dart 3.0+

### Bağımlılıklar
- `video_player: ^2.8.1`
- `http: ^1.1.0`
- Android TV Leanback kütüphaneleri

### Mimari
- TV-optimized widget yapısı
- Focus management
- Key event handling
- TV-specific themes

## 📄 Lisans

Bu uygulama tekne'nin lig TV hayratı kapsamında geliştirilmiştir.

## 🙏 Teşekkürler

- Tekne'nin lig TV hayratı için
- Android TV geliştirici topluluğu
- Flutter ekibi

---

**Not**: Bu uygulama tamamen Android TV'ler için optimize edilmiştir. Mobil cihazlarda çalışabilir ancak TV deneyimi için tasarlanmamıştır.