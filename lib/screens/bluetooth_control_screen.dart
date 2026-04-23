// ============================================================
// bluetooth_control_screen.dart
// HC-06 Kontrol Ekranı — Cihaz Seçimi ve Komut Gönderimi
// ============================================================

import 'package:flutter/material.dart';
import '../services/ble_service.dart';

class BluetoothControlScreen extends StatefulWidget {
  const BluetoothControlScreen({Key? key}) : super(key: key);

  @override
  State<BluetoothControlScreen> createState() => _BluetoothControlScreenState();
}

class _BluetoothControlScreenState extends State<BluetoothControlScreen> {
  final ble = BleService();
  Map<String, String> _eslesmisler = {};
  bool _yukleniyor = false;
  String _araSonucu = '';

  @override
  void initState() {
    super.initState();
    _eslesmisleriYukle();
    _dinleyenKurulari();
  }

  // ── Eşleşmiş cihazları yükle ──────────────────────────────
  Future<void> _eslesmisleriYukle() async {
    setState(() => _yukleniyor = true);
    try {
      final cihazlar = await ble.eslesmisCihazlariListele();
      setState(() => _eslesmisler = cihazlar);
    } catch (e) {
      _gosterHata('Cihaz listeleme hatası: $e');
    } finally {
      setState(() => _yukleniyor = false);
    }
  }

  // ── Dinleyenleri kur ─────────────────────────────────────
  void _dinleyenKurulari() {
    ble.durumStream.listen((durum) {
      if (!mounted) return;
      setState(() => _araSonucu = durum.metin);
    });

    ble.arduinoDurumStream.listen((durum) {
      if (!mounted) return;
      if (durum.depremAlgilandi) {
        _gosterHata('⚠️ DEPREM ALGILANDI!');
      }
    });
  }

  // ── HC-06'ya bağlan (seçili MAC) ────────────────────────
  Future<void> _seciliCihazaBaglan(String macAdres) async {
    setState(() => _yukleniyor = true);
    final sonuc = await ble.baglanMacAdresine(macAdres);
    if (!mounted) return;

    _gosterBilgi(sonuc.mesaj);
    setState(() => _yukleniyor = false);
  }

  // ── Otomatik bağlan ──────────────────────────────────────
  Future<void> _otomatikBaglan() async {
    setState(() => _yukleniyor = true);
    final sonuc = await ble.baglan();
    if (!mounted) return;

    _gosterBilgi(sonuc.mesaj);
    setState(() => _yukleniyor = false);
  }

  // ── Mesaj göster ─────────────────────────────────────────
  void _gosterBilgi(String mesaj) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mesaj),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _gosterHata(String mesaj) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mesaj),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('HC-06 Bluetooth Kontrol'),
        centerTitle: true,
      ),
      body: _yukleniyor
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Durum Göstergesi ────────────────────────────
                  _buildDurumKarti(),
                  const SizedBox(height: 20),

                  // ── Otomatik Bağlan Butonu ─────────────────────
                  ElevatedButton.icon(
                    onPressed: _otomatikBaglan,
                    icon: const Icon(Icons.bluetooth),
                    label: const Text('Otomatik Bağlan (HC-06)'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: Colors.blue,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Eşleşmiş Cihazlar Listesi ──────────────────
                  const Text(
                    'Eşleşmiş Cihazlar:',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _eslesmisler.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'Eşleşmiş cihaz yok!\n'
                            'Telefonun Bluetooth ayarlarından HC-06\'yı eşleştir (PIN: 1234)',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _eslesmisler.length,
                          itemBuilder: (context, index) {
                            final ad = _eslesmisler.keys.toList()[index];
                            final mac = _eslesmisler[ad]!;
                            return Card(
                              child: ListTile(
                                leading: const Icon(Icons.devices),
                                title: Text(ad),
                                subtitle: Text(mac),
                                trailing: ElevatedButton(
                                  onPressed: () => _seciliCihazaBaglan(mac),
                                  child: const Text('Bağlan'),
                                ),
                              ),
                            );
                          },
                        ),
                  const SizedBox(height: 20),

                  // ── Komut Gönderi Bölümü ──────────────────────
                  const Text(
                    'Komutlar:',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    children: [
                      _buildKomutButonu(
                        'Elektriği Aç',
                        Icons.flash_on,
                        () => ble.elektrikAktifEt(),
                        Colors.amber,
                      ),
                      _buildKomutButonu(
                        'Doğal Gazı Aç',
                        Icons.local_fire_department,
                        () => ble.dogalgazAktifEt(),
                        Colors.orange,
                      ),
                      _buildKomutButonu(
                        'Alarmı Sıfırla',
                        Icons.alarm_off,
                        () => ble.alarmSifirla(),
                        Colors.red,
                      ),
                      _buildKomutButonu(
                        'Durum İste',
                        Icons.info,
                        () => ble.durumIste(),
                        Colors.blue,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ── Ham Komut Gönder ──────────────────────────
                  const Text(
                    'Ham Veri Gönder:',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => ble.gonderRawVeri('1'),
                          child: const Text('Gönder: 1'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => ble.gonderRawVeri('0'),
                          child: const Text('Gönder: 0'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => ble.gonderRawVeri('A'),
                          child: const Text('Gönder: A'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  // ── Durum Kartı ───────────────────────────────────────────
  Widget _buildDurumKarti() {
    final bagliMi = ble.bagliMi;
    return Card(
      color: bagliMi ? Colors.green.shade100 : Colors.red.shade100,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(
              bagliMi ? Icons.check_circle : Icons.error,
              size: 48,
              color: bagliMi ? Colors.green : Colors.red,
            ),
            const SizedBox(height: 8),
            Text(
              bagliMi ? 'HC-06 Bağlı' : 'HC-06 Bağlantısız',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: bagliMi ? Colors.green : Colors.red,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _araSonucu.isEmpty
                  ? 'Bağlantı kurulması bekleniyor...'
                  : _araSonucu,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  // ── Komut Butonu ───────────────────────────────────────────
  Widget _buildKomutButonu(
    String label,
    IconData icon,
    Future<void> Function() onPressed,
    Color color,
  ) {
    return ElevatedButton.icon(
      onPressed: () async {
        setState(() => _yukleniyor = true);
        try {
          await onPressed();
        } catch (e) {
          _gosterHata('Hata: $e');
        } finally {
          setState(() => _yukleniyor = false);
        }
      },
      icon: Icon(icon),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
      ),
    );
  }

  @override
  void dispose() {
    ble.kapat();
    super.dispose();
  }
}
