# HC-06 Bluetooth Entegrasyon Rehberi (v3.2 — Hızlı Bağlantı Optimizasyonu)

## 📋 İçindekiler
1. [Genel Bakış](#genel-bakış)
2. [4 Adımlık Çalışma Algoritması](#4-adımlık-çalışma-algoritması)
3. [HC-06 Konfigürasyonu](#hc-06-konfigürasyonu)
4. [Kod Kullanım Örnekleri](#kod-kullanım-örnekleri)
5. [İzinler (Permissions)](#izinler-permissions)
6. [Sorun Giderme](#sorun-giderme)

---

## 🎯 Genel Bakış

ODAK uygulaması, **Arduino Uno** ile **HC-06 Klasik Bluetooth Modülü** kullanarak haberleşir.

**Teknik Özellikler:**
- **Bluetooth Versiyonu**: Klasik Bluetooth (SPP - Serial Port Profile)
- **Standart UUID**: `00001101-0000-1000-8000-00805F9B34FB`
- **Protokol**: UTF-8 satır tabanlı mesajlaşma (`\n` ile sonlandırılır)
- **Veri Hızı**: HC-06 varsayılan 9600 baud

**HC-06 Cihaz Adı:**
- ⭐ **Varsayılan (Tavsiye Edilen)**: "HC-06" — Fabrikasından çıktığı gibi
- **Opsiyonel**: "ODAK_Sistem" — AT komutu ile değiştirilmişse aranır

---

## 🔄 4 Adımlık Çalışma Algoritması

Flutter uygulaması, HC-06 ile bağlantı kurmak için 4 adımlık bir döngü izler:

### **ADIM 1: İzinleri Alma** 🔐

**Android 12+ (API 31+):**
- `BLUETOOTH_SCAN` — Cihaz taraması için izin (neverForLocation)
- `BLUETOOTH_CONNECT` — Cihaza bağlanmak için izin

**Android 11 ve Altı:**
- `BLUETOOTH` — Bluetooth'u açıp kapamak
- `BLUETOOTH_ADMIN` — Keşif yapmak
- `ACCESS_FINE_LOCATION` — Keşif için konum izni (gereken)

**Kod:**
```dart
final izinler = await [
  Permission.bluetoothScan,
  Permission.bluetoothConnect,
].request();

bool taramaOk = izinler[Permission.bluetoothScan] == PermissionStatus.granted;
bool baglantiOk = izinler[Permission.bluetoothConnect] == PermissionStatus.granted;

if (!taramaOk || !baglantiOk) {
  print('❌ İzin reddedildi');
}
```

---

### **ADIM 2: Eşleşmiş Cihazları Listeleme** 📱

Telefonla daha önce eşlenmiş tüm Bluetooth cihazlarını listeler.

**2a) Hızlı Yol — Eşleşmiş Listede Ara:**
```dart
final eslesmisler = await BleService().eslesmisCihazlariListele();
// Çıktı: {'HC-06': '00:11:22:33:44:55', 'Başka Cihaz': 'AA:BB:CC:DD:EE:FF'}

for (final ad in eslesmisler.keys) {
  print('📍 $ad → ${eslesmisler[ad]}');
}
```

**2b) Keşif Taraması — Yakındaki Cihazları Ara:**

Eşleşmiş listede HC-06 yoksa, Bluetooth keşif taraması yapılır.
- Varsayılan tarama süresi: **15 saniye**
- HC-06 açık olmalı ve yakında olmalı

```dart
// Otomatik olarak ADIM 1, 2a ve 2b yapılır:
final sonuc = await BleService().baglan();
if (sonuc.basarili) {
  print('✅ ${sonuc.mesaj}');
} else {
  print('❌ ${sonuc.mesaj}');
}
```

---

### **ADIM 3: Bağlantı (Soket) Kurma** 🔌

MAC adresi ve standart UUID ile HC-06'ya soket bağlantısı kurulur.

**Standart UUID (tüm Bluetooth SPP cihazlarda aynı):**
```
00001101-0000-1000-8000-00805F9B34FB
```

**Kod:**
```dart
// Doğrudan MAC adresine bağlan (eğer adres biliyorsan)
final sonuc = await BleService().baglanMacAdresine('00:11:22:33:44:55');
if (sonuc.basarili) {
  print('✅ HC-06 bağlı!');
}
```

**Bağlantı Durumu:**
```dart
// Mevcut durum kontrolü
bool bagliMi = BleService().bagliMi;

// Durum değişikliklerini dinle
BleService().durumStream.listen((durum) {
  print('Durum: ${durum.metin}');
});
```

---

### **ADIM 4: Veri Akışı (Stream)** 📡

Bağlantı kurulduktan sonra:
- **OutputStream**: Komutları Arduino'ya gönder
- **InputStream**: Arduino'dan sensör verilerini oku

#### **OutputStream — Komut Gönder:**

```dart
// 1️⃣ Hazır komutlar:
await BleService().elektrikAktifEt();      // "CMD:elektrik_ac\n"
await BleService().dogalgazAktifEt();      // "CMD:dogalgaz_ac\n"
await BleService().alarmSifirla();         // "CMD:reset_alarm\n"
await BleService().durumIste();            // "CMD:durum\n"

// 2️⃣ Ham veri gönder (doğrudan karakterler):
await BleService().gonderRawVeri('1');     // "1" gönder
await BleService().gonderRawVeri('0');     // "0" gönder
await BleService().gonderRawVeri('A\n');   // "A\n" gönder
```

#### **InputStream — Veri Oku:**

```dart
// Arduino durum değişikliklerini dinle
BleService().arduinoDurumStream.listen((durum) {
  print('📊 Durum: $durum');
  print('   Deprem: ${durum.depremAlgilandi}');
  print('   Gaz: ${durum.gazAcik}');
  print('   Elektrik: ${durum.elektrikAcik}');
  print('   Uptime: ${durum.uptimeSn}s');
});

// Ham yanıtları dinle
BleService().yanitStream.listen((mesaj) {
  print('📝 Yanıt: $mesaj');
});
```

---

## ⚙️ HC-06 Konfigürasyonu

### **HC-06 Fiziksel Kurulum:**

1. **VCC**: Arduino 5V'ye bağla
2. **GND**: Arduino GND'ye bağla
3. **TX**: Arduino RX (pin 0)'a bağla (seri haberleşme için)
4. **RX**: Arduino TX (pin 1)'e bağla (direnç ile gerilim düşürme yapılması önerilir)

### **HC-06 Cihaz Adı (Önemli!)**

**Varsayılan Durum:**
- HC-06 fabrikasından çıktığı gibi adı **"HC-06"** (değiştirilmemiş)
- Uygulamada bu ad ön planda aranıyor ⭐

**İsteğe Bağlı — AT Komutu ile Adını Değiştirme:**
- HC-06'yı "ODAK_Sistem" olarak isimlendiirmek istiyorsan aşağıdaki AT komutlarını gönder
- Komutu göndermezsen, cihaz "HC-06" olarak kalır ve otomatik bulunur

### **HC-06 AT Komutları (SEÇİMLİ):**

HC-06'nın AT komut moduna girmek için:
1. HC-06'ya 5V verin
2. **LED kırmızı yanıp sönerken** seri terminalinden AT komutları gönderin

**Örnek AT Komutları (İsteğe Bağlı):**
```
AT              (Komut modunu test et → "OK" dönmeli)
AT+NAME=ODAK_Sistem   (❌ Opsiyonel — cihaz adını "ODAK_Sistem" yap)
AT+BAUD=9             (Baud rate 9600'e ayarla)
AT+PSWD=1234          (PIN'i 1234'e ayarla)
```

**⚠️ ÖNEMLİ:**
- **AT+NAME komutunu GÖNDERMEYİN** eğer cihaz "HC-06" olarak kalmasını istiyorsan (tavsiye edilir)
- Eğer gönderdiysen, uygulamada ikinci sırada aranır (biraz daha yavaş)
- Varsayılan "HC-06" adı en hızlı bulunur

---

## 💻 Kod Kullanım Örnekleri

### **Örnek 1: Temel Bağlantı**

```dart
import 'services/ble_service.dart';

void main() async {
  final ble = BleService();
  
  // HC-06'ya bağlan
  final sonuc = await ble.baglan();
  if (sonuc.basarili) {
    print('✅ Bağlantı kuruldu!');
  } else {
    print('❌ Hata: ${sonuc.mesaj}');
  }
}
```

---

### **Örnek 1b: HIZLI Bağlantı (MAC Adresi ile — v3.2)**

```dart
import 'services/ble_service.dart';

void main() async {
  final ble = BleService();
  
  // ⚡ HIZLI BAĞLANTI — MAC adresine doğrudan bağlan (50-100ms)
  // BtKonstanlar.defaultMacAddress = '00:18:E4:40:00:06'
  final sonuc = await ble.hizliBaglan();
  if (sonuc.basarili) {
    print('✅ HC-06 HIZLI bağlantısı kuruldu!');
  } else {
    print('❌ Hata: ${sonuc.mesaj}');
  }
}
```

---

### **Örnek 2: Durum Dinamiklerini Dinle**

```dart
import 'services/ble_service.dart';

void kuruBaglantiDinamikleri() {
  final ble = BleService();
  
  // Bağlantı durumu değişikliklerini dinle
  ble.durumStream.listen((durum) {
    print('🔗 ${durum.metin}');
  });
  
  // Arduino durum güncellemelerini dinle
  ble.arduinoDurumStream.listen((durum) {
    if (durum.depremAlgilandi) {
      print('⚠️ DEPREM ALGILANDI!');
      // Alarm UI'sini göster
    }
  });
}
```

---

### **Örnek 3: Manuel Cihaz Seçimi**

```dart
import 'services/ble_service.dart';

void manuelCihazSecimi() async {
  final ble = BleService();
  
  // Eşleşmiş cihazları listele
  final cihazlar = await ble.eslesmisCihazlariListele();
  
  if (cihazlar.isEmpty) {
    print('❌ Eşleşmiş cihaz yok!');
    return;
  }
  
  print('📱 Eşleşmiş Cihazlar:');
  int index = 0;
  cihazlar.forEach((ad, mac) {
    print('$index) $ad → $mac');
    index++;
  });
  
  // Örnek: İlk cihaza bağlan
  final macAdres = cihazlar.values.first;
  final sonuc = await ble.baglanMacAdresine(macAdres);
  print(sonuc.basarili ? '✅ ${sonuc.mesaj}' : '❌ ${sonuc.mesaj}');
}
```

---

### **Örnek 4: Komut Gönder ve Yanıt Oku**

```dart
import 'services/ble_service.dart';

Future<void> komutGonder() async {
  final ble = BleService();
  
  // Elektrikği aç
  var sonuc = await ble.elektrikAktifEt();
  print(sonuc.basarili ? '✅ Elektrik açıldı' : '❌ Hata');
  
  // Doğalgazı aç
  sonuc = await ble.dogalgazAktifEt();
  print(sonuc.basarili ? '✅ Doğalgas açıldı' : '❌ Hata');
  
  // Durum iste
  sonuc = await ble.durumIste();
  print(sonuc.basarili ? '✅ Durum istendi' : '❌ Hata');
}
```

---

## 🔐 İzinler (Permissions)

### **AndroidManifest.xml (Zaten Yapılandırılmış):**

```xml
<!-- Android 12+ İzinleri -->
<uses-permission android:name="android.permission.BLUETOOTH_SCAN"
    android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />

<!-- Android 11 ve Altı İzinleri -->
<uses-permission android:name="android.permission.BLUETOOTH"
    android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN"
    android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"
    android:maxSdkVersion="30" />

<!-- HC-06 Bluetooth Donanım Gerekliliği -->
<uses-feature android:name="android.hardware.bluetooth" 
    android:required="true" />
```

### **Runtime İzinleri (pubspec.yaml):**

```yaml
dependencies:
  permission_handler: ^11.0.0  # İzin yönetimi
  flutter_bluetooth_serial: ^0.4.0  # Bluetooth SPP
```

---

## 🔧 Sorun Giderme

### **✅ HC-06 Eşleşmiş Listede Varsa — Hızlı Bağlantı (v3.2)**

**Değişiklikler (v3.2):**
- ✅ **Redundant izin kontrolü kaldırıldı** — `_eslesmisCihazBul()` içinde tekrar kontrol yapılmıyor
- ✅ **İzin dialog optimizasyonu** — Eğer izin zaten verilmişse dialog açılmıyor
- ✅ **Doğrudan MAC adresine bağlantı** — Eşleşmiş cihaz bulunduğunda soket bağlantısı hızlı kurulur

**Bağlantı Flow (v3.2):**
```
Bluetooth Bağlan Button
    ↓
ADIM 1: İzin Kontrolü
    • Eğer izin zaten verilmişse → Dialog açılmıyor (⚡ Hızlı)
    • Yoksa → Permission dialog açılıyor
    ↓
ADIM 2a: Eşleşmiş Cihazlar Listeleme
    • HC-06 listede var → HC-06 döndür (10-50ms)
    • HC-06 yok → NULL döndür
    ↓
ADIM 2b (isteğe bağlı): Discovery Taraması
    • Eğer 2a NULL döndürdüyse → 15 saniye aranır
    ↓
ADIM 3: Soket Bağlantısı
    • MAC adresi + SPP UUID ile bağlan
    • Başarılı → ADIM 4'e
    • Başarısız → Hata mesajı + çözüm önerileri
    ↓
ADIM 4: Veri Akışı
    • InputStream/OutputStream dinleme başlıyor
    • ✅ Bağlantı açık ve veri akışında
```

**Toplam Bağlantı Süresi (v3.2):**
- HC-06 eşleşmiş listede varsa: **50-200ms** (çok hızlı ✨)
- HC-06 yeni cihaz ise (discovery): **15-20 saniye** + socket time

---

### **❌ HC-06 Görünüyor Ama Eşleştirildi Olarak Görmüyor**

**Problem:** HC-06'yı Bluetooth listesinde görüyorsunuz, ekleyebiliyorsunuz ama "Eşleştirildi" (paired) olarak görmüyorsunuz.

**Yazılım Tarafındaki Çözüm (v3.2+):**

BleService artık şu iyileştirmeleri yapıyor:
1. ✅ **Redundant izin kontrolü kaldırıldı** — `_eslesmisCihazBul()` izin kontrol etmiyor (hızlı!)
2. ✅ **İzin dialog optimizasyonu** — İzin zaten verilmişse status kontrol yapılıyor, request() açılmıyor
3. ✅ **Doğrudan MAC bağlantısı** — Eşleşmiş cihaz bulunduğunda soket bağlantısı 50-200ms'de tamamlanıyor
4. ✅ **Spesifik hata mesajları** — Socket hatası vs izin hatası ayrı ayrı raporlanıyor

**Çözmek İçin:**

**Seçenek 1: Manuel Eşleştirme (Önerilen)**
```
1. Telefonun Ayarları açın
2. Bluetooth > HC-06'nın yanındaki ⚙️ (Ayarlar) tikle
3. "Çıkar" diye bir option varsa, onu tikle (eski eşleştirmeyi sil)
4. Bluetooth açık durumda kalması sağlayıp "HC-06" cihazı tekrar "Eşleştir"e tıkla
5. PIN sorması gerekir → 1234 gir
6. "Eşleştirildi" yazacak
```

**Seçenek 2: Uygulamada Otomatik Bağlantı**
```dart
// App.dart veya başlangıç ekranında:
Future<void> baglanHCYeSutunKapat() async {
  final ble = BleService();
  
  // Eşleşmiş cihazları listele
  final eslesmisler = await ble.eslesmisCihazlariListele();
  
  if (eslesmisler.isEmpty) {
    print('ℹ️ Eşleşmiş HC-06 yok — keşif yapılacak');
  } else {
    print('✅ Eşleşmiş cihazlar: $eslesmisler');
  }
  
  // Otomatik bağlan (eşleşmiş varsa hızlı, yoksa keşifle bul)
  final sonuc = await ble.baglan();
  print(sonuc.mesaj);
}
```

**v3.1'deki İyileştirmeler:**

```
ADIM 2a: Eşleşmiş Cihazları Listeleme
├─ ✅ İzin kontrolü (BLUETOOTH_SCAN)
├─ ✅ getBondedDevices() çağrısı
├─ ✅ HC-06 bulundu → ADIM 3'e (eşleşmiş!)
└─ ❌ HC-06 bulunamadı → ADIM 2b'ye (keşif yap)
   
ADIM 2b: Keşif Taraması
├─ ✅ 15 saniye HC-06 arıyor
├─ ✅ HC-06 bulundu → ADIM 3'e (eşleşmemiş uyarısı!)
└─ ❌ HC-06 bulunamadı → Hata mesajı (eşleştirme talimatları ile)
```

---

### **❌ HC-06 Bulunamıyor**

**Çözüm:**
1. ✅ HC-06'nın gücü açık mı? (LED yanıyor/yanıp sönüyor)
2. ✅ Telefonun Bluetooth'u açık mı?
3. ✅ **HC-06 cihaz adını kontrol et**: 
   - Varsayılan (tavsiye): **"HC-06"** (AT komutu ile değiştirilmemiş)
   - AT komutu ile değiştirilmişse: **"ODAK_Sistem"** veya başka bir ad
4. ✅ Telefonla HC-06'yı manual olarak eşleştir (PIN: 1234)
5. ✅ App'in `BLUETOOTH_SCAN` izni var mı?
6. ✅ HC-06'yı yakına koy (mesafe problemi)

**Hızlı Kontrol:**
```dart
// İzin kontrolü
bool kaliciRed = await BleService().izinKaliciRedMi();
if (kaliciRed) {
  print('❌ İzin kalıcı olarak reddedildi! '
        'Ayarlar > Uygulama > ODAK > İzinler\'den açın');
}

// Eşleşmiş cihazları listele — HC-06 adını bul
Map<String, String> cihazlar = await BleService().eslesmisCihazlariListele();
cihazlar.forEach((ad, mac) {
  print('📱 $ad → $mac');
});
```

**AT Komutu ile Adı Değiştirdiysen:**
```dart
// HC-06'nın adını bul, örn: "MyBluetooth" gibi bir ad gördüysen
// BleService'i şöyle update et:
// static const String cihazAdi = 'MyBluetooth';
```

---

### **❌ HC-06 Bulunamıyor**

**Çözüm:**
1. ✅ HC-06'nın gücü açık mı? (LED yanıyor/yanıp sönüyor)
2. ✅ Telefonun Bluetooth'u açık mı?
3. ✅ HC-06 cihaz adını kontrol et: 
   - Varsayılan (tavsiye): **"HC-06"** (AT komutu ile değiştirilmemiş)
   - AT komutu ile değiştirilmişse: **"ODAK_Sistem"** veya başka bir ad
4. ✅ **BLUETOOTH_SCAN İzni Var mı?** (v3.1+ tarafından kontrol edilir)
   - Ayarlar > ODAK > İzinler > "Yakındaki Cihazlar" → İzin Ver
5. ✅ HC-06'yı telefonla manual olarak eşleştir (PIN: 1234)
6. ✅ Cihazı yakına koy (mesafe < 1 metre)

**Hızlı Kontrol (v3.1+):**

BleService şimdi aşağıdaki kontrolleri yapıyor:
- ✅ İzin kontrolü (ADIM 1)
- ✅ Eşleşmiş listeme (ADIM 2a) — başarısız olursa keşif yapıyor
- ✅ Discovery taraması (ADIM 2b) — keşifle HC-06'yı buluyorDebug log'u çıktı panelinde görmek için:
```dart
flutter run -v    // Verbose modda çalıştır
```

Çıktıda bu satırları arayın:
```
[BT] ADIM 2a: X adet eşleşmiş cihaz bulundu
    ✅ Eşleşmiş: HC-06 ➜ 00:11:22:33:44:55      // HC-06 zaten eşleşmiş
    ℹ️ Eşleşmiş cihaz yok — keşif yapılacak      // Yeni cihaz, keşif yapılacak
[BT] ADIM 2b: HC-06 keşif taraması başlıyor...
    ✅ HC-06 keşifle bulundu                    // Keşifle bulundu, bağlanılacak
    ❌ HC-06 keşifle de bulunamadı              // Hiç bulunamadı
```

---

### **❌ Android Ayarlarında "Eşleşmemiş" Gösteriyor Ama App Bağlanabiliyor**

**Sebep:** flutter_bluetooth_serial, bonded olmayan cihazlara da discovery yoluyla bağlanabiliyor (socket level).

**Bu Normal mi?** Evet, Bluetooth SPP protokolü izin verir.

**Soruna Yol Açar mı?**
- ✅ Bağlantı açık olduğu sürece veri akışı sorunsuz
- ❌ Bağlantı kapatılınca yeniden bağlanmak daha uzun sürer
- ❌ Bonded olmayan cihazlar Android'in "Paired Devices" listesinde görünmüyor

**Çözüm:** Cihazı Android Bluetooth ayarlarından manuel olarak eşleştirin:
```
1. Ayarlar > Bluetooth > HC-06 > Eşleştir
2. PIN sorması gerekir → 1234 girin
3. Ardından bonded olacak
```

---

### **❌ Bağlantı Açılıyor Ama Veri Gelmiyor**

**Çözüm:**
1. Arduino kodu HC-06'ya `\n` ile veri gönderiyor mu?
2. Arduino baud rate 9600 mı?
3. HC-06 TX/RX kablolarını kontrol et (değiştirilmiş mi?)
4. Voltaj düşürme direnci RX'te var mı?

```dart
// Debug: Ham veriyi dinle
BleService().yanitStream.listen((msg) {
  print('[DEBUG] Gelen: $msg');
});
```

---

### **❌ "Kalıcı Red" Hatası**

**Sebep:** Birisi Bluetooth izinlerini "Reddet" diyerek sistem kapat mı? (v3.1+ bunu yakalıyor)

**Çözüm:**
Telefonun Ayarlar > Uygulama > ODAK > İzinler'e git ve:
1. "Yakındaki Cihazlar" → İzin Ver
2. (Android 12+ ise) "Exact location" → İzin Ver (zorunlu değil ama tarama daha hızlı olur)

**v3.1+ Debug Output:**
```
[BT] ⚠️ ADIM 2a: BLUETOOTH_SCAN izni yok — bonded devices okunamıyor
     → Cihazı manual olarak Android Ayarları > Bluetooth\'ten eşleştirin
```

Bu mesajı görürseniz → Ayarlar > İzinler kontrol edin.

---

### **❌ "Kalıcı Red" Programatik Çözümü**

İsteğe bağlı — izin ayarlarını uygulamadan açmak istiyorsanız:

```dart
// pubspec.yaml'a ekle:
dependencies:
  app_settings: ^5.1.1

// Kod:
import 'package:app_settings/app_settings.dart';

Future<void> izinAyarlariniAc() async {
  await AppSettings.openAppSettings(
    asAnotherTask: true,
  );
}
```

---

### **❌ Bağlantı Bir Süre Sonra Kopuyor**

**Çözüm:**
1. HC-06 ve Arduino arasında güç sorunu var mı? (5V sızdırıyor mu?)
2. Arduino PIN 0/1 başka sensör tarafından kullanılıyor mu?
3. HC-06 ısınıyor mu? (Soğutma gerekli mi?)
4. Düşük batarya (< 3.3V) sorunu mu?

---

### **❌ "Komut gönder" çalışmıyor

**Kontrol Listesi:**
- [ ] `BleService().bagliMi == true` mi?
- [ ] Arduino `CMD:` başlığını kaldırıyor mu?
- [ ] Arduino `OK:` veya `ERR:` yanıtı gönderiyor mu?

```dart
// Durum kontrol
print('Bağlı mı: ${BleService().bagliMi}');
print('Son durum: ${BleService().sonDurum.metin}');
```

---

## 📊 Protokol Referansı

### **Arduino → Telefon (InputStream):**
```
STATUS:deprem=0,gaz=1,elek=1,sayac=0,esik=3.0,uptime=123
ALARM:deprem_algilandi
OK:elektrik_ac
ERR:bilinmeyen_komut
INFO:system_ready
```

### **Telefon → Arduino (OutputStream):**
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

## 🚀 Hızlı Başlangıç Kodu

```dart
import 'package:flutter/material.dart';
import 'services/ble_service.dart';

void main() {
  runApp(const OdakApp());
}

class OdakApp extends StatefulWidget {
  const OdakApp({Key? key}) : super(key: key);

  @override
  State<OdakApp> createState() => _OdakAppState();
}

class _OdakAppState extends State<OdakApp> {
  final ble = BleService();
  bool bagli = false;

  @override
  void initState() {
    super.initState();
    // Durumu dinle
    ble.durumStream.listen((durum) {
      setState(() {
        bagli = durum == BtDurum.bagli;
      });
    });
  }

  Future<void> _hizliBaglan() async {
    // ⚡ HIZLI BAĞLANTI: MAC adresi ile doğrudan bağlan (50-100ms)
    final sonuc = await ble.hizliBaglan();
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(sonuc.mesaj)),
    );
  }

  Future<void> _otomatikBaglan() async {
    // 🔍 OTOMATİK BAĞLANTI: Eşleşmiş listede ara, yoksa discovery yap
    final sonuc = await ble.baglan();
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(sonuc.mesaj)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('ODAK — HC-06'),
          actions: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: bagli
                    ? const Text('✅ Bağlı', style: TextStyle(fontWeight: FontWeight.bold))
                    : const Text('❌ Bağlı Değil'),
              ),
            ),
          ],
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // ⚡ HIZLI BAĞLANTI BUTONU
              ElevatedButton.icon(
                onPressed: _hizliBaglan,
                icon: const Icon(Icons.flash_on),
                label: const Text('⚡ Hızlı Bağlan (50-100ms)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                ),
              ),
              const SizedBox(height: 20),
              // 🔍 OTOMATİK BAĞLANTI BUTONU
              ElevatedButton.icon(
                onPressed: _otomatikBaglan,
                icon: const Icon(Icons.bluetooth_connected),
                label: const Text('🔍 Otomatik Bağlan'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                ),
              ),
              const SizedBox(height: 20),
              // KOMUT BUTONU
              if (bagli)
                ElevatedButton(
                  onPressed: () => ble.elektrikAktifEt(),
                  child: const Text('Elektriği Aç'),
                ),
              const SizedBox(height: 10),
              // DURUM GÖSTERİ
              StreamBuilder<String>(
                stream: ble.yanitStream,
                builder: (context, snapshot) {
                  return Text(
                    snapshot.data ?? 'Bekleniyor...',
                    style: const TextStyle(fontSize: 18),
                    textAlign: TextAlign.center,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    ble.kapat();
    super.dispose();
  }
}
```

---

**📝 Versiyon**: 3.2  
**📅 Son Güncelleme**: 21 Nisan 2026  
**✨ Yeni**: Hızlı bağlantı optimizasyonu - redundant izin kontrolü kaldırıldı, dialog suppression eklendi  
**✅ Önceki**: Eşleştirme sorunları yazılım tarafından düzeltildi (izin kontrolleri, recovery mechanism)  
**👤 Bakım**: ODAK Ekibi
