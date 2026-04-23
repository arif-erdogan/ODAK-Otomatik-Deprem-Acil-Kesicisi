// ============================================================
// ble_service.dart
// ODAK — Otomatik Deprem Acil Kesicisi
// Bluetooth Serial (SPP) Servisi  |  v3.0
//
// HC-06 Klasik Bluetooth haberleşme (Bluetooth SPP Profile)
// flutter_bluetooth_serial paketi kullanılır.
//
// HC-06 İçin Standart UUID:
//   00001101-0000-1000-8000-00805F9B34FB (Serial Port Profile)
//
// 4 Adımlık Çalışma Algoritması:
//   1. İzinleri Alma: BLUETOOTH_SCAN + BLUETOOTH_CONNECT (Android 12+)
//   2. Eşleşmiş Cihazları Listeleme: MAC adresleri ve isimler
//   3. Bağlantı (Soket) Kurma: Mac adresi + UUID ile cihaza bağlan
//   4. Veri Akışı: OutputStream (komut gönder), InputStream (veri oku)
//
// Protokol:
//   Arduino → Telefon: STATUS:deprem=X,gaz=X,elek=X,sayac=X,esik=X.X,uptime=X\n
//   Telefon → Arduino: CMD:dogalgaz_ac\n | CMD:elektrik_ac\n | CMD:reset_alarm\n
//   Arduino yanıt:     OK:komut\n | ERR:aciklama\n | ALARM:deprem_algilandi\n
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';

// ----------------------------------------------------------------
// HC-06 Bluetooth Sabitler
// ----------------------------------------------------------------
class BtKonstanlar {
  // HC-06 cihaz adları — arama sırası: HC-06 (varsayılan) → ODAK_Sistem (AT+NAME ile değiştirilmişse)
  // Eğer cihaz "ODAK_Sistem"e AT komutu ile rename edilmişse ikinci ad olarak aranır
  static const String cihazAdi = 'HC-06'; // HC-06 varsayılan adı ⭐ ÖNCELİKLİ
  static const String cihazAdiAlt =
      'ODAK_Sistem'; // AT+NAME=ODAK_Sistem komutu ile değiştirilmişse

  // HC-06 UUID (Serial Port Profile - SPP)
  // Bu UUID tüm Bluetooth seri haberleşme cihazlarında standarddır
  static const String sppUuid = '00001101-0000-1000-8000-00805F9B34FB';

  // Keşif süresi (saniye)
  static const int taramaSuresi = 15;

  // HC-06 Varsayılan PIN
  static const String defaultPin = '1234';

  // HC-06 MAC Adresi — Doğrudan Bağlantı İçin
  // ⚠️ Bu MAC adresiniz olup olmadığını kontrol edin
  // Eğer farklıysa güncelleyin (Android Ayarları > Bluetooth'ta görebilirsiniz)
  static const String defaultMacAddress = '00:18:E4:40:00:06';
}

// ----------------------------------------------------------------
// Arduino'dan gelen durum modeli
// ----------------------------------------------------------------
class ArduinoDurum {
  final bool depremAlgilandi;
  final bool gazAcik;
  final bool elektrikAcik;
  final int depremSayaci;
  final double esikDeger;
  final int uptimeSn;

  const ArduinoDurum({
    required this.depremAlgilandi,
    required this.gazAcik,
    required this.elektrikAcik,
    required this.depremSayaci,
    required this.esikDeger,
    required this.uptimeSn,
  });

  bool get tehlikede => depremAlgilandi;

