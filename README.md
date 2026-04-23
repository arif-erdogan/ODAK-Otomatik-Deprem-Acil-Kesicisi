# 🚨 ODAK — Otomatik Deprem Acil Kesicisi (OADK)

**Mobil Uygulaması** | v3.2 | Flutter + HC-06 Bluetooth (Hızlı Bağlantı ⚡)

---

## 📋 Proje Açıklaması

ODAK, deprem sırasında otomatik olarak elektrik ve doğal gaz kesicisini aktive eden akıllı bir güvenlik sistemidir. Mobil uygulama, **Arduino Uno** ile **HC-06 Klasik Bluetooth Modülü** üzerinden iletişim kurarak sistem kontrolünü ve durum izlemesini sağlar.

**Ana Özellikler:**
- ✅ Bluetooth SPP (Serial Port Profile) haberleşmesi
- ✅ ⚡ **Hızlı bağlantı (50-100ms)** — Eşleşmiş cihaz optimizasyonu (v3.2)
- ✅ Eşleşmiş cihaz listeleme ve seçimi
- ✅ Gerçek zamanlı durum izlemesi (deprem, gaz, elektrik)
- ✅ Komut gönderimi (elektrik aç, gaz aç, alarm sıfırla)
- ✅ Android 12+ ve 11 altı uyumluluğu
- ✅ Hata yönetimi ve otomatik yeniden bağlantı

---

## 🔧 HC-06 Entegrasyon (v3.2 — Hızlı Bağlantı MAC ile)

### **HC-06 Cihaz Bilgileri**

⭐ **Cihaz Adı (Varsayılan)**: `HC-06` — Fabrikadan çıktığı gibi  
⭐ **MAC Adresi (Varsayılan)**: `00:18:E4:40:00:06` — Doğrudan bağlantı için  
**Opsiyonel Adı**: `ODAK_Sistem` — AT komutu ile rename edildiyse

### **4 Adımlık Çalışma Algoritması (v3.2 Optimized)**

Uygulama, HC-06 Bluetooth modülü ile haberleşmek için 4 adımlık algoritma izler:

1. **İzinleri Alma** — Android 12+ için `BLUETOOTH_SCAN` + `BLUETOOTH_CONNECT`
2. **Eşleşmiş Cihazları Listeleme** — MAC adreslerini al
3. **Bağlantı Kurma** — SPP UUID ile soket aç
4. **Veri Akışı** — OutputStream (gönder) + InputStream (oku)

### **Standart UUID**
```
00001101-0000-1000-8000-00805F9B34FB  (Bluetooth Serial Port Profile)
```

### **Hızlı Başlangıç (3 Seçenek)**

```dart
import 'services/ble_service.dart';

// 1️⃣ Otomatik bağlantı (Eşleşmiş listede ara)
final sonuc = await BleService().baglan();

// 2️⃣ ⚡ HIZLI bağlantı — MAC adresine doğrudan (50-100ms)
final sonuc = await BleService().hizliBaglan();  // 00:18:E4:40:00:06 kullanır

// 3️⃣ Spesifik MAC adresine bağlan
final sonuc = await BleService().baglanMacAdresine('00:18:E4:40:00:06');
```

// Manual bağlantı (MAC adresi ile)
await BleService().baglanMacAdresine('00:11:22:33:44:55');

// Komut gönder
await BleService().elektrikAktifEt();
await BleService().dogalgazAktifEt();
await BleService().alarmSifirla();

