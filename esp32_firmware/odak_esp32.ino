// ============================================================
// odak_esp32.ino
// ODAK — Otomatik Deprem Acil Kesicisi
// ESP32-S3 Mini  |  WiFi SoftAP REST API  |  v1.1
//
// Donanım:
//   MPU6050     → Wire.begin() (varsayılan SDA/SCL)
//   LED Kırmızı → GPIO 10  ── Deprem + genel alarm
//   LED Yeşil   → GPIO 17  ── Doğalgaz alarm (açıkken LOW = güvende)
//   LED Mavi    → GPIO 5   ── Elektrik alarm  (açıkken LOW = güvende)
//   Buzzer      → GPIO 6
//
// Kütüphaneler (Arduino IDE Library Manager'dan yükle):
//   - "Adafruit MPU6050" by Adafruit
//   - "Adafruit Unified Sensor" by Adafruit  (bağımlılık)
//   - "ArduinoJson" by Benoit Blanchon
//   - WiFi, WebServer → ESP32 board package ile gelir
//
// Bağlantı:
//   ESP32 kendi WiFi hotspot'unu açar (SoftAP).
//   Telefon bu ağa bağlanır → IP: 192.168.4.1  (sabit, değişmez)
//
// API Endpoints:
//   GET  /api/ping     → {"ok": true}
//   GET  /api/status   → {ok, deprem, gaz_acik, elektrik_acik,
//                         deprem_sayaci, esik_deger, ip, uptime_sn}
//   POST /api/command  → {"command": "dogalgaz_ac"|"elektrik_ac"|"reset_alarm"}
// ============================================================

#include <Adafruit_MPU6050.h>
#include <Adafruit_Sensor.h>
#include <ArduinoJson.h>
#include <WebServer.h>
#include <WiFi.h>
#include <Wire.h>
#include <math.h>

// ---------------- WiFi SoftAP ----------------
const char *WIFI_SSID     = "ODAK_Sistem";   // Telefon bu ağa bağlanır
const char *WIFI_PASSWORD = "odak1234";      // En az 8 karakter

WebServer server(80);

// ---------------- MPU ----------------
Adafruit_MPU6050 mpu;

// ---------------- Kalibrasyon ----------------
float offsetX = 0;
float offsetY = 0;
float offsetZ = 0;

float esik_deger   = 3.0;
int   deprem_sayaci = 0;
bool  deprem_olduMu = false;

// ---------------- Cihaz Durumu (Flutter'ın görmesi gereken) ----------------
bool gaz_acik      = true;   // true = gaz açık (güvende), false = kapalı (alarm)
bool elektrik_acik = true;   // true = elektrik açık (güvende), false = kesildi

// ---------------- Pinler ----------------
#define LED_RED   10
#define LED_GREEN 17
#define BUZZER    6
#define LED_BLUE  5

// ============================================================
// YARDIMCI: CORS header + JSON yanıtlar
// ============================================================
void setCorsHeaders() {
  server.sendHeader("Access-Control-Allow-Origin",  "*");
  server.sendHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  server.sendHeader("Access-Control-Allow-Headers", "Content-Type");
}

void sendOk(const String &message) {
  StaticJsonDocument<256> doc;
  doc["ok"]      = true;
  doc["message"] = message;

  String response;
  serializeJson(doc, response);
  setCorsHeaders();
  server.send(200, "application/json", response);
}

void sendError(int code, const String &errorText) {
  StaticJsonDocument<256> doc;
  doc["ok"]    = false;
  doc["error"] = errorText;

  String response;
  serializeJson(doc, response);
  setCorsHeaders();
  server.send(code, "application/json", response);
}

// ============================================================
// LED / Alarm fonksiyonları
// ============================================================