  /// "STATUS:deprem=0,gaz=1,elek=1,sayac=0,esik=3.0,uptime=123" parse
  factory ArduinoDurum.fromStatusLine(String line) {
    final veri = line.startsWith('STATUS:') ? line.substring(7) : line;
    final parcalar = <String, String>{};
    for (final parca in veri.split(',')) {
      final kv = parca.split('=');
      if (kv.length == 2) parcalar[kv[0].trim()] = kv[1].trim();
    }
    return ArduinoDurum(
      depremAlgilandi: (parcalar['deprem'] ?? '0') == '1',
      gazAcik: (parcalar['gaz'] ?? '1') == '1',
      elektrikAcik: (parcalar['elek'] ?? '1') == '1',
      depremSayaci: int.tryParse(parcalar['sayac'] ?? '0') ?? 0,
      esikDeger: double.tryParse(parcalar['esik'] ?? '3.0') ?? 3.0,
      uptimeSn: int.tryParse(parcalar['uptime'] ?? '0') ?? 0,
    );
  }

  factory ArduinoDurum.guvenli() => const ArduinoDurum(
        depremAlgilandi: false,
        gazAcik: true,
        elektrikAcik: true,
        depremSayaci: 0,
        esikDeger: 3.0,
        uptimeSn: 0,
      );

  @override
  String toString() => 'ArduinoDurum(deprem:$depremAlgilandi, gaz:$gazAcik, '
      'elek:$elektrikAcik, uptime:${uptimeSn}s)';
}

// ----------------------------------------------------------------
// BT bağlantı durumu
// ----------------------------------------------------------------
enum BtDurum {
  hazir,
  taraniyor,
  bulundu,
  baglaniyor,
  bagli,
  komutGonderildi,
  hata,
  kapali,
}

extension BtDurumAciklama on BtDurum {
  String get metin {
    switch (this) {
      case BtDurum.hazir:
        return 'Bluetooth hazır.';
      case BtDurum.taraniyor:
        return 'Arduino aranıyor... Cihaza yaklaşın.';
      case BtDurum.bulundu:
        return 'Arduino bulundu! Bağlanılıyor...';
      case BtDurum.baglaniyor:
        return 'Bağlantı kuruluyor...';
      case BtDurum.bagli:
        return 'Bluetooth bağlı — Arduino ile iletişim kuruldu.';
      case BtDurum.komutGonderildi:
        return 'Komut iletildi. Sistem güncelleniyor...';
      case BtDurum.hata:
        return 'Bluetooth hatası oluştu. Tekrar deneyin.';
      case BtDurum.kapali:
        return 'Bluetooth kapalı. Lütfen açın.';
    }
  }
}

// ----------------------------------------------------------------
// İşlem sonucu
// ----------------------------------------------------------------
class BtIslemSonucu {
  final bool basarili;
  final String mesaj;
  const BtIslemSonucu._({required this.basarili, required this.mesaj});
  factory BtIslemSonucu.basarili([String m = 'Komut başarıyla iletildi.']) =>
      BtIslemSonucu._(basarili: true, mesaj: m);
  factory BtIslemSonucu.hata(String m) =>
      BtIslemSonucu._(basarili: false, mesaj: m);
}

// ----------------------------------------------------------------
// Bluetooth Serial Servis
// ----------------------------------------------------------------
class BleService {
  BleService._();
  static final BleService instance = BleService._();
  factory BleService() => instance;

  final FlutterBluetoothSerial _bt = FlutterBluetoothSerial.instance;

  BluetoothConnection? _baglanti;
  String? _bagliAdres;

  final _durumCtrl = StreamController<BtDurum>.broadcast();
  final _arduinoDurumCtrl = StreamController<ArduinoDurum>.broadcast();
  final _yanitCtrl = StreamController<String>.broadcast();

  Stream<BtDurum> get durumStream => _durumCtrl.stream;
  Stream<ArduinoDurum> get arduinoDurumStream => _arduinoDurumCtrl.stream;
  Stream<String> get yanitStream => _yanitCtrl.stream;

  BtDurum _sonDurum = BtDurum.hazir;
  BtDurum get sonDurum => _sonDurum;

  String _buffer = '';

