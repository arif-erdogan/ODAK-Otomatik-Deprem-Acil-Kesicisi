// ============================================================
// odak_arduino.ino
// ODAK — Otomatik Deprem Acil Kesicisi
// Arduino Uno  |  HC-06 Bluetooth (SPP)  |  v3.2 (Servo + MPU Optim)
//
// Donanım:
//   MPU6050     → A4 (SDA), A5 (SCL) — Uno sabit I2C pinleri
//   LED Kırmızı → Pin 4  —— Deprem + genel alarm
//   LED Yeşil   → Pin 5  —— Doğalgaz alarm (yandığında = alarm)
//   LED Mavi    → Pin 6  —— Elektrik alarm (yandığında = alarm)
//   Buzzer      → Pin 7
//   Servo Motor → Pin 9  —— Depremde 180°, normalda 0°
//   HC-06 TX    → Pin 10 (Arduino SoftwareSerial RX)
//   HC-06 RX    → Pin 11 (Arduino SoftwareSerial TX) + volt bölücü!
//
// NOT: HC-06 sadece SLAVE modda çalışır (bağlantıyı hep telefon başlatır).
//      AT komutları: cihaz bağlı değilken Serial'dan AT gönderilir (baud 9600).
//      HC-06 AT Komutları:
//        AT→OK  |  AT+NAMEodak→OKsetname  |  AT+PIN1234→OKsetPIN
//
// Kütüphaneler (Arduino IDE Library Manager):
//   - "Adafruit MPU6050" by Adafruit
//   - "Adafruit Unified Sensor" by Adafruit (bağımlılık)
//   - Wire → Arduino ile gelir
//   - SoftwareSerial → Arduino ile gelir
//   - Servo → Arduino ile gelir
//
// Bluetooth Protokolü:
//   Arduino → Telefon: STATUS:deprem=X,gaz=X,elek=X,sayac=X,esik=X.X,uptime=X\n
//   Telefon → Arduino: CMD:dogalgaz_ac\n | CMD:elektrik_ac\n |
//   CMD:reset_alarm\n | CMD:durum\n Arduino yanıt:     OK:komut_adi\n |
//   ERR:aciklama\n
//
// HC-06 Bluetooth Ayarları:
//   Cihaz Adı: HC-06 (veya AT+NAME komutuyla değiştirin)
//   PIN Kodu:  1234  (AT+PIN1234 komutuyla değiştirildiğinde)
//   Baud Rate: 9600 (varsayılan, AT+BAUD4 ile değiştirilebilir)
// ============================================================

#include <Adafruit_MPU6050.h>
#include <Adafruit_Sensor.h>
#include <SoftwareSerial.h>
#include <Wire.h>
#include <math.h>
#include <Servo.h>

// ---------------- HC-06 Bluetooth ----------------
// HC-06 TX → Arduino Pin 10 (RX)
// HC-06 RX → Arduino Pin 11 (TX) — voltaj bölücü gerekli!
SoftwareSerial btSerial(10, 11); // RX, TX

// ---------------- MPU ----------------
Adafruit_MPU6050 mpu;

// ---------------- Servo Motor ----------------
Servo myServo;
#define SERVO_PIN 9

// ---------------- Kalibrasyon ----------------
float offsetX = 0;
float offsetY = 0;
float offsetZ = 0;

float esik_deger = 3.0;
int deprem_sayaci = 0;
bool deprem_olduMu = false;

// ---------------- Cihaz Durumu ----------------
bool gaz_acik = true;      // true = gaz açık (güvende), false = kapalı (alarm)
bool elektrik_acik = true; // true = elektrik açık (güvende), false = kesildi

// ---------------- Pinler ----------------
#define LED_RED 4
#define LED_GREEN 5
#define BUZZER 7
#define LED_BLUE 6

// ---------------- Zamanlayıcılar ----------------
unsigned long sonDurumGonderimi = 0;
const unsigned long DURUM_ARALIGI = 2000; // 2 saniye

