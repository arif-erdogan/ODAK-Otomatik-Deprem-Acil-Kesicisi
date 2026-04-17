// ============================================================
// firebase_service.dart
// Deprem Güvenlik Sistemi — Firebase Realtime Database Servisi
//
// Kullanım:
//   final fb = FirebaseService();
//   fb.cihazDurumu.listen((durum) => ...);
//   await fb.sistemiAktifEt();
// ============================================================

import 'dart:async';
import 'package:firebase_database/firebase_database.dart';

// ----------------------------------------------------------------
// Veri modeli — veritabanındaki JSON ağacını temsil eder
// ----------------------------------------------------------------
class CihazDurumu {
  final String durum;          // "guvenli" | "tehlike"
  final String sistemiAc;      // "beklemede" | "tetiklendi"
  final int    sonDepremZamani; // Unix ms
  final int    sinyalGucu;     // Wi-Fi RSSI (dBm)

  const CihazDurumu({
    required this.durum,
    required this.sistemiAc,
    required this.sonDepremZamani,
    required this.sinyalGucu,
  });

  bool get tehlikede    => durum == 'tehlike';
  bool get sistemAktif  => durum == 'guvenli';

  factory CihazDurumu.fromMap(Map<dynamic, dynamic> map) {
    return CihazDurumu(
      durum:             map['cihaz_durumu']      as String? ?? 'guvenli',
      sistemiAc:         map['sistemi_ac']         as String? ?? 'beklemede',
      sonDepremZamani:   map['son_deprem_zamani']  as int?    ?? 0,
      sinyalGucu:        map['sinyal_gucu']        as int?    ?? -99,
    );
  }

  /// Ekranda gösterilecek sinyal kalite metni
  String get sinyalKalitesi {
    if (sinyalGucu >= -60) return 'Mükemmel';
    if (sinyalGucu >= -70) return 'İyi';
    if (sinyalGucu >= -80) return 'Orta';
    return 'Zayıf';
  }

  @override
  String toString() =>
      'CihazDurumu(durum: $durum, sinyal: ${sinyalGucu}dBm)';
}

// ----------------------------------------------------------------
// Firebase servis sınıfı
// ----------------------------------------------------------------
class FirebaseService {
  FirebaseService._();
  static final FirebaseService instance = FirebaseService._();
  factory FirebaseService() => instance;

  final DatabaseReference _ref = FirebaseDatabase.instance.ref();

  // -- Özel alanlar --
  StreamController<CihazDurumu>? _durumController;
  StreamSubscription<DatabaseEvent>? _abonelik;

  // ----------------------------------------------------------------
  // STREAM: Tüm cihaz durumunu tek seferde dinle
  // ----------------------------------------------------------------
  Stream<CihazDurumu> get cihazDurumu {
    _durumController ??= StreamController<CihazDurumu>.broadcast(
      onListen: _dinlemeyeBasla,
      onCancel: _dinlemeyiDurdur,
    );
    return _durumController!.stream;
  }

  void _dinlemeyeBasla() {
    _abonelik = _ref.onValue.listen(
      (event) {
        final data = event.snapshot.value;
        if (data == null) return;
        try {
          final durum = CihazDurumu.fromMap(data as Map);
          _durumController?.add(durum);
        } catch (e) {
          _durumController?.addError(
            FirebaseServiceHatasi('Veri parse hatası: $e'),
          );
        }
      },
      onError: (error) {
        _durumController?.addError(
          FirebaseServiceHatasi('Firebase bağlantı hatası: $error'),
        );
      },
    );
  }

  void _dinlemeyiDurdur() {
    _abonelik?.cancel();
    _abonelik = null;
  }

  // ----------------------------------------------------------------
  // OKUMA: Anlık (tek seferlik) durum sorgusu
  // ----------------------------------------------------------------
  Future<CihazDurumu?> anlikDurum() async {
    try {
      final snapshot = await _ref.get();
      if (!snapshot.exists || snapshot.value == null) return null;
      return CihazDurumu.fromMap(snapshot.value as Map);
    } catch (e) {
      throw FirebaseServiceHatasi('Anlık okuma hatası: $e');
    }
  }

  // ----------------------------------------------------------------
  // YAZMA: Sistemi aktif et (Firebase Plan A)
  // ----------------------------------------------------------------
  Future<void> sistemiAktifEt() async {
    try {
      await _ref.update({
        'sistemi_ac': 'tetiklendi',
      });
    } catch (e) {
      throw FirebaseServiceHatasi('Sistemi aktif etme hatası: $e');
    }
  }

  // ----------------------------------------------------------------
  // YAZMA: Elektrik aktifleştir
  // ----------------------------------------------------------------
  Future<void> elektrikAktifEt() async {
    try {
      await _ref.update({
        'elektrik_ac': 'tetiklendi',
      });
    } catch (e) {
      throw FirebaseServiceHatasi('Elektrik aktif etme hatası: $e');
    }
  }

  // ----------------------------------------------------------------
  // YAZMA: Doğalgaz aktifleştir
  // ----------------------------------------------------------------
  Future<void> dogalgazAktifEt() async {
    try {
      await _ref.update({
        'dogalgaz_ac': 'tetiklendi',
      });
    } catch (e) {
      throw FirebaseServiceHatasi('Doğalgaz aktif etme hatası: $e');
    }
  }

  // ----------------------------------------------------------------
  // YAZMA: Durumu sıfırla (ESP32 bu işi kendisi yapar, ama
  //         uygulama tarafından da tetiklenebilir)
  // ----------------------------------------------------------------
  Future<void> durumuSifirla() async {
    try {
      await _ref.update({
        'cihaz_durumu': 'guvenli',
        'sistemi_ac':   'beklemede',
      });
    } catch (e) {
      throw FirebaseServiceHatasi('Durum sıfırlama hatası: $e');
    }
  }

  // ----------------------------------------------------------------
  // YAZMA: Komut durumunu "beklemede" yap
  //         (ESP32 komutu işledikten sonra çağrılır)
  // ----------------------------------------------------------------
  Future<void> komutSifirla() async {
    try {
      await _ref.child('sistemi_ac').set('beklemede');
    } catch (e) {
      throw FirebaseServiceHatasi('Komut sıfırlama hatası: $e');
    }
  }

  // ----------------------------------------------------------------
  // YETKİLENDİRME: ESP32 için kullanılan anonim giriş kontrolü
  // (Eğer Firebase Auth eklenirse buraya taşınır)
  // ----------------------------------------------------------------
  Future<bool> baglantiKontrol() async {
    try {
      final connRef = FirebaseDatabase.instance.ref('.info/connected');
      final snapshot = await connRef.get();
      return snapshot.value == true;
    } catch (_) {
      return false;
    }
  }

  // ----------------------------------------------------------------
  // TEMİZLİK
  // ----------------------------------------------------------------
  void kapat() {
    _dinlemeyiDurdur();
    _durumController?.close();
    _durumController = null;
  }
}

// ----------------------------------------------------------------
// Özel hata sınıfı
// ----------------------------------------------------------------
class FirebaseServiceHatasi implements Exception {
  final String mesaj;
  const FirebaseServiceHatasi(this.mesaj);

  @override
  String toString() => 'FirebaseServiceHatasi: $mesaj';
}