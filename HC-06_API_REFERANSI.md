# HC-06 API Hızlı Referans Kartı (v3.2)

## 🚀 Hızlı Bağlantı (v3.2 — 50-100ms)

HC-06 eşleşmiş listede varsa bağlantı 50-100ms'de tamamlanıyor.
- ✅ Redundant izin kontrolü kaldırıldı  
- ✅ İzin dialog suppression (dialog açılmıyor)
- ✅ Doğrudan MAC adresine socket bağlantısı

---

## ⚠️ ÖNEMLİ: Cihaz Adı Ayarı

**HC-06 varsayılan adı:** `HC-06` ✅ (AT komutu ile değiştirilmemiş)  
**Opsiyonel ad:** `ODAK_Sistem` (AT+NAME komutu gönderildiyse)

---

## 🔗 Bağlantı Yönetimi

### **Bağlan — 3 Yol**

**1️⃣ Otomatik (Eşleşmiş listede ara, yoksa discovery yap)**
```dart
// ADIM 1-4 otomatik — Eşleşmiş varsa 50-100ms
final sonuc = await BleService().baglan();
print(sonuc.mesaj);  // Başarı/hata mesajı
```

**2️⃣ ⚡ HIZLI — MAC Adresine Doğrudan Bağlan (50-100ms)**
```dart
// En Hızlısı — HC-06 MAC: 00:18:E4:40:00:06 (BtKonstanlar.defaultMacAddress)
final sonuc = await BleService().hizliBaglan();
print(sonuc.mesaj);

// Alternatif MAC:
await BleService().baglanMacAdresine('00:18:E4:40:00:06');
```

**3️⃣ Manuel MAC ile Bağlan**
```dart
await BleService().baglanMacAdresine('00:11:22:33:44:55');
```

### **Bağlantı Durumu**
```dart
bool bagliMi = BleService().bagliMi;                    // true/false
BtDurum sonDurum = BleService().sonDurum;               // Mevcut durum
```

### **Bağlantıyı Kapat**
```dart
await BleService().baglantiKapat();
```

---

## 📱 Cihaz Yönetimi

### **Eşleşmiş Cihazları Listele**
```dart
Map<String, String> cihazlar = await BleService().eslesmisCihazlariListele();
// Çıktı: {'HC-06': '00:11:22:33:44:55', 'HC-05': 'AA:BB:CC:...'}

cihazlar.forEach((ad, mac) {
  print('$ad → $mac');
});
```

### **İzin Kontrolleri**
```dart
// Runtime izinleri iste
bool izinlerOk = await BleService().izinleriKontrolEt();

// Kalıcı red kontrol et
bool kaliciRed = await BleService().izinKaliciRedMi();

// Bluetooth açık mı?
bool btAcik = await BleService().bluetoothAcikMi();
```

---

## 📡 Komut Gönderimi (OutputStream)

### **Hazır Komutlar**
```dart
await BleService().elektrikAktifEt();      // Elektriği aç
await BleService().dogalgazAktifEt();      // Doğal gazı aç
await BleService().alarmSifirla();         // Alarmı sıfırla
await BleService().durumIste();            // Durum iste
```

### **Ham Veri Gönder**
```dart
await BleService().gonderRawVeri('1');     // "1" gönder
await BleService().gonderRawVeri('0');     // "0" gönder
await BleService().gonderRawVeri('A\n');   // "A\n" gönder
await BleService().gonderRawVeri('ABC');   // "ABC" gönder
```

---

## 📥 Veri Alma (InputStream)

### **Bağlantı Durumu Dinle**
```dart
BleService().durumStream.listen((durum) {
  print('🔗 ${durum.metin}');
  
  switch(durum) {
    case BtDurum.hazir:           print('Hazır'); break;
    case BtDurum.taraniyor:       print('Taranıyor'); break;
    case BtDurum.bulundu:         print('Bulundu'); break;
    case BtDurum.baglaniyor:      print('Bağlanıyor'); break;
    case BtDurum.bagli:           print('✅ Bağlı'); break;
    case BtDurum.komutGonderildi: print('Komut gönderildi'); break;
    case BtDurum.hata:            print('❌ Hata'); break;
    case BtDurum.kapali:          print('Bluetooth kapalı'); break;
  }
});
```

### **Arduino Durum Güncellemeleri**
```dart
BleService().arduinoDurumStream.listen((durum) {
  print('📊 Arduino Durumu:');
  print('  Deprem: ${durum.depremAlgilandi}');
  print('  Gaz Açık: ${durum.gazAcik}');
  print('  Elektrik Açık: ${durum.elektrikAcik}');
  print('  Deprem Sayacı: ${durum.depremSayaci}');
  print('  Eşik: ${durum.esikDeger}');
  print('  Uptime: ${durum.uptimeSn}s');
  
  if (durum.depremAlgilandi) {
    print('⚠️ DEPREM ALGILANDI!');
  }
});
```

### **Raw Yanıtlar**
```dart
BleService().yanitStream.listen((mesaj) {
  print('📝 Yanıt: $mesaj');
  
  if (mesaj.startsWith('OK:')) {
    print('✅ Komut başarıldı');
  } else if (mesaj.startsWith('ERR:')) {
    print('❌ Komut hatası: $mesaj');
  } else if (mesaj.startsWith('ALARM:')) {
    print('⚠️ Alarm: $mesaj');
  }
});
```

---

## ⚙️ Kurulum & Yapılandırma

### **pubspec.yaml**
```yaml
dependencies:
  flutter_bluetooth_serial: ^0.4.0
  permission_handler: ^11.0.0
```

### **AndroidManifest.xml** (Zaten yapılandırılmış)
```xml
<!-- Android 12+ -->
<uses-permission android:name="android.permission.BLUETOOTH_SCAN"
    android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />

<!-- Android 11- -->
<uses-permission android:name="android.permission.BLUETOOTH"
    android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN"
    android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"
    android:maxSdkVersion="30" />
```