// Durum dinle
BleService().arduinoDurumStream.listen((durum) {
  print('Deprem: ${durum.depremAlgilandi}');
  print('Gaz: ${durum.gazAcik}');
});
```

**📖 Detaylı rehber:** [HC-06_ENTEGRASYON_REHBERI.md](HC-06_ENTEGRASYON_REHBERI.md)

---

## 📦 Teknoloji Stack

| Bileşen | Sürüm | Amaç |
|---------|-------|------|
| Flutter | 3.3.0+ | Mobil uygulama geliştirme |
| Dart | 3.3.0+ | Programlama dili |
| flutter_bluetooth_serial | 0.4.0 | HC-06 SPP haberleşmesi |
| permission_handler | 11.0.0 | Runtime izin yönetimi |
| Arduino | Uno + HC-06 | Donanım kontrol sistemi |

---

## 🛠️ Kurulum

### **1. Flutter Ortamını Hazırla**

```bash
flutter --version  # 3.3.0 veya üzeri kontrol et
flutter pub get    # Bağımlılıkları indir
```

### **2. Android Ayarları**

`AndroidManifest.xml` zaten yapılandırılmış:
- ✅ `BLUETOOTH_SCAN` (Android 12+)
- ✅ `BLUETOOTH_CONNECT` (Android 12+)
- ✅ `BLUETOOTH` + `BLUETOOTH_ADMIN` (Android 11-)
- ✅ `ACCESS_FINE_LOCATION` (Keşif için)

### **3. HC-06 Kurulumu**

**Fiziksel Bağlantı:**
```
HC-06 VCC   → Arduino 5V
HC-06 GND   → Arduino GND
HC-06 TX    → Arduino RX (Pin 0)
HC-06 RX    → Arduino TX (Pin 1) [Direnç ile gerilim düşürme]
```

**AT Komutu İle Cihaz Adı Değiştirme:**
```
AT+NAME=ODAK_Sistem
AT+BAUD=9          (9600 baud)
AT+PSWD=1234       (PIN kodu)
```

---

## 📱 Uygulama Mimarisi

```
lib/
├── main.dart                           # Uygulama giriş noktası
├── services/
│   ├── ble_service.dart               # HC-06 Bluetooth SPP servisi ⭐
│   ├── firebase_service.dart          # Firebase (gerekirse)
│   └── wifi_api_service.dart          # WiFi API (gerekirse)
├── screens/
│   └── bluetooth_control_screen.dart  # HC-06 kontrol ekranı (örnek) ⭐
└── ... (diğer UI bileşenleri)
```

### **BleService Sınıfı**

```dart
class BleService {
  // İzin & Keşif
  Future<bool> izinleriKontrolEt()              // ADIM 1
  Future<Map<String, String>> eslesmisCihazlariListele()  // ADIM 2
  
  // Bağlantı
  Future<BtIslemSonucu> baglan()                // ADIM 1-4 otomatik
  Future<BtIslemSonucu> baglanMacAdresine(String mac)     // ADIM 3 direkt
  Future<void> baglantiKapat()
  
  // Komut Gönder (ADIM 4 - OutputStream)
  Future<BtIslemSonucu> elektrikAktifEt()
  Future<BtIslemSonucu> dogalgazAktifEt()
  Future<BtIslemSonucu> alarmSifirla()
  Future<BtIslemSonucu> gonderRawVeri(String veri)
  
  // Dinleyenler (ADIM 4 - InputStream)
  Stream<BtDurum> get durumStream              // Bağlantı durumu
  Stream<ArduinoDurum> get arduinoDurumStream  // Arduino sensör verisi
  Stream<String> get yanitStream               // Raw yanıtlar
}
```

---

## 🎮 Kullanım Örnekleri

### **Örnek 1: Temel Bağlantı ve Komut**

```dart
void main() async {
  final ble = BleService();
  
  // HC-06'ya bağlan
  final sonuc = await ble.baglan();
  if (sonuc.basarili) {
    print('✅ Bağlı!');
    
    // Elektriği aç
    await ble.elektrikAktifEt();
    
    // Doğalgazı aç
    await ble.dogalgazAktifEt();
  } else {
    print('❌ Hata: ${sonuc.mesaj}');
  }
}
```

### **Örnek 2: Durum Değişikliklerini Dinle**

```dart
final ble = BleService();

// Bağlantı durumu
ble.durumStream.listen((durum) {
  print('🔗 ${durum.metin}');
});

// Arduino durum güncellemeleri
ble.arduinoDurumStream.listen((durum) {
  if (durum.depremAlgilandi) {
    print('⚠️ DEPREM ALGILANDI!');
  }
  print('Gaz: ${durum.gazAcik}, Elektrik: ${durum.elektrikAcik}');
});
```

### **Örnek 3: Eşleşmiş Cihazlardan Seçim**

```dart
final ble = BleService();

