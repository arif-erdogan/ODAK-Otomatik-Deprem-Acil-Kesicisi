// ============================================================
// wifi_api_service.dart
// ODAK — ESP32 WiFi REST API Servisi  |  v1.1
//
// ESP32 SoftAP modunda çalışır:
//   Telefon "ODAK_Sistem" ağına bağlanır (şifre: odak1234)
//   IP sabit: 192.168.4.1  (kullanıcı değiştirebilir)
//
// API Kontratı (Arduino v1.1 ile tam eşleşik):
//   GET  /api/ping     → {ok}
//   GET  /api/status   → {ok, deprem, gaz_acik, elektrik_acik,
//                         deprem_sayaci, esik_deger, ip, uptime_sn, sistem_durumu}
//   POST /api/command  → {"command": "dogalgaz_ac"|"elektrik_ac"|"reset_alarm"}
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

// ----------------------------------------------------------------
// ESP32 SoftAP varsayılan sabit IP
// ----------------------------------------------------------------
const String kEspSoftApIp = '192.168.4.1';

// ----------------------------------------------------------------
// ESP32'den gelen durum modeli
// Arduino /api/status → {ok, deprem, gaz_acik, elektrik_acik,
//                         deprem_sayaci, esik_deger, ip, uptime_sn, sistem_durumu}
// ----------------------------------------------------------------
class EspDurum {
  final bool   depremAlgilandi;   // "deprem" alanından
  final bool   gazAcik;           // "gaz_acik" alanından — true = gaz açık (güvende)
  final bool   elektrikAcik;      // "elektrik_acik" alanından — true = elektrik var
  final int    depremSayaci;
  final double esikDeger;
  final String espIp;
  final int    uptimeSn;
  final String sistemDurumu;      // "guvenli" | "tehlike"

  const EspDurum({
    required this.depremAlgilandi,
    required this.gazAcik,
    required this.elektrikAcik,
    required this.depremSayaci,
    required this.esikDeger,
    required this.espIp,
    required this.uptimeSn,
    required this.sistemDurumu,
  });

  bool get tehlikede => depremAlgilandi || sistemDurumu == 'tehlike';

  factory EspDurum.fromJson(Map<String, dynamic> json) {
    return EspDurum(
      depremAlgilandi: json['deprem']         as bool?   ?? false,
      gazAcik:         json['gaz_acik']       as bool?   ?? true,
      elektrikAcik:    json['elektrik_acik']  as bool?   ?? true,
      depremSayaci:    json['deprem_sayaci']  as int?    ?? 0,
      esikDeger:       (json['esik_deger']    as num?)?.toDouble() ?? 3.0,
      espIp:           json['ip']             as String? ?? kEspSoftApIp,
      uptimeSn:        json['uptime_sn']      as int?    ?? 0,
      sistemDurumu:    json['sistem_durumu']  as String? ?? 'guvenli',
    );
  }

  String get sinyalKalitesi => 'SoftAP';

  @override
  String toString() =>
      'EspDurum(deprem: $depremAlgilandi, gaz: $gazAcik, '
      'elektrik: $elektrikAcik, uptime: ${uptimeSn}s)';
}

// ----------------------------------------------------------------
// WiFi işlem sonucu
// ----------------------------------------------------------------
class WifiIslemSonucu {
  final bool     basarili;
  final String   mesaj;
  final EspDurum? espDurum;

  const WifiIslemSonucu._({
    required this.basarili,
    required this.mesaj,
    this.espDurum,
  });

  factory WifiIslemSonucu.basarili(String mesaj, {EspDurum? durum}) =>
      WifiIslemSonucu._(basarili: true, mesaj: mesaj, espDurum: durum);

  factory WifiIslemSonucu.hata(String mesaj) =>
      WifiIslemSonucu._(basarili: false, mesaj: mesaj);
}

// ----------------------------------------------------------------
// WiFi bağlantı durumu
// ----------------------------------------------------------------
enum WifiBaglantiDurumu {
  bilinmiyor,
  bagli,
  baglanamadi,
  zamanasimiAsildi,
}

extension WifiBaglantiDurumuAciklama on WifiBaglantiDurumu {
  String get metin {
    switch (this) {
      case WifiBaglantiDurumu.bilinmiyor:
        return 'ESP32 bağlantısı henüz test edilmedi.';
      case WifiBaglantiDurumu.bagli:
        return 'ESP32 bağlı — WiFi (SoftAP) üzerinden.';
      case WifiBaglantiDurumu.baglanamadi:
        return 'ESP32\'ye ulaşılamıyor. "ODAK_Sistem" WiFi ağına bağlı mısınız? (Şifre: odak1234)';
      case WifiBaglantiDurumu.zamanasimiAsildi:
        return 'Bağlantı zaman aşımına uğradı (4s). ESP32 açık mı?';
    }
  }
}