  // ── İzin Kontrolü ────────────────────────────────────────────
  // Android 12+ (API 31+): BLUETOOTH_SCAN (neverForLocation) + BLUETOOTH_CONNECT
  //   → Ayarlar > Uygulama > ODAK > İzinler altında "Yakındaki Cihazlar" görünür.
  // Android 11 ve altı: Bu runtime izinleri yoktur, otomatik granted döner.
  Future<bool> izinleriKontrolEt() async {
    // Önce status kontrol et — dialog açmamak için
    final scanStatus = await Permission.bluetoothScan.status;
    final connStatus = await Permission.bluetoothConnect.status;

    // Eğer ikisi de granted/limited ise, request() çağırma (dialog açmamak için)
    if ((scanStatus == PermissionStatus.granted ||
            scanStatus == PermissionStatus.limited) &&
        (connStatus == PermissionStatus.granted ||
            connStatus == PermissionStatus.limited)) {
      debugPrint('[İZİN] ✅ Bluetooth izinleri zaten verilmiş');
      return true;
    }

    // İzin verilmemişse, request() çağırarak dialog aç
    debugPrint('[İZİN] ⚠️ İzin isteniliyor (dialog açılabilir)...');
    final durumlar = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();

    final taramaOk =
        durumlar[Permission.bluetoothScan] == PermissionStatus.granted ||
            durumlar[Permission.bluetoothScan] == PermissionStatus.limited;
    final baglantiOk =
        durumlar[Permission.bluetoothConnect] == PermissionStatus.granted ||
            durumlar[Permission.bluetoothConnect] == PermissionStatus.limited;

    debugPrint('[İZİN] bluetoothScan: ${durumlar[Permission.bluetoothScan]}');
    debugPrint(
        '[İZİN] bluetoothConnect: ${durumlar[Permission.bluetoothConnect]}');

    if (!taramaOk || !baglantiOk) {
      debugPrint(
          '[İZİN] ❌ Bluetooth izinleri reddedildi — kalıcı red: ${durumlar.values.any((s) => s == PermissionStatus.permanentlyDenied)}');
    }

    return taramaOk && baglantiOk;
  }

  // ── İzin Kalıcı Red Kontrolü ────────────────────────────────────
  // Dart identifier'larda yalnızca ASCII karakterler kullanılabilir.
  // 'izinKaliciRedMi' — Tüm karakterler ASCII
  Future<bool> izinKaliciRedMi() async {
    final scan = await Permission.bluetoothScan.status;
    final conn = await Permission.bluetoothConnect.status;
    return scan == PermissionStatus.permanentlyDenied ||
        conn == PermissionStatus.permanentlyDenied;
  }

  // ── BT Açık mı? ──────────────────────────────────────────────
  Future<bool> bluetoothAcikMi() async {
    final acik = await _bt.isEnabled;
    return acik ?? false;
  }

  // ── Bağlı mı? ────────────────────────────────────────────────
  bool get bagliMi => _baglanti != null && (_baglanti!.isConnected);

  // ───────────────────────────────────────────────────────────────
  // ADIM 2: Eşleşmiş Cihazları Listeleme
  // ───────────────────────────────────────────────────────────────
  /// Telefonla eşleşmiş olan tüm Bluetooth cihazlarını listeler
  /// Format: {'ad': MAC_adresi, ...}
  /// Örnek: {'HC-06': '00:11:22:33:44:55', 'Başka Cihaz': 'AA:BB:CC:DD:EE:FF'}
  /// ⚠️ Android 12+ için BLUETOOTH_SCAN izni gereklidir
  Future<Map<String, String>> eslesmisCihazlariListele() async {
    final cihazlar = <String, String>{};

    // ✅ İzin kontrolü (Android 12+ için gerekli)
    final izinOk = await izinleriKontrolEt();
    if (!izinOk) {
      debugPrint('[BT] ⚠️ Eşleşmiş cihazları listelemek için izin gerekli!');
      return cihazlar; // Boş liste dön
    }

    try {
      final eslesmisler = await _bt.getBondedDevices();
      debugPrint(
          '[BT] Eşleşmiş cihazlar kontrol ediliyor (${eslesmisler.length} bulundu)');

      for (final c in eslesmisler) {
        final ad = c.name ?? 'Bilinmiyen';
        final adres = c.address ?? '';
        if (adres.isNotEmpty) {
          cihazlar[ad] = adres;
          debugPrint('[BT]   ✅ Eşleşmiş: $ad ➜ $adres');
        }
      }

      if (cihazlar.isEmpty) {
        debugPrint(
            '[BT] ℹ️ Eşleşmiş cihaz yok — yeni cihaz eşleştirmek için discovery yapın');
      }
    } catch (e) {
      debugPrint('[BT] ❌ Eşleşmiş cihaz listeleme hatası: $e');
      debugPrint('[BT]    → Android Ayarları > ODAK > İzinler kontrol edin');
    }
    return cihazlar;
  }

