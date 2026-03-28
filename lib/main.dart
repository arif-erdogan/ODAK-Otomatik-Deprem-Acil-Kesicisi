import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const DepremSistemiApp());
}

class DepremSistemiApp extends StatelessWidget {
  const DepremSistemiApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Deprem Güvenlik Sistemi',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
      home: const AnaSayfa(),
    );
  }
}

class AnaSayfa extends StatefulWidget {
  const AnaSayfa({super.key});
  @override
  State<AnaSayfa> createState() => _AnaSayfaState();
}

class _AnaSayfaState extends State<AnaSayfa> {
  // --- Durum değişkenleri ---
  String _cihazDurumu = 'guvenli';
  String _baglantıDurumu = 'Firebase bekleniyor...';
  bool   _islemYapiliyor = false;

  // --- Firebase ---
  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  // --- BLE ---
  BluetoothDevice?       _bleDevice;
  BluetoothCharacteristic? _bleChar;

  static const String BLE_ADI    = 'DepremSistemi';
  static const String BLE_CHAR_UUID =
      'abcdef01-1234-1234-1234-abcdef012345';

  @override
  void initState() {
    super.initState();
    _firebaseDinle();
    _bildirimKur();
  }

  // -------------------------------------------------------
  // Firebase dinleyici
  // -------------------------------------------------------
  void _firebaseDinle() {
    _db.child('cihaz_durumu').onValue.listen((event) {
      final deger = event.snapshot.value as String? ?? 'guvenli';
      setState(() => _cihazDurumu = deger);
    });
  }

  // -------------------------------------------------------
  // FCM bildirim kurulumu
  // -------------------------------------------------------
  Future<void> _bildirimKur() async {
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission();
    FirebaseMessaging.onMessage.listen((message) {
      // Ön planda gelen bildirim — snackbar göster
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message.notification?.body ?? '')),
      );
    });
  }

  // -------------------------------------------------------
  // ANA BUTON: Sistemi yeniden aktif et
  // -------------------------------------------------------
  Future<void> _sistemiYenidenAktifEt() async {
    setState(() => _islemYapiliyor = true);

    final baglantiSonuc = await Connectivity().checkConnectivity();
    final internetVar  = baglantiSonuc != ConnectivityResult.none;

    if (internetVar) {
      // PLAN A: Firebase
      await _planA_Firebase();
    } else {
      // PLAN B: BLE
      await _planB_BLE();
    }

    setState(() => _islemYapiliyor = false);
  }

  // -------------------------------------------------------
  // Plan A: Firebase komutu gönder
  // -------------------------------------------------------
  Future<void> _planA_Firebase() async {
    try {
      setState(() => _baglantıDurumu = 'Firebase\'e komut gönderiliyor...');
      await _db.child('sistemi_ac').set('tetiklendi');
      setState(() => _baglantıDurumu = 'Komut gönderildi! ESP32 aktif ediyor.');
    } catch (e) {
      setState(() => _baglantıDurumu = 'Firebase hatası: $e');
    }
  }

  // -------------------------------------------------------
  // Plan B: BLE ile komut gönder
  // -------------------------------------------------------
  Future<void> _planB_BLE() async {
    setState(() => _baglantıDurumu =
        'İnternet yok. Bluetooth ile bağlanılıyor...');

    try {
      // Tarıyıp ESP32'yi bul
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
      FlutterBluePlus.scanResults.listen((sonuclar) async {
        for (final sonuc in sonuclar) {
          if (sonuc.device.platformName == BLE_ADI) {
            await FlutterBluePlus.stopScan();
            _bleDevice = sonuc.device;
            await _bleDevice!.connect();
            setState(() => _baglantıDurumu = 'ESP32 bulundu, bağlanıldı!');

            // Servis ve characteristic bul
            final servisler = await _bleDevice!.discoverServices();
            for (final servis in servisler) {
              for (final char in servis.characteristics) {
                if (char.uuid.toString() == BLE_CHAR_UUID) {
                  _bleChar = char;
                  // "1" komutunu gönder
                  await _bleChar!.write([0x31]); // "1" ASCII
                  setState(() =>
                    _baglantıDurumu = 'BLE komutu gönderildi!');
                }
              }
            }
          }
        }
      });
    } catch (e) {
      setState(() => _baglantıDurumu = 'BLE hatası: $e');
    }
  }

  // -------------------------------------------------------
  // Arayüz
  // -------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final tehlikeMi = _cihazDurumu == 'tehlike';

    return Scaffold(
      backgroundColor: tehlikeMi ? Colors.red[50] : Colors.green[50],
      appBar: AppBar(title: const Text('Deprem Güvenlik Sistemi')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // DURUM KARTI
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: tehlikeMi ? Colors.red[400] : Colors.green[400],
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(children: [
                Icon(
                  tehlikeMi ? Icons.warning_rounded : Icons.check_circle,
                  size: 72, color: Colors.white,
                ),
                const SizedBox(height: 16),
                Text(
                  tehlikeMi ? 'GAZ KESİLDİ' : 'SİSTEM GÜVENLİ',
                  style: const TextStyle(
                    fontSize: 28, fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ]),
            ),

            const SizedBox(height: 24),

            // DURUM MESAJI
            Text(_baglantıDurumu,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[700])),

            const SizedBox(height: 32),

            // AKTİF ET BUTONU — sadece tehlike modunda göster
            if (tehlikeMi)
              SizedBox(
                width: double.infinity,
                height: 64,
                child: ElevatedButton.icon(
                  onPressed: _islemYapiliyor ? null : _sistemiYenidenAktifEt,
                  icon: _islemYapiliyor
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.power_settings_new),
                  label: Text(
                    _islemYapiliyor ? 'İşlem yapılıyor...' : 'Sistemi Yeniden Aktif Et',
                    style: const TextStyle(fontSize: 18),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}