// ============================================================
// ble_service.dart
// Deprem Güvenlik Sistemi — Bluetooth Low Energy Servisi
//
// ESP32 BLE Server ile iletişim kurar.
// Plan B devreye girdiğinde otomatik tarar, bağlanır, komut yazar.
// ============================================================

import 'dart:async';
import 'dart:io';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

// ----------------------------------------------------------------
// Sabitler — ESP32 kodu ile birebir eşleşmeli
// ----------------------------------------------------------------
class BleKonstanlar {
  static const String cihazAdi     = 'DepremSistemi';
  static const String serviceUuid  = '12345678-1234-1234-1234-123456789abc';
  static const String charUuid     = 'abcdef01-1234-1234-1234-abcdef012345';
  static const int    taramaSuresi = 12;   // saniye
  static const int    baglantiZaman = 10;  // saniye

  static const int komutAc        = 0x31; // ASCII "1"
  static const int komutKapat     = 0x30; // ASCII "0"
  static const int komutElektrik  = 0x32; // ASCII "2"
  static const int komutDogalgaz  = 0x33; // ASCII "3"
}

// ----------------------------------------------------------------
// BLE bağlantı durumu enum
// ----------------------------------------------------------------
enum BleDurum {
  hazir,
  taraniyor,
  bulundu,
  baglaniyor,
  bagli,
  komutGonderildi,
  hata,
  desteklenmiyor,
}

extension BleDurumAciklama on BleDurum {
  String get metin {
    switch (this) {
      case BleDurum.hazir:
        return 'Bluetooth hazır.';
      case BleDurum.taraniyor:
        return 'ESP32 aranıyor... Cihaza yaklaşın.';
      case BleDurum.bulundu:
        return 'ESP32 bulundu! Bağlanılıyor...';
      case BleDurum.baglaniyor:
        return 'Bağlantı kuruluyor...';
      case BleDurum.bagli:
        return 'Bağlantı kuruldu! Komut gönderiliyor...';
      case BleDurum.komutGonderildi:
        return 'Komut iletildi. Sistem aktif ediliyor...';
      case BleDurum.hata:
        return 'BLE hatası oluştu. Tekrar deneyin.';
      case BleDurum.desteklenmiyor:
        return 'Bu cihaz BLE desteklemiyor.';
    }
  }
}

// ----------------------------------------------------------------
// BLE Servis sınıfı
// ----------------------------------------------------------------
class BleService {
  BleService._();
  static final BleService instance = BleService._();
  factory BleService() => instance;

  // -- Durum stream'i --
  final StreamController<BleDurum> _durumController =
      StreamController<BleDurum>.broadcast();

  Stream<BleDurum> get durumStream => _durumController.stream;

  // -- Dahili durum --
  BluetoothDevice?         _bagliCihaz;
  StreamSubscription?      _taramaAbonelik;
  bool                     _tariyor = false;

