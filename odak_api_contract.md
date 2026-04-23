# ODAK — Bluetooth Serial Protokol Kontratı (v2.0)

Hazırlayan: ODAK Geliştirme Ekibi  
Versiyon: 2.0  
Tarih: 2026-04-20

---

## Genel Kurallar

- **Donanım**: Arduino Uno + HC-06 Bluetooth modülü
- **Protokol**: Bluetooth SPP (Serial Port Profile)
- **Baud Rate**: 9600
- **HC-06 Cihaz Adı**: `HC-06` (veya varsayılan `HC-06`)
- **HC-06 PIN**: `1234`
- **Veri formatı**: Düz metin (text), satır sonu: `\n`
- **Karakter kodlaması**: UTF-8

---

## Mesaj Formatları

### 1. Durum Mesajı (Arduino → Telefon)

Her 2 saniyede otomatik gönderilir.

```
STATUS:deprem=X,gaz=X,elek=X,sayac=X,esik=X.X,uptime=X
```

| Alan | Tip | Açıklama |
|------|-----|----------|
| `deprem` | 0/1 | 0 = yok, 1 = deprem algılandı |
| `gaz` | 0/1 | 0 = kapalı (alarm), 1 = açık (güvende) |
| `elek` | 0/1 | 0 = kesik (alarm), 1 = açık (güvende) |
| `sayac` | int | Ardışık eşik aşım sayısı (0-2 normal, 3 = tetikleme) |
| `esik` | float | Deprem sapma eşiği (m/s²) |
| `uptime` | int | Çalışma süresi (saniye) |

**Örnek:**
```
STATUS:deprem=0,gaz=1,elek=1,sayac=0,esik=3.0,uptime=3600
```

---

### 2. Komut Mesajı (Telefon → Arduino)

```
CMD:<komut_adi>
```

| Komut | Açıklama |
|-------|----------|
| `dogalgaz_ac` | Gaz alarmını kaldır, gaz sistemi aç |
| `elektrik_ac` | Elektrik alarmını kaldır, elektriği ver |
| `reset_alarm` | Tüm alarmları sıfırla (gaz + elektrik aç) |
| `durum` | Anlık durum isteği (STATUS yanıtı tetiklenir) |

**Örnekler:**
```
CMD:dogalgaz_ac
CMD:elektrik_ac
CMD:reset_alarm
CMD:durum
```

---

### 3. Yanıt Mesajları (Arduino → Telefon)

#### Başarılı yanıt:
```
OK:<komut_adi>
```

#### Hata yanıtı:
```
ERR:<hata_aciklamasi>
```

#### Alarm bildirimi:
```
ALARM:deprem_algilandi
```

#### Bilgi mesajı:
```
INFO:<bilgi>
```

| Mesaj | Açıklama |
|-------|----------|
| `OK:dogalgaz_ac` | Gaz açıldı |
| `OK:elektrik_ac` | Elektrik verildi |
| `OK:reset_alarm` | Tüm alarmlar sıfırlandı |
| `ERR:bilinmeyen_komut:xxx` | Bilinmeyen komut |
| `ERR:gecersiz_format` | CMD: öneki eksik |
| `ERR:buffer_tasti` | Gelen veri çok uzun |
| `ERR:mpu6050_bulunamadi` | Sensör bağlantı hatası |
| `ALARM:deprem_algilandi` | Deprem tespit edildi |
| `INFO:sistem_hazir` | Sistem başlatıldı |
| `INFO:kalibrasyon_basliyor` | Kalibrasyon başlıyor |

---

## Flutter Servis Eşleşmesi

| Arduino Mesajı | Flutter Metodu | Açıklama |
|---------------|---------------|----------|
| `STATUS:...` | `BleService.arduinoDurumStream` | Otomatik durum güncellemesi |
| `OK:` / `ERR:` | `BleService.yanitStream` | Komut yanıtı |
| `ALARM:` | `BleService.arduinoDurumStream` | Deprem uyarısı |
| `CMD:dogalgaz_ac` | `BleService.dogalgazAktifEt()` | Gaz aç |
| `CMD:elektrik_ac` | `BleService.elektrikAktifEt()` | Elektrik ver |
| `CMD:reset_alarm` | `BleService.alarmSifirla()` | Alarm sıfırla |
| `CMD:durum` | `BleService.durumIste()` | Durum iste |

---

## Pin Bağlantıları

```
Arduino Uno          Komponent
─────────────────────────────────
Pin 4           →    LED Kırmızı (Deprem)
Pin 5           →    LED Yeşil   (Gaz)
Pin 6           →    LED Mavi    (Elektrik)
Pin 7           →    Buzzer
Pin 10 (RX)     ←    HC-06 TX
Pin 11 (TX)     →    HC-06 RX  (voltaj bölücü!)
A4 (SDA)        →    MPU6050 SDA
A5 (SCL)        →    MPU6050 SCL
5V              →    HC-06 VCC, MPU6050 VCC
GND             →    Ortak GND
```

---

## Sorun Giderme

| Sorun | Çözüm |
|-------|-------|
| "ODAK_Sistem" bulunamadı | HC-06 güç kontrolü, eşleştirme |
| Bluetooth bağlanamadı | PIN: 1234 doğru mu? |
| Veri gelmiyor | TX/RX kablo kontrolü, baud rate 9600 |
| Garip karakterler | Voltaj bölücü kontrolü |
| Deprem sürekli algılanıyor | `esik_deger` artırın |