// Gaz geri açıldı — yalnızca gaz LED'ini söndür
void gazAc() {
  Serial.println("[CMD] DOGALGAZ GERI ACILIYOR...");
  gaz_acik = true;
  digitalWrite(LED_GREEN, LOW);  // Yeşil LED söner (gaz güvende)
  // Eğer elektrik de açıksa ve deprem bitmişse buzzer + kırmızı sönsün
  if (elektrik_acik && !deprem_olduMu) {
    digitalWrite(LED_RED,  LOW);
    digitalWrite(BUZZER,   LOW);
  }
}

// Elektrik geri verildi — yalnızca elektrik LED'ini söndür
void elektrikAc() {
  Serial.println("[CMD] ELEKTRIK GERI VERILIYOR...");
  elektrik_acik = true;
  digitalWrite(LED_BLUE, LOW);   // Mavi LED söner (elektrik güvende)
  // Eğer gaz da açıksa ve deprem bitmişse buzzer + kırmızı sönsün
  if (gaz_acik && !deprem_olduMu) {
    digitalWrite(LED_RED,  LOW);
    digitalWrite(BUZZER,   LOW);
  }
}

// Tam alarm: deprem algılandı → her şeyi kapat
void alarmVer() {
  Serial.println("[ALARM] DEPREM ALGILANDI — GAZ VE ELEKTRIK KESILIYOR!");
  deprem_olduMu = true;
  gaz_acik      = false;
  elektrik_acik = false;

  digitalWrite(LED_RED,   HIGH);  // Kırmızı → deprem
  digitalWrite(BUZZER,    HIGH);  // Buzzer çal
  digitalWrite(LED_GREEN, HIGH);  // Yeşil → gaz alarmı
  digitalWrite(LED_BLUE,  HIGH);  // Mavi  → elektrik alarmı
}

// Tüm alarmı sıfırla: gaz + elektrik AÇILIR, LED'ler söner
void alarmSifirla() {
  Serial.println("[CMD] ALARM SIFIRLANIYOR — TUM SISTEMLER ACILIYOR...");
  deprem_olduMu = false;
  deprem_sayaci = 0;
  gaz_acik      = true;
  elektrik_acik = true;

  digitalWrite(LED_RED,   LOW);
  digitalWrite(BUZZER,    LOW);
  digitalWrite(LED_GREEN, LOW);
  digitalWrite(LED_BLUE,  LOW);
}

// ============================================================
// Deprem ölçüm algoritması
// ============================================================
float readAverageDeviation() {
  float sumDeviation = 0.0;

  for (int i = 0; i < 5; i++) {
    server.handleClient(); // WiFi isteklerini kaçırma

    sensors_event_t a, g, temp;
    mpu.getEvent(&a, &g, &temp);

    float ax = a.acceleration.x - offsetX;
    float ay = a.acceleration.y - offsetY;
    float az = a.acceleration.z - offsetZ + 9.81;

    float totalAccel = sqrt(ax * ax + ay * ay + az * az);
    float deviation  = fabs(totalAccel - 9.81);

    sumDeviation += deviation;
    delay(20);
  }

  return sumDeviation / 5.0;
}

// ============================================================
// API Endpoint: GET /api/ping
// Flutter wifi_api_service.dart canlılık testi için kullanır
// ============================================================
void handlePing() {
  StaticJsonDocument<64> doc;
  doc["ok"] = true;

  String response;
  serializeJson(doc, response);
  setCorsHeaders();
  server.send(200, "application/json", response);
}

// ============================================================
// API Endpoint: GET /api/status
// Flutter wifi_api_service.dart bu endpoint'i çeker
// ============================================================
void handleStatus() {
  StaticJsonDocument<384> doc;
  doc["ok"]             = true;
  doc["deprem"]         = (bool)deprem_olduMu;
  doc["gaz_acik"]       = (bool)gaz_acik;
  doc["elektrik_acik"]  = (bool)elektrik_acik;
  doc["deprem_sayaci"]  = deprem_sayaci;
  doc["esik_deger"]     = esik_deger;
  doc["ip"]             = WiFi.softAPIP().toString();
  doc["uptime_sn"]      = (int)(millis() / 1000);
  doc["sistem_durumu"]  = deprem_olduMu ? "tehlike" : "guvenli";

  String response;
  serializeJson(doc, response);
  setCorsHeaders();
  server.send(200, "application/json", response);
}