  // ───────────────────────────────────────────────────────────────
  // ADIM 3: MAC Adresi ile Doğrudan Bağlanma (SPP UUID Kullanılan)
  // ───────────────────────────────────────────────────────────────
  /// Belirli bir MAC adresine doğrudan bağlanır.
  /// UUID otomatik olarak SPP (Serial Port Profile) UUID'si olur.
  /// Örnek: baglanMacAdresine('00:11:22:33:44:55')
  Future<BtIslemSonucu> baglanMacAdresine(String macAdres) async {
    // 1. İzinleri kontrol et
    if (!await izinleriKontrolEt()) {
      return BtIslemSonucu.hata('❌ Bluetooth izinleri verilmedi.\n'
          'Ayarlar > ODAK > İzinler\'den "Yakındaki Cihazlar" açın.');
    }

    // 2. Bluetooth açık mı?
    if (!await bluetoothAcikMi()) {
      final acildi = await _bt.requestEnable() ?? false;
      if (!acildi) {
        return BtIslemSonucu.hata('❌ Bluetooth kapalı.\n'
            'Telefonun Ayarları > Bluetooth\'ten açın.');
      }
    }

    // 3. Eski bağlantıyı kapat
    await baglantiKapat();

    try {
      _guncelle(BtDurum.baglaniyor);
      debugPrint(
          '[BT] MAC adresine bağlanılıyor: $macAdres (UUID: ${BtKonstanlar.sppUuid})');

      // 4. SPP UUID ile bağlan (flutter_bluetooth_serial otomatik olarak SPP UUID'sini kullanır)
      _baglanti = await BluetoothConnection.toAddress(macAdres);
      _bagliAdres = macAdres;

      _guncelle(BtDurum.bagli);
      debugPrint('[BT] ✅ MAC adresi ile bağlandı: $macAdres');

      // 5. Veri dinlemeyi başlat
      _veriDinle();
      return BtIslemSonucu.basarili('HC-06 bağlantısı kuruldu ($macAdres).');
    } catch (e) {
      _guncelle(BtDurum.hata);
      debugPrint('[BT] MAC bağlantı hatası: $e');
      return BtIslemSonucu.hata('❌ Bağlantı kurulamadı ($macAdres)\n'
          'Hata: $e\n\n'
          '✅ Çözüm:\n'
          '1. Cihazın Android Bluetooth ayarlarında "Eşleştirildi" durumda mı?\n'
          '2. Evet ise: HC-06\'yı resetleyin (güç kes/aç)\n'
          '3. Hayır ise: Ayarlar > Bluetooth > HC-06 > Eşleştir');
    }
  }