// ---------------- Bluetooth Veri Tamponu ----------------
String btBuffer = "";
const int BT_BUFFER_MAX = 64;

// ============================================================
// LED / Alarm fonksiyonları
// ============================================================

// Gaz geri açıldı — yalnızca gaz LED'ini söndür
void gazAc() {
  Serial.println(F("[CMD] DOGALGAZ GERI ACILIYOR..."));
  gaz_acik = true;
  digitalWrite(LED_GREEN, LOW); // Yeşil LED söner (gaz güvende)
  myServo.write(0);             // Servo 0° (normal pos)
  // Eğer elektrik de açıksa ve deprem bitmişse buzzer + kırmızı sönsün
  if (elektrik_acik && !deprem_olduMu) {
    digitalWrite(LED_RED, LOW);
    digitalWrite(BUZZER, LOW);
  }
  btSerial.println(F("OK:dogalgaz_ac"));
}

// Elektrik geri verildi — yalnızca elektrik LED'ini söndür
void elektrikAc() {
  Serial.println(F("[CMD] ELEKTRIK GERI VERILIYOR..."));
  elektrik_acik = true;
  digitalWrite(LED_BLUE, LOW); // Mavi LED söner (elektrik güvende)
  myServo.write(0);            // Servo 0° (normal pos)
  // Eğer gaz da açıksa ve deprem bitmişse buzzer + kırmızı sönsün
  if (gaz_acik && !deprem_olduMu) {
    digitalWrite(LED_RED, LOW);
    digitalWrite(BUZZER, LOW);
  }
  btSerial.println(F("OK:elektrik_ac"));
}

// Tam alarm: deprem algılandı → her şeyi kapat + servo 180°
void alarmVer() {
  Serial.println(F("[ALARM] DEPREM ALGILANDI — GAZ VE ELEKTRIK KESILIYOR!"));
  deprem_olduMu = true;
  gaz_acik = false;
  elektrik_acik = false;

  digitalWrite(LED_RED, HIGH);   // Kırmızı → deprem
  digitalWrite(BUZZER, HIGH);    // Buzzer çal
  digitalWrite(LED_GREEN, HIGH); // Yeşil → gaz alarmı
  digitalWrite(LED_BLUE, HIGH);  // Mavi  → elektrik alarmı
  myServo.write(180);            // Servo 180° (acil durum)

  // Deprem bildirimi gönder
  btSerial.println(F("ALARM:deprem_algilandi"));
}

// Tüm alarmı sıfırla: gaz + elektrik AÇILIR, LED'ler söner, servo normal
void alarmSifirla() {
  Serial.println(F("[CMD] ALARM SIFIRLANIYOR — TUM SISTEMLER ACILIYOR..."));
  deprem_olduMu = false;
  deprem_sayaci = 0;
  gaz_acik = true;
  elektrik_acik = true;

  digitalWrite(LED_RED, LOW);
  digitalWrite(BUZZER, LOW);
  digitalWrite(LED_GREEN, LOW);
  digitalWrite(LED_BLUE, LOW);
  myServo.write(0); // Servo 0° (normal)

  btSerial.println(F("OK:reset_alarm"));
}

// ============================================================
// Bluetooth Durum Gönderimi
// ============================================================
void durumGonder() {
  // Format: STATUS:deprem=X,gaz=X,elek=X,sayac=X,esik=X.X,uptime=X
  btSerial.print(F("STATUS:deprem="));
  btSerial.print(deprem_olduMu ? 1 : 0);
  btSerial.print(F(",gaz="));
  btSerial.print(gaz_acik ? 1 : 0);
  btSerial.print(F(",elek="));
  btSerial.print(elektrik_acik ? 1 : 0);
  btSerial.print(F(",sayac="));
  btSerial.print(deprem_sayaci);
  btSerial.print(F(",esik="));
  btSerial.print(esik_deger, 1);
  btSerial.print(F(",uptime="));
  btSerial.println(millis() / 1000);
}

