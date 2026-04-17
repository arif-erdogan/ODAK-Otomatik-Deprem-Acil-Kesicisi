# ODAK — ESP32 REST API Kontratı (v1.1)

Hazırlayan: ODAK Geliştirme Ekibi  
Versiyon: 1.1  
Tarih: 2026-04-17

---

## Genel Kurallar

- **Bağlantı**: ESP32 SoftAP — SSID: `ODAK_Sistem`, Şifre: `odak1234`
- **Base URL**: `http://192.168.4.1`
- **Port**: `80`
- **Protokol**: HTTP/1.1 (yerel ağ, HTTPS gerekmez)
- **İçerik tipi**: `Content-Type: application/json`
- **CORS**: `Access-Control-Allow-Origin: *`
- **Timeout**: Client tarafı 4 saniye

---

## Endpoint Listesi

| Method | Endpoint | Açıklama |
|--------|----------|----------|
| GET | `/api/ping` | Canlılık kontrolü |
| GET | `/api/status` | Tam sistem durumu |
| POST | `/api/command` | Komut gönder |
| OPTIONS | Tüm endpointler | CORS preflight |

---

### 1. Canlılık Kontrolü

```
GET /api/ping
```

**Yanıt (200):**
```json
{ "ok": true }
```

---

### 2. Sistem Durumu

```
GET /api/status
```

**Yanıt (200):**
```json
{
  "ok": true,
  "deprem": false,
  "gaz_acik": true,
  "elektrik_acik": true,
  "deprem_sayaci": 0,
  "esik_deger": 3.0,
  "ip": "192.168.4.1",
  "uptime_sn": 3600,
  "sistem_durumu": "guvenli"
}
```

| Alan | Tip | Açıklama |
|------|-----|----------|
| `ok` | bool | Yanıt geçerliliği |
| `deprem` | bool | Deprem algılandı mı |
| `gaz_acik` | bool | true = gaz açık (güvende), false = alarm |
| `elektrik_acik` | bool | true = elektrik var, false = kesildi |
| `deprem_sayaci` | int | Ardışık eşik aşım sayısı (0-2 normal) |
| `esik_deger` | float | Deprem sapma eşiği (m/s²) |
| `ip` | string | ESP32 SoftAP IP adresi |
| `uptime_sn` | int | Çalışma süresi (saniye) |
| `sistem_durumu` | string | `"guvenli"` veya `"tehlike"` |

---

### 3. Komut Gönder

```
POST /api/command
Content-Type: application/json
```

**Body:**
```json
{ "command": "<komut_adi>" }
```

#### Komut: `dogalgaz_ac`

```json
// Yanıt (200):
{ "ok": true, "message": "dogalgaz ac komutu uygulandi", "gaz_acik": true }
```

#### Komut: `elektrik_ac`

```json
// Yanıt (200):
{ "ok": true, "message": "elektrik ac komutu uygulandi", "elektrik_acik": true }
```

#### Komut: `reset_alarm`

```json
// Yanıt (200):
{
  "ok": true,
  "message": "alarm resetlendi",
  "gaz_acik": true,
  "elektrik_acik": true,
  "deprem": false
}
```

---

## Hata Yanıtları

```json
{ "ok": false, "error": "Hata açıklaması" }
```

| HTTP Kodu | Durum |
|-----------|-------|
| 200 | Başarılı |
| 400 | Geçersiz istek (eksik body/alan, bilinmeyen komut) |
| 404 | Endpoint bulunamadı |

---

## Flutter Servis Eşleşmesi

| ESP32 Endpoint | Flutter Metodu | Açıklama |
|---------------|---------------|----------|
| `GET /api/ping` | `WifiApiService.ping()` | Bağlantı testi |
| `GET /api/status` | `WifiApiService.durumAl()` | Polling ile durum |
| `POST dogalgaz_ac` | `WifiApiService.gazAc()` | Gaz alarmı kaldır |
| `POST elektrik_ac` | `WifiApiService.elektrikAktifEt()` | Elektrik ver |
| `POST reset_alarm` | `WifiApiService.sistemSifirla()` | Tam sıfırlama |

---

## Test Örnekleri

```bash
curl http://192.168.4.1/api/ping
curl http://192.168.4.1/api/status
curl -X POST http://192.168.4.1/api/command -H "Content-Type: application/json" -d '{"command":"dogalgaz_ac"}'
curl -X POST http://192.168.4.1/api/command -H "Content-Type: application/json" -d '{"command":"elektrik_ac"}'
curl -X POST http://192.168.4.1/api/command -H "Content-Type: application/json" -d '{"command":"reset_alarm"}'
```