// ============================================================
// API Endpoint: POST /api/command
// Body: {"command": "dogalgaz_ac" | "elektrik_ac" | "reset_alarm"}
// ============================================================
void handleCommand() {
  if (!server.hasArg("plain")) {
    sendError(400, "JSON body yok");
    return;
  }

  String body = server.arg("plain");
  Serial.print("[API] Gelen JSON: ");
  Serial.println(body);

  StaticJsonDocument<256> doc;
  DeserializationError error = deserializeJson(doc, body);

  if (error) {
    sendError(400, "Gecersiz JSON");
    return;
  }

  if (!doc.containsKey("command")) {
    sendError(400, "command alani eksik");
    return;
  }

  String command = doc["command"].as<String>();

  if (command == "dogalgaz_ac") {
    gazAc();
    // Komut yanıtına güncel durumu da ekle
    StaticJsonDocument<256> resp;
    resp["ok"]       = true;
    resp["message"]  = "dogalgaz ac komutu uygulandi";
    resp["gaz_acik"] = (bool)gaz_acik;
    String r;
    serializeJson(resp, r);
    setCorsHeaders();
    server.send(200, "application/json", r);

  } else if (command == "elektrik_ac") {
    elektrikAc();
    StaticJsonDocument<256> resp;
    resp["ok"]             = true;
    resp["message"]        = "elektrik ac komutu uygulandi";
    resp["elektrik_acik"]  = (bool)elektrik_acik;
    String r;
    serializeJson(resp, r);
    setCorsHeaders();
    server.send(200, "application/json", r);

  } else if (command == "reset_alarm") {
    alarmSifirla();
    StaticJsonDocument<256> resp;
    resp["ok"]             = true;
    resp["message"]        = "alarm resetlendi";
    resp["gaz_acik"]       = (bool)gaz_acik;
    resp["elektrik_acik"]  = (bool)elektrik_acik;
    resp["deprem"]         = (bool)deprem_olduMu;
    String r;
    serializeJson(resp, r);
    setCorsHeaders();
    server.send(200, "application/json", r);

  } else {
    sendError(400, "Bilinmeyen komut: " + command);
  }
}

// CORS preflight (OPTIONS)
void handleOptions() {
  setCorsHeaders();
  server.send(204);
}

void handleNotFound() { sendError(404, "Endpoint bulunamadi"); }