  // ── Ana Bağlantı Metodu ───────────────────────────────────────
  // HC-06'ya hızlı bağlantı: eşleşmiş listede varsa direkt bağlan, yoksa keşifle bul
  Future<BtIslemSonucu> baglan() async {
    // ─── ADIM 1: İzinleri Alma ──────────────────────────────────
    if (!await izinleriKontrolEt()) {
      return BtIslemSonucu.hata('❌ Bluetooth izinleri verilmedi.\n'
          'Ayarlar > ODAK > İzinler\'den "Yakındaki Cihazlar" açın.');
    }

    // ─── Bluetooth açık mı? ──────────────────────────────────────
    if (!await bluetoothAcikMi()) {
      _guncelle(BtDurum.kapali);
      final acildi = await _bt.requestEnable() ?? false;
      if (!acildi) {
        return BtIslemSonucu.hata('❌ Bluetooth kapalı.\n'
            'Telefonun Ayarları > Bluetooth\'ten açın.');
      }
    }

    // ─── Eski bağlantıyı kapat ──────────────────────────────────
    await baglantiKapat();

    try {
      _guncelle(BtDurum.taraniyor);

      // ─── ADIM 2: Eşleşmiş Cihazları Listeleme ─────────────────
      debugPrint('[BT] ⏱️ ADIM 2a: Eşleşmiş cihazlar taranıyor...');
      BluetoothDevice? hedef = await _eslesmisCihazBul();

      // ─── Eşleşmiş değilse keşif yap ───────────────────────────
      if (hedef == null) {
        debugPrint('[BT] ℹ️ ADIM 2b: Eşleşmiş bulunamadı, keşif başlıyor...');
        hedef = await _kesfetVeBul();
      }

      if (hedef == null) {
        _guncelle(BtDurum.hata);
        return BtIslemSonucu.hata('❌ "${BtKonstanlar.cihazAdi}" bulunamadı.\n\n'
            '✅ Çözüm:\n'
            '1. HC-06\'nın gücü açık mı? (LED yanıyor mu?)\n'
            '2. Telefonla HC-06\'yı eşleştirin:\n'
            '   → Ayarlar > Bluetooth > HC-06 > Eşleştir\n'
            '   → PIN: ${BtKonstanlar.defaultPin}\n'
            '3. Cihazı yakına getirin (< 1 metre)\n'
            '4. Uygulamayı kapatıp tekrar açın');
      }

      // ─── ADIM 3: Bağlantı (Soket) Kurma ──────────────────────
      _guncelle(BtDurum.bulundu);
      debugPrint(
          '[BT] ADIM 3: ${hedef.name} (${hedef.address}) bağlanılıyor...');
      _guncelle(BtDurum.baglaniyor);

      try {
        _baglanti = await BluetoothConnection.toAddress(hedef.address);
        _bagliAdres = hedef.address;

        _guncelle(BtDurum.bagli);
        debugPrint('[BT] ✅ ADIM 3: Soket bağlantısı BAŞARILI');

        // ─── ADIM 4: Veri Akışı (Stream) ────────────────────────
        debugPrint('[BT] ADIM 4: Veri akışı dinleme başlıyor...');
        _veriDinle();

        return BtIslemSonucu.basarili(
            'HC-06 bağlantısı kuruldu (${hedef.name}).');
      } catch (socketE) {
        _guncelle(BtDurum.hata);
        debugPrint('[BT] ❌ ADIM 3: Soket hatası: $socketE');
        return BtIslemSonucu.hata('❌ Soket kurulamadı: $socketE\n\n'
            '✅ Çözüm:\n'
            '1. Android Ayarlarında HC-06 "Eşleştirildi" mi?\n'
            '2. Değilse: Ayarlar > Bluetooth > HC-06 > Çıkar > Eşleştir\n'
            '3. HC-06 resetleyin (güç kes/aç)\n'
            '4. 30 sn beklip yeniden deneyin');
      }
    } catch (e) {
      _guncelle(BtDurum.hata);
      debugPrint('[BT] ❌ Ana flow hatası: $e');
      return BtIslemSonucu.hata('❌ Bağlantı kurulamadı: $e');
    }
  }