// ============================================================
// Bluetooth Komut İşleme
// ============================================================
void komutIsle(String komut) {
  komut.trim();

  Serial.print(F("[BT] Gelen: "));
  Serial.println(komut);

  // CMD: önekini kontrol et
  if (!komut.startsWith("CMD:")) {
    btSerial.println(F("ERR:gecersiz_format"));
    return;
  }

  // CMD: önekini kaldır
  String cmd = komut.substring(4);

  if (cmd == "dogalgaz_ac") {
    gazAc();
  } else if (cmd == "elektrik_ac") {
    elektrikAc();
  } else if (cmd == "reset_alarm") {
    alarmSifirla();
  } else if (cmd == "durum") {
    durumGonder();
  } else {
    btSerial.print(F("ERR:bilinmeyen_komut:"));
    btSerial.println(cmd);
  }
}

// ============================================================
// Bluetooth Veri Okuma
// ============================================================
void bluetoothOku() {
  while (btSerial.available()) {
    char c = (char)btSerial.read();

    if (c == '\n' || c == '\r') {
      if (btBuffer.length() > 0) {
        komutIsle(btBuffer);
        btBuffer = "";
      }
    } else {
      if (btBuffer.length() < BT_BUFFER_MAX) {
        btBuffer += c;
      } else {
        // Buffer taştı — sıfırla
        btBuffer = "";
        btSerial.println(F("ERR:buffer_tasti"));
      }
    }
  }
}

// ============================================================
// Deprem ölçüm algoritması (v3.2 — Servo kontrolü ile)
// ============================================================
float readAverageDeviation() {
  float sumDeviation = 0.0;

  for (int i = 0; i < 5; i++) {
    sensors_event_t a, g, temp;
    mpu.getEvent(&a, &g, &temp);

    float ax = a.acceleration.x - offsetX;
    float ay = a.acceleration.y - offsetY + 9.81;  // Gravity component
    float az = a.acceleration.z - offsetZ;

    float totalAccel = sqrt(ax * ax + ay * ay + az * az);
    float deviation = fabs(totalAccel - 9.81);

    sumDeviation += deviation;
    delay(20);
  }

  return sumDeviation / 5.0;
}