// ============================================================
// SETUP
// ============================================================
void setup() {
  Serial.begin(115200);
  delay(2000);

  Serial.println("\n================================");
  Serial.println("  ODAK — Deprem Güvenlik Sistemi");
  Serial.println("  ESP32-S3 Mini  |  SoftAP Modu");
  Serial.println("  Versiyon: 1.1");
  Serial.println("================================\n");

  // ---- Pinler ----
  pinMode(LED_RED,   OUTPUT);
  pinMode(LED_GREEN, OUTPUT);
  pinMode(BUZZER,    OUTPUT);
  pinMode(LED_BLUE,  OUTPUT);

  // Başlangıçta hepsi söndürülmüş (güvenli mod)
  digitalWrite(LED_RED,   LOW);
  digitalWrite(LED_GREEN, LOW);
  digitalWrite(BUZZER,    LOW);
  digitalWrite(LED_BLUE,  LOW);

  // ---- I2C + MPU6050 ----
  Wire.begin();
  Serial.println("[HW] Wire basladi");

  Serial.println("[HW] MPU6050 araniyor...");
  if (!mpu.begin()) {
    Serial.println("[HATA] MPU6050 bulunamadi! Kablolari kontrol edin.");
    // Hata: kırmızı LED hızlı blink - sonsuz döngü
    while (1) {
      digitalWrite(LED_RED, HIGH); delay(200);
      digitalWrite(LED_RED, LOW);  delay(200);
    }
  }
  Serial.println("[HW] MPU6050 bulundu!");

  // ---- Kalibrasyon ----
  Serial.println("[CAL] Kalibrasyon basliyor (2 sn bekleyin)...");
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

  Serial.println("[CAL] Offset degerleri:");
  Serial.printf("      X: %.4f  Y: %.4f  Z: %.4f\n", offsetX, offsetY, offsetZ);

  mpu.setAccelerometerRange(MPU6050_RANGE_8_G);
  mpu.setFilterBandwidth(MPU6050_BAND_21_HZ);
  Serial.println("[HW] MPU6050 hazir!");

  // ---- WiFi SoftAP ----
  WiFi.mode(WIFI_AP);
  WiFi.softAP(WIFI_SSID, WIFI_PASSWORD);
  delay(500); // SoftAP'ın IP'yi ataması için kısa bekle

  Serial.println("\n[WiFi] SoftAP baslatildi");
  Serial.printf("[WiFi] SSID    : %s\n", WIFI_SSID);
  Serial.printf("[WiFi] Sifre   : %s\n", WIFI_PASSWORD);
  Serial.printf("[WiFi] IP      : %s\n", WiFi.softAPIP().toString().c_str());

  // ---- REST API Endpoint'leri ----
  server.on("/api/ping",    HTTP_GET,     handlePing);
  server.on("/api/status",  HTTP_GET,     handleStatus);
  server.on("/api/command", HTTP_POST,    handleCommand);

  // OPTIONS (CORS preflight) — tüm endpoint'ler için
  server.on("/api/ping",    HTTP_OPTIONS, handleOptions);
  server.on("/api/status",  HTTP_OPTIONS, handleOptions);
  server.on("/api/command", HTTP_OPTIONS, handleOptions);

  server.onNotFound(handleNotFound);
  server.begin();

  Serial.println("\n[HTTP] Server port 80'de basladi");
  Serial.println("\n=== Kullanilabilir Endpointler ===");
  Serial.printf("  GET  http://%s/api/ping\n",    WiFi.softAPIP().toString().c_str());
  Serial.printf("  GET  http://%s/api/status\n",  WiFi.softAPIP().toString().c_str());
  Serial.printf("  POST http://%s/api/command\n", WiFi.softAPIP().toString().c_str());
  Serial.println("\n=== LED Tablosu ===");
  Serial.println("  Kirmizi + Buzzer  → Deprem algilandi");
  Serial.println("  Yesil (yanar)     → Dogalgaz alarm (kapali)");
  Serial.println("  Mavi  (yanar)     → Elektrik alarm (kesili)");
  Serial.println("==================================\n");
  Serial.printf("*** Telefondan '%s' WiFi'a baglanin ***\n", WIFI_SSID);
  Serial.printf("*** Sifre: %s\n\n", WIFI_PASSWORD);
}

// ============================================================
// LOOP
// ============================================================
void loop() {
  server.handleClient();

  // Deprem zaten tespit edilmişse sadece WiFi servis et, ölçüm yapma
  if (deprem_olduMu) {
    delay(10);
    return;
  }

  // Ölçüm yap (içinde de server.handleClient() çağrılıyor)
  float ort_sapma = readAverageDeviation();

  Serial.printf("[MPU] Ort. sapma: %.4f (esik: %.1f)\n", ort_sapma, esik_deger);

  if (ort_sapma > esik_deger) {
    deprem_sayaci++;
    Serial.printf("[MPU] Deprem sayaci: %d/3\n", deprem_sayaci);
  } else {
    deprem_sayaci = 0;
  }

  if (deprem_sayaci >= 3) {
    alarmVer();
  }

  delay(100);
}