  // ----------------------------------------------------------------
  // İZİN KONTROLÜ
  // ----------------------------------------------------------------
  Future<bool> izinleriKontrolEt() async {
    if (Platform.isAndroid) {
      final durumlar = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
      ].request();

      return durumlar.values.every(
        (s) => s == PermissionStatus.granted,
      );
    }
    // iOS: Info.plist'te NSBluetoothAlwaysUsageDescription yeterli
    return true;
  }

  // ----------------------------------------------------------------
  // BLE AÇIK MI?
  // ----------------------------------------------------------------
  Future<bool> bluetoothAcikMi() async {
    final adapterDurum = await FlutterBluePlus.adapterState.first;
    return adapterDurum == BluetoothAdapterState.on;
  }

  // ----------------------------------------------------------------
  // ANA METOT: Tara → Bağlan → Komut Gönder
  // ----------------------------------------------------------------
  Future<BleIslemSonucu> sistemiAcBle() async {
    // 1. BLE açık mı?
    if (!await bluetoothAcikMi()) {
      _durumuGuncelle(BleDurum.desteklenmiyor);
      return BleIslemSonucu.hata('Bluetooth kapalı. Lütfen açın.');
    }

    // 2. İzinler tamam mı?
    if (!await izinleriKontrolEt()) {
      return BleIslemSonucu.hata(
        'Bluetooth izinleri verilmedi. Ayarlardan izin verin.');
    }

    try {
      // 3. Varsa mevcut bağlantıyı kapat
      await _baglantiKapat();

      // 4. Cihazı tara
      _durumuGuncelle(BleDurum.taraniyor);
      final cihaz = await _cihaziBul();
      if (cihaz == null) {
        _durumuGuncelle(BleDurum.hata);
        return BleIslemSonucu.hata(
          '"DepremSistemi" bulunamadı. Cihazın açık ve yakın olduğundan emin olun.');
      }

      // 5. Bağlan
      _durumuGuncelle(BleDurum.bulundu);
      await _baglan(cihaz);

      // 6. Characteristic bul
      final char = await _characteristicBul();
      if (char == null) {
        _durumuGuncelle(BleDurum.hata);
        return BleIslemSonucu.hata(
          'ESP32 servisi bulunamadı. UUID eşleşmesini kontrol edin.');
      }

      // 7. Komutu yaz
      _durumuGuncelle(BleDurum.bagli);
      await char.write([BleKonstanlar.komutAc], withoutResponse: false);
      _durumuGuncelle(BleDurum.komutGonderildi);

      return BleIslemSonucu.basarili();

    } on BleServisiHatasi catch (e) {
      _durumuGuncelle(BleDurum.hata);
      return BleIslemSonucu.hata(e.mesaj);
    } catch (e) {
      _durumuGuncelle(BleDurum.hata);
      return BleIslemSonucu.hata('Beklenmeyen hata: $e');
    }
  }

  // ----------------------------------------------------------------
  // Elektrik aktifleştir
  // ----------------------------------------------------------------
  Future<BleIslemSonucu> elektrikAktifEt() async {
    if (!await bluetoothAcikMi()) {
      return BleIslemSonucu.hata('Bluetooth kapalı.');
    }

    try {
      await _baglantiKapat();
      _durumuGuncelle(BleDurum.taraniyor);

      final cihaz = await _cihaziBul();
      if (cihaz == null) {
        _durumuGuncelle(BleDurum.hata);
        return BleIslemSonucu.hata('ESP32 bulunamadı.');
      }

      _durumuGuncelle(BleDurum.bulundu);
      await _baglan(cihaz);

      final char = await _characteristicBul();
      if (char == null) {
        _durumuGuncelle(BleDurum.hata);
        return BleIslemSonucu.hata('Servis bulunamadı.');
      }

      _durumuGuncelle(BleDurum.bagli);
      await char.write([BleKonstanlar.komutElektrik], withoutResponse: false);
      _durumuGuncelle(BleDurum.komutGonderildi);

      return BleIslemSonucu.basarili();
    } catch (e) {
      _durumuGuncelle(BleDurum.hata);
      return BleIslemSonucu.hata('Elektrik hatası: $e');
    }
  }

  // ----------------------------------------------------------------
  // Doğalgaz aktifleştir
  // ----------------------------------------------------------------
  Future<BleIslemSonucu> dogalgazAktifEt() async {
    if (!await bluetoothAcikMi()) {
      return BleIslemSonucu.hata('Bluetooth kapalı.');
    }

    try {
      await _baglantiKapat();
      _durumuGuncelle(BleDurum.taraniyor);

      final cihaz = await _cihaziBul();
      if (cihaz == null) {
        _durumuGuncelle(BleDurum.hata);
        return BleIslemSonucu.hata('ESP32 bulunamadı.');
      }

      _durumuGuncelle(BleDurum.bulundu);
      await _baglan(cihaz);

      final char = await _characteristicBul();
      if (char == null) {
        _durumuGuncelle(BleDurum.hata);
        return BleIslemSonucu.hata('Servis bulunamadı.');
      }

      _durumuGuncelle(BleDurum.bagli);
      await char.write([BleKonstanlar.komutDogalgaz], withoutResponse: false);
      _durumuGuncelle(BleDurum.komutGonderildi);

      return BleIslemSonucu.basarili();
    } catch (e) {
      _durumuGuncelle(BleDurum.hata);
      return BleIslemSonucu.hata('Doğalgaz hatası: $e');
    }
  }

  // ----------------------------------------------------------------
  // YARDIMCI: Cihazı tara ve bul
  // ----------------------------------------------------------------
  Future<BluetoothDevice?> _cihaziBul() async {
    final tamamlayici = Completer<BluetoothDevice?>();
    _tariyor = true;

    await FlutterBluePlus.startScan(
      timeout: Duration(seconds: BleKonstanlar.taramaSuresi),
    );

    _taramaAbonelik = FlutterBluePlus.scanResults.listen((sonuclar) {
      for (final sonuc in sonuclar) {
        if (sonuc.device.platformName == BleKonstanlar.cihazAdi) {
          if (!tamamlayici.isCompleted) {
            tamamlayici.complete(sonuc.device);
          }
          break;
        }
      }
    });

    // Tarama bittiğinde bulunamadıysa null döndür
    Future.delayed(
      Duration(seconds: BleKonstanlar.taramaSuresi + 1),
      () {
        if (!tamamlayici.isCompleted) tamamlayici.complete(null);
      },
    );

    final cihaz = await tamamlayici.future;
    await FlutterBluePlus.stopScan();
    _taramaAbonelik?.cancel();
    _tariyor = false;

    return cihaz;
  }

  // ----------------------------------------------------------------
  // YARDIMCI: Cihaza bağlan
  // ----------------------------------------------------------------
  Future<void> _baglan(BluetoothDevice cihaz) async {
    _durumuGuncelle(BleDurum.baglaniyor);
    _bagliCihaz = cihaz;

    try {
      await cihaz.connect(
        timeout: Duration(seconds: BleKonstanlar.baglantiZaman),
        autoConnect: false,
      );
    } catch (e) {
      throw BleServisiHatasi('Bağlantı kurulamadı: $e');
    }

    // Bağlantı kopma dinleyicisi
    cihaz.connectionState.listen((durum) {
      if (durum == BluetoothConnectionState.disconnected) {
        _bagliCihaz = null;
      }
    });
  }

  // ----------------------------------------------------------------
  // YARDIMCI: Characteristic keşfet
  // ----------------------------------------------------------------
  Future<BluetoothCharacteristic?> _characteristicBul() async {
    if (_bagliCihaz == null) return null;

    final servisler = await _bagliCihaz!.discoverServices();

    for (final servis in servisler) {
      if (servis.uuid.str128.toLowerCase() ==
          BleKonstanlar.serviceUuid.toLowerCase()) {
        for (final char in servis.characteristics) {
          if (char.uuid.str128.toLowerCase() ==
              BleKonstanlar.charUuid.toLowerCase()) {
            return char;
          }
        }
      }
    }
    return null;
  }

  // ----------------------------------------------------------------
  // Bağlantıyı kapat
  // ----------------------------------------------------------------
  Future<void> _baglantiKapat() async {
    if (_bagliCihaz != null) {
      try {
        await _bagliCihaz!.disconnect();
      } catch (_) {}
      _bagliCihaz = null;
    }
  }

  // ----------------------------------------------------------------
  // Durum güncelle
  // ----------------------------------------------------------------
  void _durumuGuncelle(BleDurum yeniDurum) {
    if (!_durumController.isClosed) {
      _durumController.add(yeniDurum);
    }
  }

  // ----------------------------------------------------------------
  // Bağlı mı?
  // ----------------------------------------------------------------
  bool get bagliMi => _bagliCihaz != null;

  // ----------------------------------------------------------------
  // TEMİZLİK
  // ----------------------------------------------------------------
  Future<void> kapat() async {
    if (_tariyor) await FlutterBluePlus.stopScan();
    _taramaAbonelik?.cancel();
    await _baglantiKapat();
    _durumController.close();
  }
}

// ----------------------------------------------------------------
// İşlem sonucu — başarı / hata sarmalayıcısı
// ----------------------------------------------------------------
class BleIslemSonucu {
  final bool   basarili;
  final String mesaj;

  const BleIslemSonucu._({required this.basarili, required this.mesaj});

  factory BleIslemSonucu.basarili() =>
      const BleIslemSonucu._(basarili: true, mesaj: 'Komut başarıyla iletildi.');

  factory BleIslemSonucu.hata(String mesaj) =>
      BleIslemSonucu._(basarili: false, mesaj: mesaj);
}

// ----------------------------------------------------------------
// Özel hata sınıfı
// ----------------------------------------------------------------
class BleServisiHatasi implements Exception {
  final String mesaj;
  const BleServisiHatasi(this.mesaj);

  @override
  String toString() => 'BleServisiHatasi: $mesaj';
}