  // ── Eşleşmiş Cihaz Ara ───────────────────────────────────────
  // ADIM 2a: Eşleşmiş cihazlar listesinde HC-06'yı ara
  // ── Eşleşmiş Cihaz Ara ───────────────────────────────────────
  // ADIM 2a: Eşleşmiş cihazlar listesinde HC-06'yı ara
  // NOT: baglan() içinden çağrıldığında, izin zaten kontrol edilmiştir.
  //      Redundant izin kontrolü yapılmıyor (hızlı bağlantı için)
  // ⚠️ Doğrudan çağrıldığında izin kontrolü yapılması gerekebilir
  Future<BluetoothDevice?> _eslesmisCihazBul() async {
    try {
      final eslesmisler = await _bt.getBondedDevices();
      debugPrint(
          '[BT] ADIM 2a: ${eslesmisler.length} adet eşleşmiş cihaz bulundu');

      if (eslesmisler.isEmpty) {
        debugPrint('[BT] ℹ️ Eşleşmiş cihaz bulunamadı — keşif yapılacak');
        return null;
      }

      // HC-06'yı eşleşmiş listede ara
      for (final c in eslesmisler) {
        final ad = (c.name ?? '').toLowerCase();
        debugPrint('[BT]   - ${c.name} (${c.address}) [eşleşmiş]');

        // Device name priority: HC-06 (primary) → ODAK_Sistem (fallback)
        if (ad.contains(BtKonstanlar.cihazAdi.toLowerCase()) ||
            ad.contains(BtKonstanlar.cihazAdiAlt.toLowerCase())) {
          debugPrint(
              '[BT] ✅ ADIM 2a: HC-06 eşleşmiş listede bulundu — ${c.name}');
          return c;
        }
      }

      debugPrint(
          '[BT] ℹ️ ADIM 2a: HC-06 eşleşmiş listede yok ama başka cihazlar var');
      debugPrint(
          '[BT]    → Cihazı Android Ayarları\'ndan çıkarıp yeniden eşleştirin');
    } catch (e) {
      debugPrint('[BT] ⚠️ ADIM 2a hatası: $e');
      debugPrint('[BT]    → Tür: ${e.runtimeType}');

      // Specific error handling
      if (e.toString().contains('permission') ||
          e.toString().contains('denied')) {
        debugPrint('[BT]    → SEBEBİ: Bluetooth izinleri reddedildi');
        debugPrint('[BT]    → ÇÖZÜM: Ayarlar > ODAK > İzinler\'den açın');
      }
    }
    return null;
  }

  // ── Keşif ile Bul ────────────────────────────────────────────
  // ADIM 2b: Cihaz keşif taraması yaparak HC-06'yı ara
  // Yeni cihazlar bu şekilde bulunur (eşleşmemiş cihazlar için)
  Future<BluetoothDevice?> _kesfetVeBul() async {
    final completer = Completer<BluetoothDevice?>();
    StreamSubscription<BluetoothDiscoveryResult>? abonelik;

    final timer = Timer(Duration(seconds: BtKonstanlar.taramaSuresi), () {
      if (!completer.isCompleted) {
        debugPrint(
            '[BT] ⏱️ ADIM 2b: Keşif süresi doldu (${BtKonstanlar.taramaSuresi}s)');
        completer.complete(null);
      }
    });

    try {
      debugPrint(
          '[BT] ADIM 2b: HC-06 keşif taraması başlıyor... (${BtKonstanlar.taramaSuresi}s)');
      debugPrint('[BT]    → Cihazı açık tutun, lütfen yakına gelin');

      int bulunanSayisi = 0;
      abonelik = _bt.startDiscovery().listen(
        (sonuc) {
          bulunanSayisi++;
          final ad = (sonuc.device.name ?? '').toLowerCase();
          final adres = sonuc.device.address ?? 'Bilinmiyen';

          debugPrint(
              '[BT]   ($bulunanSayisi) Bulunan: ${sonuc.device.name} ➜ $adres');

          if (ad.contains(BtKonstanlar.cihazAdi.toLowerCase()) ||
              ad.contains(BtKonstanlar.cihazAdiAlt.toLowerCase())) {
            if (!completer.isCompleted) {
              debugPrint(
                  '[BT] ✅ ADIM 2b: HC-06 keşifle bulundu → ${sonuc.device.name}');
              debugPrint('[BT]    → Adres: $adres');
              debugPrint(
                  '[BT] ⚠️ Not: Bu cihaz şu anda Android\'te "eşleşmemiş" durumda');
              debugPrint(
                  '[BT]         Eşleştirmek için: Ayarlar > Bluetooth > + (Ekle)');
              completer.complete(sonuc.device);
            }
          }
        },
        onError: (e) {
          debugPrint('[BT] ⚠️ ADIM 2b: Keşif hatası: $e');
          if (!completer.isCompleted) completer.complete(null);
        },
        onDone: () {
          debugPrint(
              '[BT] ADIM 2b: Keşif taraması tamamlandı ($bulunanSayisi cihaz)');
          if (!completer.isCompleted) {
            debugPrint('[BT] ❌ HC-06 keşifle de bulunamadı');
            completer.complete(null);
          }
        },
      );
      return await completer.future;
    } catch (e) {
      debugPrint('[BT] ⚠️ ADIM 2b: İstisnai hata: $e');
      if (!completer.isCompleted) completer.complete(null);
      return null;
    } finally {
      timer.cancel();
      await abonelik?.cancel();
    }
  }