// ----------------------------------------------------------------
// WiFi API Servis Sınıfı
// ----------------------------------------------------------------
class WifiApiService {
  WifiApiService._();
  static final WifiApiService instance = WifiApiService._();
  factory WifiApiService() => instance;

  // ESP32 IP — başlangıçta boş; kullanıcı girinceye kadar WiFi denenmez
  String  _espIp    = '';
  bool    _ipAyarli = false;  // Kullanıcı IP'yi açıkça girdi mi?

  // Bağlantı durumu stream'i
  final StreamController<WifiBaglantiDurumu> _baglantiController =
      StreamController<WifiBaglantiDurumu>.broadcast();

  Stream<WifiBaglantiDurumu> get baglantiStream => _baglantiController.stream;

  WifiBaglantiDurumu _baglantiDurumu = WifiBaglantiDurumu.bilinmiyor;
  WifiBaglantiDurumu get baglantiDurumu => _baglantiDurumu;

  // HTTP timeout
  static const Duration _timeout = Duration(seconds: 4);

  // ----------------------------------------------------------------
  // IP Adresi Yönetimi
  // ----------------------------------------------------------------
  String get espIpAdresi => _espIp.isEmpty ? kEspSoftApIp : _espIp;

  /// Kullanıcı IP'yi diyalogdan girinceye kadar false döner.
  /// Bu sayede uygulama açılışında gereksiz WiFi denemesi yapılmaz.
  bool get ipGirildi => _ipAyarli;

  set espIpAdresi(String ip) {
    final temiz = ip.trim();
    if (temiz.isEmpty) return;
    _espIp    = temiz;
    _ipAyarli = true;
    _baglantiGuncelle(WifiBaglantiDurumu.bilinmiyor);
    debugPrint('[WifiApiService] IP ayarlandi: $_espIp');
  }

  /// Diyalogsuz, SoftAP sabit IP ile doğrudan bağlanmak için
  void softApBaglantisiKur() {
    _espIp    = kEspSoftApIp;
    _ipAyarli = true;
    _baglantiGuncelle(WifiBaglantiDurumu.bilinmiyor);
    debugPrint('[WifiApiService] SoftAP IP kullaniliyor: $kEspSoftApIp');
  }

  String get _baseUrl => 'http://${_espIp.isEmpty ? kEspSoftApIp : _espIp}';

  // ----------------------------------------------------------------
  // Canlılık Kontrolü — GET /api/ping
  // ----------------------------------------------------------------
  Future<bool> ping() async {
    if (!_ipAyarli) return false;
    try {
      final yanit = await http
          .get(Uri.parse('$_baseUrl/api/ping'))
          .timeout(_timeout);
      final basarili = yanit.statusCode == 200;
      _baglantiGuncelle(
        basarili ? WifiBaglantiDurumu.bagli : WifiBaglantiDurumu.baglanamadi,
      );
      if (basarili) {
        debugPrint('[WifiApiService] Ping basarili → $_baseUrl');
      }
      return basarili;
    } on TimeoutException {
      _baglantiGuncelle(WifiBaglantiDurumu.zamanasimiAsildi);
      debugPrint('[WifiApiService] Ping zaman asimi');
      return false;
    } catch (e) {
      _baglantiGuncelle(WifiBaglantiDurumu.baglanamadi);
      debugPrint('[WifiApiService] Ping hatasi: $e');
      return false;
    }
  }

  // ----------------------------------------------------------------
  // Sistem Durumu — GET /api/status
  // ----------------------------------------------------------------
  Future<EspDurum?> durumAl() async {
    if (!_ipAyarli) return null;
    try {
      final yanit = await http
          .get(Uri.parse('$_baseUrl/api/status'))
          .timeout(_timeout);

      if (yanit.statusCode == 200) {
        _baglantiGuncelle(WifiBaglantiDurumu.bagli);
        final json = jsonDecode(yanit.body) as Map<String, dynamic>;
        final durum = EspDurum.fromJson(json);
        debugPrint('[WifiApiService] Durum alindi: $durum');
        return durum;
      }
      debugPrint('[WifiApiService] Durum HTTP ${yanit.statusCode}');
      return null;
    } on TimeoutException {
      _baglantiGuncelle(WifiBaglantiDurumu.zamanasimiAsildi);
      debugPrint('[WifiApiService] Durum zaman asimi');
      return null;
    } catch (e) {
      _baglantiGuncelle(WifiBaglantiDurumu.baglanamadi);
      debugPrint('[WifiApiService] durumAl hatasi: $e');
      return null;
    }
  }

