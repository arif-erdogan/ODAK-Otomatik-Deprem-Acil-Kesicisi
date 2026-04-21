// --- KÜTÜPHANE TANIMLAMALARI ---
#include <Wire.h>
#include <Adafruit_MPU6050.h>
#include <Adafruit_Sensor.h>
#include <SoftwareSerial.h>
#include <Servo.h>

// --- NESNE TANIMLAMALARI ---
Adafruit_MPU6050 mpu;
SoftwareSerial BT(10, 11);
Servo myServo;

// --- MPU KALİBRASYON TANIMLAMALARI ---
float offsetX = 0;
float offsetY = 0;
float offsetZ = 0;

float esik_deger = 3.0;
int deprem_sayaci = 0;
bool deprem_olduMu = false;
bool manuel_mod = false;

// --- MPU VERİ DEĞİŞKENLERİ ---
float sonSapma = 0.0;

// --- ZAMAN DEĞİŞKENLERİ ---
unsigned long previousSensorMillis = 0;
unsigned long previousControlMillis = 0;

const unsigned long sensorInterval = 20;   // 20 ms'de bir örnek al
const unsigned long controlInterval = 100; // 100 ms'de bir karar ver

// --- KAYAN ORTALAMA İÇİN ---
const int ornekSayisi = 5;
float deviationBuffer[ornekSayisi] = {0};
int bufferIndex = 0;
bool bufferDoldu = false;

// --- ARDUINO PIN TANIMLAMALARI ---
#define LED_RED 6
#define LED_GREEN 5
#define BUZZER 4
#define ROLE 7
#define SERVO_PIN 9

void setup() {
  Serial.begin(9600);
  BT.begin(9600);

  pinMode(LED_RED, OUTPUT);
  pinMode(LED_GREEN, OUTPUT);
  pinMode(BUZZER, OUTPUT);
  pinMode(ROLE, OUTPUT);

  Wire.begin();
  Serial.println("2 - Wire basladi");

  Serial.println("3 - MPU araniyor");
  if (!mpu.begin()) {
    Serial.println("4 - HATA: MPU6050 bulunamadi");
    while (1) {
    }
  }

  digitalWrite(LED_GREEN, HIGH);
  digitalWrite(ROLE, HIGH);
  digitalWrite(LED_RED, LOW);
  digitalWrite(BUZZER, LOW);

  myServo.attach(SERVO_PIN);
  myServo.write(0);

  Serial.println("5 - MPU6050 bulundu");
  Serial.println("Kalibrasyon basliyor...");

  kalibrasyonYap();

  Serial.println("Offset degerleri:");
  Serial.print("X: "); Serial.println(offsetX);
  Serial.print("Y: "); Serial.println(offsetY);
  Serial.print("Z: "); Serial.println(offsetZ);

  mpu.setAccelerometerRange(MPU6050_RANGE_8_G);
  Serial.println("6 - Accelerometer range ayarlandi");

  mpu.setFilterBandwidth(MPU6050_BAND_21_HZ);
  Serial.println("7 - Filtre ayarlandi");

  Serial.println("MPU6050 hazir!");
}

void loop() {
  bluetoothKomutlariniOku();

  unsigned long currentMillis = millis();

  // --- Sensörden periyodik örnek al ---
  if (currentMillis - previousSensorMillis >= sensorInterval) {
    previousSensorMillis = currentMillis;
    sensorOrnekle();
  }

  // --- Karar mekanizması ---
  if (currentMillis - previousControlMillis >= controlInterval) {
    previousControlMillis = currentMillis;

    if (!manuel_mod) {
      if (sonSapma > esik_deger) {
        deprem_sayaci++;
      } else {
        deprem_sayaci = 0;
      }

      if (deprem_sayaci >= 3) {
        deprem_olduMu = true;
      }
    }

    durumUygula();
  }
}

// ---------------- Bluetooth Komutları ----------------
void bluetoothKomutlariniOku() {
  if (BT.available()) {
    char komut = BT.read();

    if (komut == 'a') {
      manuel_mod = true;
      guvenlikElektrik();
      BT.println("ELEKTRIK SAGLANDI...");
    }
    else if (komut == 'b') {
      manuel_mod = true;
      guvenlikDogalgaz();
      BT.println("DOGALGAZ SAGLANDI...");
    }
    else if (komut == 'c') {
      manuel_mod = false;
      deprem_olduMu = false;
      deprem_sayaci = 0;
      BT.println("OTOMATIK MOD AKTIF");
      Serial.println("OTOMATIK MOD AKTIF");
    }
  }
}

// ---------------- Sensör Örnekleme ----------------
void sensorOrnekle() {
  sensors_event_t a, g, temp;
  mpu.getEvent(&a, &g, &temp);

  float ax = a.acceleration.x - offsetX;
  float ay = a.acceleration.y - offsetY + 9.81;
  float az = a.acceleration.z - offsetZ;

  float totalAccel = sqrt(ax * ax + ay * ay + az * az);
  float deviation = fabs(totalAccel - 9.81);

  deviationBuffer[bufferIndex] = deviation;
  bufferIndex++;

  if (bufferIndex >= ornekSayisi) {
    bufferIndex = 0;
    bufferDoldu = true;
  }

  sonSapma = ortalamaSapmaHesapla();
}

// ---------------- Ortalama Hesabı ----------------
float ortalamaSapmaHesapla() {
  float toplam = 0.0;
  int adet = bufferDoldu ? ornekSayisi : bufferIndex;

  if (adet == 0) return 0.0;

  for (int i = 0; i < adet; i++) {
    toplam += deviationBuffer[i];
  }

  return toplam / adet;
}

// ---------------- Durum Uygulama ----------------
void durumUygula() {
  if (deprem_olduMu) {
    Serial.println("DEPREM ALGILANDI...");
    digitalWrite(LED_RED, HIGH);
    digitalWrite(LED_GREEN, LOW);
    digitalWrite(BUZZER, HIGH);
    digitalWrite(ROLE, LOW);
    myServo.write(180);
  } else {
    digitalWrite(LED_RED, LOW);
    digitalWrite(LED_GREEN, HIGH);
    digitalWrite(BUZZER, LOW);
    digitalWrite(ROLE, HIGH);
    myServo.write(0);
  }
}

// ---------------- Kalibrasyon ----------------
void kalibrasyonYap() {
  offsetX = 0;
  offsetY = 0;
  offsetZ = 0;

  const int n = 200;

  for (int i = 0; i < n; i++) {
    sensors_event_t a, g, temp;
    mpu.getEvent(&a, &g, &temp);

    offsetX += a.acceleration.x;
    offsetY += a.acceleration.y;
    offsetZ += a.acceleration.z;

    delay(10); // sadece setup içinde
  }

  offsetX /= n;
  offsetY /= n;
  offsetZ /= n;
}

// ---------------- Güvenlik Fonksiyonları ----------------
void guvenlikDogalgaz() {
  deprem_olduMu = false;
  deprem_sayaci = 0;

  digitalWrite(LED_RED, LOW);
  digitalWrite(BUZZER, LOW);
  myServo.write(0);
  digitalWrite(LED_GREEN, HIGH);

  Serial.println("DOGALGAZ SAGLANDI...");
}

void guvenlikElektrik() {
  deprem_olduMu = false;
  deprem_sayaci = 0;

  digitalWrite(LED_RED, LOW);
  digitalWrite(BUZZER, LOW);
  digitalWrite(ROLE, HIGH);
  digitalWrite(LED_GREEN, HIGH);

  Serial.println("ELEKTRIK SAGLANDI...");
}