---

## 🔄 4 Adımlık Algoritma

```dart
// ADIM 1: İzinleri Alma
bool izinlerOk = await BleService().izinleriKontrolEt();
if (!izinlerOk) return;

// ADIM 2: Eşleşmiş Cihazları Listeleme
Map<String, String> cihazlar = await BleService().eslesmisCihazlariListele();

// ADIM 3: Bağlantı Kurma (Soket)
await BleService().baglanMacAdresine('00:11:22:33:44:55');
// VEYA
await BleService().baglan();  // Otomatik

// ADIM 4: Veri Akışı
await BleService().elektrikAktifEt();     // Gönder (OutputStream)
BleService().arduinoDurumStream.listen((d) {  // Oku (InputStream)
  print('Durum: $d');
});
```

---

## 📊 Veri Modelleri

### **ArduinoDurum**
```dart
class ArduinoDurum {
  final bool   depremAlgilandi;    // true/false
  final bool   gazAcik;            // true/false
  final bool   elektrikAcik;       // true/false
  final int    depremSayaci;       // 0-N
  final double esikDeger;          // 0.0-10.0
  final int    uptimeSn;           // Saniye
}

// Örnek parse
ArduinoDurum durum = ArduinoDurum.fromStatusLine(
  'STATUS:deprem=0,gaz=1,elek=1,sayac=0,esik=3.0,uptime=123'
);
```

### **BtIslemSonucu**
```dart
class BtIslemSonucu {
  final bool   basarili;  // true/false
  final String mesaj;     // "Bağlantı kuruldu..." vb.
}

// Kullanım
final sonuc = await BleService().baglan();
if (sonuc.basarili) {
  print('✅ ${sonuc.mesaj}');
} else {
  print('❌ ${sonuc.mesaj}');
}
```

---

## 🐛 Hata Durumları

| Hata | Çözüm |
|------|-------|
| "İzin reddedildi" | Ayarlar > Yakındaki Cihazlar |
| "HC-06 bulunamadı" | Telefon ↔ HC-06 eşleştir (PIN: 1234) |
| "Bağlantı başarısız" | HC-06'yı yakına koy, powered on |
| "Veri gelmiyor" | Arduino baud rate 9600 kontrol et |
| "Kalıcı red hatası" | Uygulamayı kaldır ve yeniden yükle |

---

## 🎯 Sık Kullanılan Kombinasyonlar

### **Kombinasyon 1: İlk Bağlantı**
```dart
await BleService().baglan();
BleService().durumStream.listen((d) {
  if (d == BtDurum.bagli) {
    print('✅ Bağlı!');
  }
});
```

### **Kombinasyon 2: Durum İzleme**
```dart
BleService().arduinoDurumStream.listen((durum) {
  print('Durum: $durum');
});
await BleService().durumIste();  // Durum iste
```

### **Kombinasyon 3: Komut Gönderme**
```dart
await BleService().elektrikAktifEt();
BleService().yanitStream.listen((yanit) {
  if (yanit.startsWith('OK:')) {
    print('✅ Komut başarıldı');
  }
});
```

### **Kombinasyon 4: Manuel Cihaz Seçimi**
```dart
var cihazlar = await BleService().eslesmisCihazlariListele();
String seciliMac = cihazlar['HC-06']!;
await BleService().baglanMacAdresine(seciliMac);
```

---

## 📞 HC-06 AT Komutları

```
AT              // Test
AT+NAME=ODAK    // Adı "ODAK" yap
AT+PSWD=1234    // PIN'i 1234'e ayarla
AT+BAUD=9       // 9600 baud ayarla
AT+ROLE=0       // Slave mod (varsayılan)
```

---

## 🎨 Widget Örneği

```dart
StreamBuilder<BtDurum>(
  stream: BleService().durumStream,
  initialData: BleService().sonDurum,
  builder: (context, snapshot) {
    final durum = snapshot.data!;
    return Text(durum.metin);  // "Bağlı", "Bağlanıyor", vb.
  },
)
```

---

## 📝 Protokol

### **Telefon → Arduino**
```
CMD:elektrik_ac\n
CMD:dogalgaz_ac\n
CMD:reset_alarm\n
CMD:durum\n
1
0
A\n
```

### **Arduino → Telefon**
```
STATUS:deprem=0,gaz=1,elek=1,sayac=0,esik=3.0,uptime=123
OK:elektrik_ac
ERR:bilinmeyen_komut
ALARM:deprem_algilandi
INFO:system_ready
```

---

## 🔗 UUID Referansı

| Cihaz Tipi | UUID |
|-----------|------|
| Bluetooth SPP | `00001101-0000-1000-8000-00805F9B34FB` |
| HC-06 Standart | `00001101-0000-1000-8000-00805F9B34FB` |
| HC-05 Standart | `00001101-0000-1000-8000-00805F9B34FB` |

**Not:** flutter_bluetooth_serial otomatik SPP UUID'sini kullanır, manuel belirtmeye gerek yoktur.

---

## 📚 Kaynaklar

- 📖 [HC-06_ENTEGRASYON_REHBERI.md](HC-06_ENTEGRASYON_REHBERI.md) — Detaylı
- 📋 [README.md](README.md) — Proje Özeti
- 📊 [HC-06_GUNCELLEME_OZETI.md](HC-06_GUNCELLEME_OZETI.md) — Değişiklikler
- 🛠️ [bluetooth_control_screen.dart](lib/screens/bluetooth_control_screen.dart) — Örnek UI

---

**Versiyon:** 3.0 | **Güncelleme:** 2026 | **Durum:** ✅ Hazır