  // ── Veri Dinle ───────────────────────────────────────────────
  // ADIM 4: Veri Akışı — InputStream ile Arduino'dan veri oku
  void _veriDinle() {
    _baglanti?.input?.listen(
      (Uint8List veri) {
        // HC-06 tarafından gelen ham veriyi UTF-8 ile decode et
        _buffer += utf8.decode(veri, allowMalformed: true);

        // Satır satır işle (her satır '\n' ile sona erer)
        while (_buffer.contains('\n')) {
          final idx = _buffer.indexOf('\n');
          final satir = _buffer.substring(0, idx).trim();
          _buffer = _buffer.substring(idx + 1);
          if (satir.isEmpty) continue;

          debugPrint('[BT] InputStream ← $satir');
          _satirIsle(satir);
        }
      },
      onDone: () {
        debugPrint('[BT] ⚠️ Bağlantı koptu (HC-06 uzaklaştı veya kapandı)');
        _guncelle(BtDurum.hata);
        _baglanti = null;
        _bagliAdres = null;
      },
      onError: (e) {
        debugPrint('[BT] ⚠️ InputStream okuma hatası: $e');
        _guncelle(BtDurum.hata);
      },
    );
  }

  // ── Satır İşle ───────────────────────────────────────────────
  void _satirIsle(String satir) {
    if (satir.startsWith('STATUS:')) {
      try {
        final durum = ArduinoDurum.fromStatusLine(satir);
        if (!_arduinoDurumCtrl.isClosed) _arduinoDurumCtrl.add(durum);
      } catch (e) {
        debugPrint('[BT] Durum parse hatası: $e');
      }
    } else if (satir.startsWith('ALARM:')) {
      debugPrint('[BT] ⚠️ $satir');
      const durum = ArduinoDurum(
        depremAlgilandi: true,
        gazAcik: false,
        elektrikAcik: false,
        depremSayaci: 3,
        esikDeger: 3.0,
        uptimeSn: 0,
      );
      if (!_arduinoDurumCtrl.isClosed) _arduinoDurumCtrl.add(durum);
      if (!_yanitCtrl.isClosed) _yanitCtrl.add(satir);
    } else if (satir.startsWith('OK:') ||
        satir.startsWith('ERR:') ||
        satir.startsWith('INFO:')) {
      if (!_yanitCtrl.isClosed) _yanitCtrl.add(satir);
    }
  }