  // ----------------------------------------------------------------
  // Doğalgaz Aç — POST /api/command {"command":"dogalgaz_ac"}
  // ----------------------------------------------------------------
  Future<WifiIslemSonucu> gazAc() async {
    return _postKomut('dogalgaz_ac', 'Doğalgaz açıldı (WiFi)');
  }

  // ----------------------------------------------------------------
  // Alarm Sıfırla (hem gaz hem elektrik açılır)
  // ----------------------------------------------------------------
  Future<WifiIslemSonucu> alarmSifirla() async {
    return _postKomut('reset_alarm', 'Sistem sıfırlandı — gaz ve elektrik açıldı');
  }

  // ----------------------------------------------------------------
  // Elektrik Aktifleştir — POST /api/command {"command":"elektrik_ac"}
  // ----------------------------------------------------------------
  Future<WifiIslemSonucu> elektrikAktifEt() async {
    return _postKomut('elektrik_ac', 'Elektrik verildi (WiFi)');
  }

  // ----------------------------------------------------------------
  // Sistemi Sıfırla — POST /api/command {"command":"reset_alarm"}
  // ----------------------------------------------------------------
  Future<WifiIslemSonucu> sistemSifirla() async {
    return _postKomut('reset_alarm', 'Sistem güvenli moda alındı');
  }

  // ----------------------------------------------------------------
  // YARDIMCI: POST /api/command gönder
  // ----------------------------------------------------------------
  Future<WifiIslemSonucu> _postKomut(
    String command,
    String basariliMesaj,
  ) async {
    if (!_ipAyarli) {
      return WifiIslemSonucu.hata(
        'ESP32 IP adresi henüz girilmedi. Lütfen WiFi bağlantısını kurun.',
      );
    }

    try {
      final body = jsonEncode({'command': command});
      debugPrint('[WifiApiService] POST /api/command → $command');

      final yanit = await http
          .post(
            Uri.parse('$_baseUrl/api/command'),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(_timeout);

      debugPrint('[WifiApiService] Yanit: HTTP ${yanit.statusCode} — ${yanit.body}');

      if (yanit.statusCode == 200) {
        _baglantiGuncelle(WifiBaglantiDurumu.bagli);
        final json = jsonDecode(yanit.body) as Map<String, dynamic>;
        final basarili = json['ok'] as bool? ?? false;
        if (basarili) {
          return WifiIslemSonucu.basarili(basariliMesaj);
        } else {
          final hataMetni = json['error'] as String? ?? 'ESP32 bilinmeyen hata';
          return WifiIslemSonucu.hata(hataMetni);
        }
      }
      return WifiIslemSonucu.hata(
        'ESP32 yanıtı: HTTP ${yanit.statusCode}',
      );
    } on TimeoutException {
      _baglantiGuncelle(WifiBaglantiDurumu.zamanasimiAsildi);
      return WifiIslemSonucu.hata('Bağlantı zaman aşımına uğradı (4s). ESP32 açık mı?');
    } catch (e) {
      _baglantiGuncelle(WifiBaglantiDurumu.baglanamadi);
      return WifiIslemSonucu.hata('WiFi bağlantı hatası: $e');
    }
  }

  // ----------------------------------------------------------------
  // Durum güncelle — stream'e yayınla
  // ----------------------------------------------------------------
  void _baglantiGuncelle(WifiBaglantiDurumu yeniDurum) {
    if (_baglantiDurumu == yeniDurum) return; // Değişmemişse yayınlama
    _baglantiDurumu = yeniDurum;
    if (!_baglantiController.isClosed) {
      _baglantiController.add(yeniDurum);
    }
  }

  // ----------------------------------------------------------------
  // Periyodik polling — her X saniyede /api/status çeker
  // ----------------------------------------------------------------
  Timer? _pollingTimer;
  final StreamController<EspDurum> _durumController =
      StreamController<EspDurum>.broadcast();

  Stream<EspDurum> get espDurumStream => _durumController.stream;

  bool get pollingAktif => _pollingTimer != null && _pollingTimer!.isActive;

  void pollingBaslat({int saniye = 3}) {
    if (pollingAktif) return; // Zaten aktifse tekrar başlatma
    debugPrint('[WifiApiService] Polling baslatildi (${saniye}s aralikla)');
    _pollingTimer = Timer.periodic(
      Duration(seconds: saniye),
      (_) async {
        final durum = await durumAl();
        if (durum != null && !_durumController.isClosed) {
          _durumController.add(durum);
        }
      },
    );
  }

  void pollingSondur() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    debugPrint('[WifiApiService] Polling durduruldu');
  }

  // ----------------------------------------------------------------
  // TEMİZLİK
  // ----------------------------------------------------------------
  void kapat() {
    pollingSondur();
    if (!_baglantiController.isClosed) _baglantiController.close();
    if (!_durumController.isClosed)    _durumController.close();
  }
}
