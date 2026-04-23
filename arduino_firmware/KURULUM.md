# ODAK — Arduino Uno Firmware Kurulum Kılavuzu (v2.0)

## Dosyalar

```
arduino_firmware/
├── odak_arduino.ino   ← Arduino IDE'ye yükleyeceğiniz ana dosya
└── KURULUM.md         ← Bu dosya
```

---

## Haberleşme Mimarisi

```
┌────────────────────┐      HC-06 Bluetooth       ┌──────────────────┐
│   Arduino Uno      │ ◄────────────────────────► │   Mobil Uygulama │
│                    │   (SPP Serial Profile)     │   (Flutter)      │
│  • MPU6050 Sensör  │   Cihaz: ODAK_Sistem       │                  │
│  • LED×3 + Buzzer  │   PIN: 1234                │  Bluetooth       │
│  • HC-06 Modülü    │   Baud: 9600               │  Serial (SPP)    │
└────────────────────┘                            └──────────────────┘
```

**Bağlantı Yöntemi:** HC-06 Bluetooth modülü ile Klasik Bluetooth (SPP) kullanılır.
Telefon "ODAK_Sistem" cihazına eşleşip seri port üzerinden iletişim kurar.

---

## Pin Bağlantı Şeması

```
Arduino Uno          Komponent
─────────────────────────────────
Pin 4           →    LED Kırmızı (+) → 220Ω → GND
Pin 5           →    LED Yeşil   (+) → 220Ω → GND
Pin 6           →    LED Mavi    (+) → 220Ω → GND
Pin 7           →    Buzzer      (+) → GND
Pin 10 (RX)     ←    HC-06 TX  (doğrudan bağlanabilir)
Pin 11 (TX)     →    HC-06 RX  (⚠️ VOLTAJ BÖLÜCÜ GEREKLİ!)
A4 (SDA)        →    MPU6050 SDA
A5 (SCL)        →    MPU6050 SCL
5V              →    HC-06 VCC, MPU6050 VCC
GND             →    HC-06 GND, MPU6050 GND, LED'ler, Buzzer
```

### ⚠️ HC-06 RX Voltaj Bölücü

Arduino Uno **5V** lojik çıkış verir, HC-06 RX pini **3.3V** bekler.
Voltaj bölücü **zorunludur**, yoksa HC-06 hasar görebilir!

```
Arduino Pin 11 (TX) ──── [1kΩ] ──┬── HC-06 RX
                                  │
                                [2kΩ]
                                  │
                                 GND
```

Bu bölücü 5V'u yaklaşık 3.3V'a düşürür: `5V × (2kΩ / (1kΩ + 2kΩ)) ≈ 3.33V`

---

## Adım 1 — Arduino IDE Hazırlığı

### Board Seçimi

1. Arduino IDE → **Tools → Board** → **"Arduino Uno"** seç
2. **Tools → Port** → Arduino'nun bağlı olduğu COM portunu seç

### Kütüphaneleri Yükle

**Tools → Manage Libraries** (Ctrl+Shift+I):

| Arama terimi | Yüklenecek kütüphane |
|-------------|----------------------|
| `Adafruit MPU6050` | "Adafruit MPU6050" by Adafruit |
| `Adafruit Unified Sensor` | "Adafruit Unified Sensor" by Adafruit |

> `Wire` ve `SoftwareSerial` kütüphaneleri Arduino IDE ile **otomatik gelir**.

---

## Adım 2 — HC-06 Modülünü Yapılandırma (Opsiyonel)

HC-06'in cihaz adını "ODAK_Sistem" yapmak için AT komut moduna alın:

1. HC-06'in KEY/EN pinini VCC'ye bağlayın (AT modu)
2. Arduino'ya basit bir Serial passthrough sketch yükleyin
3. AT komutlarını gönderin:

```
AT                    → Yanıt: OK
AT+NAME=ODAK_Sistem   → Yanıt: OK
AT+PSWD="1234"        → Yanıt: OK  (veya AT+PIN="1234")
AT+UART=9600,0,0      → Yanıt: OK
```

4. KEY/EN pinini çıkarıp normal moda geçin

> **Not:** Çoğu HC-06 modülü fabrika ayarı olarak "HC-06" adında ve "1234" PIN'inde gelir.
> İsterseniz adını değiştirmeden de kullanabilirsiniz; Flutter'da cihaz adını buna göre ayarlayın.

---

## Adım 3 — Arduino'ya Yükle

1. `odak_arduino.ino` dosyasını Arduino IDE'de açın
2. **Tools → Board** → "Arduino Uno" seçili olduğundan emin olun
3. **Upload** butonuna basın (veya Ctrl+U)
4. "Done uploading" mesajı görünce tamam

---

## Adım 4 — Test Et

1. **Tools → Serial Monitor** (Ctrl+Shift+M) → Baud: **9600**
2. Şunu göreceksiniz:

```
================================
  ODAK — Deprem Guvenlik Sistemi
  Arduino Uno | HC-06 Bluetooth
  Versiyon: 2.0
================================

[HW] Wire basladi
[HW] MPU6050 araniyor...
[HW] MPU6050 bulundu!
[CAL] Kalibrasyon basliyor (2 sn bekleyin)...
[CAL] Offset degerleri:
      X: 0.xxxx  Y: 0.xxxx  Z: 9.xxxx
[HW] MPU6050 hazir!

[BT] HC-06 hazir (9600 baud)
[BT] Cihaz Adi: ODAK_Sistem
[BT] PIN: 1234

=== LED Tablosu ===
  Kirmizi + Buzzer  -> Deprem algilandi
  Yesil (yanar)     -> Dogalgaz alarm (kapali)
  Mavi  (yanar)     -> Elektrik alarm (kesili)
==================================
```

3. Telefondan **Bluetooth → ODAK_Sistem** ile eşleştirin (PIN: 1234)
4. ODAK uygulamasını açın ve Bluetooth ile bağlanın

---

## Bluetooth Protokolü

### Arduino → Telefon (her 2 saniye otomatik):
```
STATUS:deprem=0,gaz=1,elek=1,sayac=0,esik=3.0,uptime=123
```

### Telefon → Arduino (komut):
```
CMD:dogalgaz_ac
CMD:elektrik_ac
CMD:reset_alarm
CMD:durum
```

### Arduino → Telefon (yanıt):
```
OK:dogalgaz_ac
OK:elektrik_ac
OK:reset_alarm
ALARM:deprem_algilandi
ERR:bilinmeyen_komut:xxx
ERR:gecersiz_format
INFO:sistem_hazir
INFO:kalibrasyon_basliyor
```

---

## Sorun Giderme

| Sorun | Çözüm |
|-------|-------|
| HC-06 LED yanıp sönmüyor | HC-06 güç bağlantısını kontrol edin (VCC → 5V, GND → GND) |
| Bluetooth eşleşmiyor | PIN kodunun "1234" olduğundan emin olun |
| Veri gelmiyor | HC-06 TX/RX kablolarının doğru pinde olduğunu kontrol edin |
| LED kırmızı yanıp söner | MPU6050 bağlantı hatası — SDA/SCL (A4/A5) kablolarını kontrol edin |
| Deprem sürekli algılanıyor | `esik_deger` değerini artırın (varsayılan: 3.0) |
| Garip karakterler geliyor | Baud rate'in hem Arduino hem HC-06 tarafında 9600 olduğundan emin olun |
| Voltaj bölücü sorusu | HC-06 RX pinine mutlaka 1kΩ+2kΩ voltaj bölücü kullanın |