  // ── Hızlı Bağlantı (Varsayılan MAC Adresi ile) ─────────────────────
  // Eğer HC-06'nız eşleşmiş listede varsa, bu method çok hızlı bağlanır (50-100ms)
  // Varsayılan MAC: 00:18:E4:40:00:06 (BtKonstanlar.defaultMacAddress)
  // NOT: MAC adresiniz farklıysa BtKonstanlar.defaultMacAddress güncelleyin
  Future<BtIslemSonucu> hizliBaglan() async {
    debugPrint(
        '[BT] ⚡ HIZLI BAĞLANTI: ${BtKonstanlar.defaultMacAddress} MAC\'e bağlanılıyor...');
    return baglanMacAdresine(BtKonstanlar.defaultMacAddress);
  }

  // ── Komut Gönder ─────────────────────────────────────────────
  // ADIM 4: Veri Akışı — OutputStream ile Arduino'ya komut gönder
  Future<BtIslemSonucu> _komutGonder(String komut) async {
    if (!bagliMi) {
      final sonuc = await baglan();
      if (!sonuc.basarili) return sonuc;
    }
    try {
      // HC-06'ya komut gönder: "CMD:<komut>\n" formatında
      final veri = utf8.encode('CMD:$komut\n');
      _baglanti!.output.add(Uint8List.fromList(veri));
      await _baglanti!.output.allSent;

      debugPrint('[BT] OutputStream → CMD:$komut');
      _guncelle(BtDurum.komutGonderildi);
      return BtIslemSonucu.basarili('$komut komutu gönderildi.');
    } catch (e) {
      debugPrint('[BT] ⚠️ OutputStream gönderme hatası: $e');
      _guncelle(BtDurum.hata);
      return BtIslemSonucu.hata('Komut gönderilemedi: $e');
    }
  }

  // ── Dışa Açık Komutlar ───────────────────────────────────────
  Future<BtIslemSonucu> elektrikAktifEt() => gonderRawVeri('B');
  Future<BtIslemSonucu> dogalgazAktifEt() => gonderRawVeri('A');
  Future<BtIslemSonucu> alarmSifirla() => gonderRawVeri('C'); // Uyumluluk icin, Arduino kodunda suan C yok
  Future<BtIslemSonucu> durumIste() => gonderRawVeri('D'); // Uyumluluk icin, Arduino kodunda suan D yok

  /// Ham veri gönder (doğrudan komut format olmadan)
  /// Örnek: gonderRawVeri('1') → '1' gönderir
  ///        gonderRawVeri('A\n') → 'A\n' gönderir
  Future<BtIslemSonucu> gonderRawVeri(String veri) async {
    if (!bagliMi) {
      final sonuc = await baglan();
      if (!sonuc.basarili) return sonuc;
    }
    try {
      final bytes = utf8.encode(veri);
      _baglanti!.output.add(Uint8List.fromList(bytes));
      await _baglanti!.output.allSent;
      debugPrint('[BT] OutputStream → Raw: $veri');
      return BtIslemSonucu.basarili('Veri gönderildi.');
    } catch (e) {
      debugPrint('[BT] ⚠️ Raw veri gönderme hatası: $e');
      _guncelle(BtDurum.hata);
      return BtIslemSonucu.hata('Veri gönderilemedi: $e');
    }
  }

  // ── Durum Güncelle ───────────────────────────────────────────
  void _guncelle(BtDurum d) {
    _sonDurum = d;
    if (!_durumCtrl.isClosed) _durumCtrl.add(d);
  }

  // ── Bağlantıyı Kapat ─────────────────────────────────────────
  Future<void> baglantiKapat() async {
    try {
      await _baglanti?.close();
    } catch (_) {}
    _baglanti = null;
    _bagliAdres = null;
    _buffer = '';
  }

  // ── Temizlik ─────────────────────────────────────────────────
  Future<void> kapat() async {
    await baglantiKapat();
    if (!_durumCtrl.isClosed) _durumCtrl.close();
    if (!_arduinoDurumCtrl.isClosed) _arduinoDurumCtrl.close();
    if (!_yanitCtrl.isClosed) _yanitCtrl.close();
  }
}