// ============================================================
// SETUP
// ============================================================
void setup() {
  Serial.begin(9600);
  btSerial.begin(9600); // HC-06 varsayılan baud rate

  delay(1000);

  Serial.println(F(""));
  Serial.println(F("================================"));
  Serial.println(F("  ODAK — Deprem Guvenlik Sistemi"));
  Serial.println(F("  Arduino Uno | HC-06 Bluetooth"));
  Serial.println(F("  Versiyon: 3.2 (Servo + MPU)"));
  Serial.println(F("================================"));
  Serial.println(F(""));

  // ---- Pinler ----
  pinMode(LED_RED, OUTPUT);
  pinMode(LED_GREEN, OUTPUT);
  pinMode(BUZZER, OUTPUT);
  pinMode(LED_BLUE, OUTPUT);

  // Başlangıçta hepsi söndürülmüş (güvenli mod)
  digitalWrite(LED_RED, LOW);
  digitalWrite(LED_GREEN, LOW);
  digitalWrite(BUZZER, LOW);
  digitalWrite(LED_BLUE, LOW);

  // ---- Servo Motor ----
  myServo.attach(SERVO_PIN);
  myServo.write(0);  // Normal pozisyon (0°)

  // ---- I2C + MPU6050 ----
  Wire.begin();
  Serial.println(F("[HW] Wire basladi"));

  Serial.println(F("[HW] MPU6050 araniyor..."));
  if (!mpu.begin()) {
    Serial.println(F("[HATA] MPU6050 bulunamadi! Kablolari kontrol edin."));
    btSerial.println(F("ERR:mpu6050_bulunamadi"));
    // Hata: kırmızı LED hızlı blink - sonsuz döngü
    while (1) {
      digitalWrite(LED_RED, HIGH);
      delay(200);
      digitalWrite(LED_RED, LOW);
      delay(200);
    }
  }
  Serial.println(F("[HW] MPU6050 bulundu!"));

  // ---- Kalibrasyon ----
  Serial.println(F("[CAL] Kalibrasyon basliyor (2 sn bekleyin)..."));
  btSerial.println(F("INFO:kalibrasyon_basliyor"));
  delay(2000);

  int n = 200;
  for (int i = 0; i < n; i++) {
    sensors_event_t a, g, temp;
    mpu.getEvent(&a, &g, &temp);
    offsetX += a.acceleration.x;
    offsetY += a.acceleration.y;
    offsetZ += a.acceleration.z;
    delay(10);
  }
  offsetX /= n;
  offsetY /= n;
  offsetZ /= n;

  Serial.println(F("[CAL] Offset degerleri:"));
  Serial.print(F("      X: "));
  Serial.print(offsetX, 4);
  Serial.print(F("  Y: "));
  Serial.print(offsetY, 4);
  Serial.print(F("  Z: "));
  Serial.println(offsetZ, 4);

  mpu.setAccelerometerRange(MPU6050_RANGE_8_G);
  mpu.setFilterBandwidth(MPU6050_BAND_21_HZ);
  Serial.println(F("[HW] MPU6050 hazir!"));
  Serial.println(F("[HW] Servo Motor hazir (Pin 9)!"));

  // ---- Bluetooth Hazır ----
  Serial.println(F(""));
  Serial.println(F("[BT] HC-06 hazir (9600 baud)"));
  Serial.println(F("[BT] Cihaz Adi: ODAK_Sistem"));
  Serial.println(F("[BT] PIN: 1234"));
  Serial.println(F(""));
  Serial.println(F("=== LED Tablosu ==="));
  Serial.println(F("  Kirmizi + Buzzer  -> Deprem algilandi"));
  Serial.println(F("  Yesil (yanar)     -> Dogalgaz alarm (kapali)"));
  Serial.println(F("  Mavi  (yanar)     -> Elektrik alarm (kesili)"));
  Serial.println(F("=== Servo ==="));
  Serial.println(F("  0°   -> Normal (guvenli)"));
  Serial.println(F("  180° -> Deprem (acil kapatma)"));
  Serial.println(F("=================================="));
  Serial.println(F(""));
  Serial.println(F("*** Telefondan Bluetooth ile baglanin ***"));
  Serial.println(F(""));

  btSerial.println(F("INFO:sistem_hazir"));
}

// ============================================================
// LOOP
// ============================================================
void loop() {
  // Bluetooth komutlarını her zaman kontrol et
  bluetoothOku();

  // Periyodik durum gönderimi (her 2 saniye)
  unsigned long simdi = millis();
  if (simdi - sonDurumGonderimi >= DURUM_ARALIGI) {
    sonDurumGonderimi = simdi;
    durumGonder();
  }

  // Deprem zaten tespit edilmişse ölçüm yapma, sadece BT dinle
  if (deprem_olduMu) {
    delay(10);
    return;
  }

  // Ölçüm yap
  float ort_sapma = readAverageDeviation();

  // Her ölçümde Serial'a yazdır (debug)
  Serial.print(F("[MPU] Ort. sapma: "));
  Serial.print(ort_sapma, 4);
  Serial.print(F(" (esik: "));
  Serial.print(esik_deger, 1);
  Serial.println(F(")"));

  if (ort_sapma > esik_deger) {
    deprem_sayaci++;
    Serial.print(F("[MPU] Deprem sayaci: "));
    Serial.print(deprem_sayaci);
    Serial.println(F("/3"));
  } else {
    deprem_sayaci = 0;
  }

  if (deprem_sayaci >= 3) {
    alarmVer();
  }

  delay(100);
}
