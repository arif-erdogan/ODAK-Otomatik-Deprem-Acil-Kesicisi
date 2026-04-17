# ODAK — ESP32 Firmware Kurulum Kılavuzu (v1.1)

## Dosyalar

```
esp32_firmware/
├── odak_esp32.ino   ← Arduino'ya yükleyeceğin ana dosya
├── secrets.h        ← (opsiyonel, şu an kullanılmıyor — SoftAP modu)
└── KURULUM.md       ← Bu dosya
```

---

## Haberleşme Mimarisi

```
┌────────────────────┐         WiFi SoftAP         ┌──────────────────┐
│   ESP32-S3 Mini    │ ◄───────────────────────────►│   Mobil Uygulama │
│                    │   SSID: ODAK_Sistem          │   (Flutter)      │
│  • MPU6050 Sensör  │   Şifre: odak1234           │                  │
│  • LED×3 + Buzzer  │   IP: 192.168.4.1           │  WiFi → Firebase │
│  • REST API Server │                             │  → BLE fallback  │
└────────────────────┘                             └──────────────────┘
```

**Bağlantı Yöntemi:** ESP32 kendi WiFi ağını oluşturur (SoftAP).
Telefon "ODAK_Sistem" ağına bağlanıp 192.168.4.1 üzerinden iletişim kurar.

> ⚠️ SoftAP modunda telefon internet bağlantısını kaybeder.
> Firebase sadece telefon internete bağlıyken (ör. mobil veri) çalışır.

---

## Adım 1 — Arduino IDE Hazırlığı

### ESP32 Board Package

1. Arduino IDE → **File → Preferences**
2. "Additional boards manager URLs" alanına ekle:
   ```
   https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json
   ```
3. **Tools → Board → Boards Manager** → "esp32" ara → **Install**

### Kütüphaneleri Yükle

**Tools → Manage Libraries** (Ctrl+Shift+I):

| Arama terimi | Yüklenecek kütüphane |
|-------------|----------------------|
| `Adafruit MPU6050` | "Adafruit MPU6050" by Adafruit |
| `Adafruit Unified Sensor` | "Adafruit Unified Sensor" by Adafruit |
| `ArduinoJson` | "ArduinoJson" by Benoit Blanchon (v6.x) |

> `WiFi`, `WebServer`, `Wire` kütüphaneleri ESP32 board package ile **otomatik gelir**.

---

## Adım 2 — Pin Kontrolü

`odak_esp32.ino` dosyasındaki pin tanımları:

```cpp
#define LED_RED   10   // Kırmızı LED — Deprem alarmı
#define LED_GREEN 17   // Yeşil LED   — Doğalgaz alarmı
#define LED_BLUE  5    // Mavi LED    — Elektrik alarmı
#define BUZZER    6    // Buzzer      — Sesli alarm
// MPU6050: varsayılan SDA/SCL (Wire.begin())
```

---

## Adım 3 — ESP32'ye Yükle

1. **Tools → Board** → "ESP32S3 Dev Module" seç
2. **Tools → Port** → COM portunu seç
3. **Upload** butonuna bas
4. "Done uploading" mesajı görünce tamam

---

## Adım 4 — WiFi'a Bağlan ve Test Et

1. **Tools → Serial Monitor** (Ctrl+Shift+M) → Baud: **115200**
2. Şunu göreceksin:

```
================================
  ODAK — Deprem Güvenlik Sistemi
  ESP32-S3 Mini  |  SoftAP Modu
  Versiyon: 1.1
================================

[WiFi] SoftAP baslatildi
[WiFi] SSID    : ODAK_Sistem
[WiFi] Sifre   : odak1234
[WiFi] IP      : 192.168.4.1

[HTTP] Server port 80'de basladi
```

3. Telefondan **"ODAK_Sistem"** WiFi ağına bağlan (şifre: `odak1234`)
4. Tarayıcıdan test:
   ```
   http://192.168.4.1/api/ping   → {"ok":true}
   http://192.168.4.1/api/status → {"ok":true,"deprem":false,...}
   ```

---

## Adım 5 — Mobil Uygulamayı Bağla

1. ODAK uygulamasını aç
2. AppBar'daki WiFi badge'ine dokun
3. **"SoftAP ile Otomatik Bağlan"** butonuna bas
4. Yeşil "WiFi ✓" görünürse bağlantı tamam!

---

## API Endpoints

| Method | Endpoint | Açıklama |
|--------|----------|----------|
| GET | `/api/ping` | Canlılık kontrolü |
| GET | `/api/status` | Sistem durumu |
| POST | `/api/command` | Komut gönder |

### Komutlar (POST body):
```json
{"command": "dogalgaz_ac"}    // Gaz alarmını kaldır
{"command": "elektrik_ac"}    // Elektrik alarmını kaldır
{"command": "reset_alarm"}    // Tüm alarmı sıfırla
```

---

## Sorun Giderme

| Sorun | Çözüm |
|-------|-------|
| "ODAK_Sistem" ağı görünmüyor | ESP32 güç kontrolü, Serial Monitor'da çıktıyı kontrol et |
| API ping başarısız | Telefonun ODAK_Sistem ağına bağlı olduğundan emin ol |
| LED kırmızı yanıp söner | MPU6050 bağlantı hatası — SDA/SCL kablolarını kontrol et |
| Deprem sürekli algılanıyor | Eşik değeri düşük olabilir — `esik_deger` değerini artır |
| Uygulama "zaman aşımı" diyor | ESP32 meşgul olabilir — polling süresini 5s'ye çıkar |