// Eşleşmiş cihazları listele
final cihazlar = await ble.eslesmisCihazlariListele();
cihazlar.forEach((ad, mac) {
  print('📱 $ad → $mac');
});

// Seçili cihaza bağlan
await ble.baglanMacAdresine('00:11:22:33:44:55');
```

### **Örnek 4: Ham Veri Gönder**

```dart
final ble = BleService();

// Sadece karakter gönder
await ble.gonderRawVeri('1');    // "1" gönder
await ble.gonderRawVeri('A\n');  // "A\n" gönder
```

---

## 🔐 İzinler Detaylı

### **Android 12+ (API 31+)**
- `BLUETOOTH_SCAN` — Tarama (neverForLocation flag)
- `BLUETOOTH_CONNECT` — Bağlantı

**Ayarlar Ekranında:** "Yakındaki Cihazlar" görünür

### **Android 11 ve Altı**
- `BLUETOOTH` — BT aç/kapa
- `BLUETOOTH_ADMIN` — Keşif
- `ACCESS_FINE_LOCATION` — Keşif için konum

**Runtime İzin İsteme:**
```dart
bool izinlerVerildi = await BleService().izinleriKontrolEt();
if (!izinlerVerildi) {
  print('❌ İzin reddedildi!');
}
```

---

## 📊 Protokol Referansı

### **Arduino → Telefon** (InputStream)

```
STATUS:deprem=0,gaz=1,elek=1,sayac=0,esik=3.0,uptime=123
ALARM:deprem_algilandi
OK:elektrik_ac
ERR:bilinmeyen_komut
INFO:system_ready
```

### **Telefon → Arduino** (OutputStream)

```
CMD:elektrik_ac
CMD:dogalgaz_ac
CMD:reset_alarm
CMD:durum
1
0
A
```

---

## 🐛 Sorun Giderme

### **HC-06 Bulunamıyor**

✅ **Kontrol Listesi:**
- [ ] HC-06 gücü açık mı?
- [ ] LED'i yanıyor/yanıp sönüyor mu?
- [ ] Telefonla manual olarak eşleştirildi mi? (PIN: 1234)
- [ ] App izinleri (BLUETOOTH_SCAN) verili mi?
- [ ] Telefonun Bluetooth'u açık mı?

### **Bağlantı Kuruluyor Ama Veri Gelmiyor**

✅ **Kontrol Listesi:**
- [ ] Arduino `\n` ile veri gönderiyor mu?
- [ ] Arduino baud rate 9600 mı?
- [ ] HC-06 TX/RX kablolarının polarity doğru mu?
- [ ] RX'te voltaj düşürme direnci var mı?

### **"Kalıcı Red" Hatası**

Telefonun **Ayarlar → Uygulama → ODAK → İzinler → Yakındaki Cihazlar** açın.

---

## 🚀 Derleme ve Çalıştırma

```bash
# Debug modunda çalıştır
flutter run

# Release modunda derle
flutter build apk --release
flutter build appbundle --release

# Gerçek cihazda test et
flutter run -v
```

---

## 📚 Kaynaklar

- [HC-06 Entegrasyon Rehberi](HC-06_ENTEGRASYON_REHBERI.md) — Detaylı dokümantasyon
- [Flutter Bluetooth Serial](https://pub.dev/packages/flutter_bluetooth_serial)
- [Permission Handler](https://pub.dev/packages/permission_handler)
- [Arduino HC-06 Kurulum](https://en.wikipedia.org/wiki/Bluetooth_device_class)

---

## 📞 İletişim

**Proje:** ODAK — Otomatik Deprem Acil Kesicisi  
**Versiyon:** 3.0  
**Tür:** Flutter + Arduino + HC-06 Klasik Bluetooth SPP  
**Lisans:** MIT

---

## 🎯 Sonraki Adımlar

- [ ] iOS uyumluluğu (Core Bluetooth)
- [ ] Firebase gerçek zamanlı veri sinkronizasyonu
- [ ] Offline mod desteği
- [ ] Ses ve titreşim uyarıları
- [ ] Çoklu cihaz desteği
