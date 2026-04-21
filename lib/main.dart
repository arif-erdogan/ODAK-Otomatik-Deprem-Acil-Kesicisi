import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const DepremGuvenlikApp());
}

// ─────────────────────────────────────────────────────────────
//  UYGULAMA KÖKÜ
// ─────────────────────────────────────────────────────────────
class DepremGuvenlikApp extends StatelessWidget {
  const DepremGuvenlikApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Deprem Güvenlik Sistemi',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFB71C1C),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0D0D0D),
      ),
      home: const BluetoothScanPage(),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  BLUETOOTH TARAMA & BAĞLANTI SAYFASI
// ─────────────────────────────────────────────────────────────
class BluetoothScanPage extends StatefulWidget {
  const BluetoothScanPage({super.key});

  @override
  State<BluetoothScanPage> createState() => _BluetoothScanPageState();
}

class _BluetoothScanPageState extends State<BluetoothScanPage>
    with SingleTickerProviderStateMixin {
  List<BluetoothDevice> _bondedDevices = [];
  bool _isLoading = false;
  String _statusMsg = 'Eşleştirilmiş cihazları yüklemek için tara';
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _requestPermissions();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  // İzinleri iste
  Future<void> _requestPermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();
  }

  // Eşleştirilmiş cihazları listele
  Future<void> _loadBondedDevices() async {
    setState(() {
      _isLoading = true;
      _statusMsg = 'İzinler kontrol ediliyor...';
    });

    // 1. İzinleri tekrar iste
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    // Eğer Konum veya Bluetooth izinleri reddedilirse uyar.
    if (statuses[Permission.location]?.isDenied == true ||
        statuses[Permission.bluetoothScan]?.isDenied == true) {
      setState(() {
        _isLoading = false;
        _statusMsg = 'Hata: Bluetooth ve Konum izinleri zorunludur!';
      });
      openAppSettings(); // İzinler tamamen reddedildiyse ayarlara yönlendir
      return;
    }

    // 2. Konum (GPS) Servisi açık mı kontrol et
    if (!await Permission.locationWhenInUse.serviceStatus.isEnabled) {
      setState(() {
        _isLoading = false;
        _statusMsg = 'Hata: Lütfen telefonun Konum (GPS) özelliğini açın!';
      });
      return;
    }

    setState(() {
      _statusMsg = 'Cihazlar taranıyor...';
    });

    try {
      final devices = await FlutterBluetoothSerial.instance.getBondedDevices();
      setState(() {
        _bondedDevices = devices;
        _isLoading = false;
        _statusMsg = devices.isEmpty
            ? 'Eşleştirilmiş cihaz bulunamadı.\nTelefon ayarlarından HC-06\'yı eşleştirin.'
            : '${devices.length} cihaz bulundu';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMsg = 'Hata: $e';
      });
    }
  }

  // Cihaza bağlan → Ana ekrana geç
  Future<void> _connectToDevice(BluetoothDevice device) async {
    setState(() {
      _isLoading = true;
      _statusMsg = '${device.name} bağlanıyor...';
    });

    try {
      final connection =
          await BluetoothConnection.toAddress(device.address);

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ControlPanelPage(
            device: device,
            connection: connection,
          ),
        ),
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMsg = 'Bağlantı başarısız: $e';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Bağlantı kurulamadı: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 24),

              // Logo & Başlık
              ScaleTransition(
                scale: _pulseAnim,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFB71C1C).withOpacity(0.15),
                    border: Border.all(
                        color: const Color(0xFFB71C1C), width: 2),
                  ),
                  child: const Icon(
                    Icons.crisis_alert,
                    size: 52,
                    color: Color(0xFFEF5350),
                  ),
                ),
              ),

              const SizedBox(height: 20),
              const Text(
                'DEPREM GÜVENLİK',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3,
                  color: Colors.white,
                ),
              ),
              const Text(
                'SİSTEMİ',
                style: TextStyle(
                  fontSize: 14,
                  letterSpacing: 6,
                  color: Color(0xFFEF5350),
                ),
              ),

              const SizedBox(height: 40),

              // Durum mesajı
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isLoading
                          ? Icons.bluetooth_searching
                          : Icons.info_outline,
                      color: const Color(0xFF42A5F5),
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _statusMsg,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Tara butonu
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _loadBondedDevices,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.bluetooth_searching),
                  label: Text(_isLoading ? 'Taranıyor...' : 'Cihazları Tara'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Cihaz listesi
              if (_bondedDevices.isNotEmpty) ...[
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'EŞLEŞTİRİLMİŞ CİHAZLAR',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 2,
                      color: Colors.white38,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView.separated(
                    itemCount: _bondedDevices.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final device = _bondedDevices[i];
                      final isHC06 =
                          (device.name ?? '').toUpperCase().contains('HC');
                      return _DeviceTile(
                        device: device,
                        isRecommended: isHC06,
                        onTap: () => _connectToDevice(device),
                      );
                    },
                  ),
                ),
              ],

              if (_bondedDevices.isEmpty && !_isLoading)
                const Expanded(
                  child: Center(
                    child: Text(
                      'HC-06\'yı telefon Bluetooth\nayarlarından önce eşleştirin,\nşifre genellikle: 1234 veya 0000',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(color: Colors.white38, fontSize: 13),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Cihaz Kartı ───
class _DeviceTile extends StatelessWidget {
  final BluetoothDevice device;
  final bool isRecommended;
  final VoidCallback onTap;

  const _DeviceTile({
    required this.device,
    required this.isRecommended,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isRecommended
              ? const Color(0xFF0D47A1).withOpacity(0.3)
              : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isRecommended
                ? const Color(0xFF42A5F5)
                : Colors.white12,
            width: isRecommended ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.bluetooth,
              color:
                  isRecommended ? const Color(0xFF42A5F5) : Colors.white38,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        device.name ?? 'Bilinmeyen Cihaz',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      if (isRecommended) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF42A5F5).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'ÖNERİLEN',
                            style: TextStyle(
                              fontSize: 9,
                              color: Color(0xFF42A5F5),
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    device.address,
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios,
                size: 14, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  KONTROL PANELİ SAYFASI
// ─────────────────────────────────────────────────────────────
class ControlPanelPage extends StatefulWidget {
  final BluetoothDevice device;
  final BluetoothConnection connection;

  const ControlPanelPage({
    super.key,
    required this.device,
    required this.connection,
  });

  @override
  State<ControlPanelPage> createState() => _ControlPanelPageState();
}

class _ControlPanelPageState extends State<ControlPanelPage> {
  // Sistem durumu
  bool _depremAlgilandi = false;
  bool _dogalgazAktif = true;   // Relay HIGH = aktif başlangıçta
  bool _elektrikAktif = true;   // Relay HIGH = aktif başlangıçta
  bool _isConnected = true;

  // Log mesajları
  final List<_LogEntry> _logs = [];
  final ScrollController _logScroll = ScrollController();

  // Gelen veri tamponu
  String _buffer = '';

  @override
  void initState() {
    super.initState();
    _listenBluetooth();
    _addLog('✅ Arduino bağlandı: ${widget.device.name}', LogType.success);
  }

  // ── Bluetooth'tan gelen verileri dinle ──
  void _listenBluetooth() {
    widget.connection.input?.listen(
      (Uint8List data) {
        _buffer += utf8.decode(data);

        // Satır satır işle
        while (_buffer.contains('\n')) {
          final idx = _buffer.indexOf('\n');
          final line = _buffer.substring(0, idx).trim();
          _buffer = _buffer.substring(idx + 1);

          if (line.isEmpty) continue;

          if (mounted) {
            setState(() {
              _handleArduinoMessage(line);
            });
          }
        }
      },
      onDone: _onDisconnected,
      onError: (e) => _addLog('⚠️ Hata: $e', LogType.warning),
    );
  }

  // ── Arduino mesajlarını işle ──
  void _handleArduinoMessage(String msg) {
    _addLog('📡 Arduino: $msg', LogType.info);

    if (msg.contains('DOGALGAZ SAGLANDI')) {
      _dogalgazAktif = true;
      _addLog('✅ Doğalgaz vanası açıldı', LogType.success);
    } else if (msg.contains('ELEKTRIK SAGLANDI')) {
      _elektrikAktif = true;
      _addLog('✅ Elektrik röle açıldı', LogType.success);
    } else if (msg.contains('DEPREM ALGILANDI')) {
      // Arduino şu an BT'ye göndermese de, ileride eklenirse hazır
      _depremAlgilandi = true;
      _dogalgazAktif = false;
      _elektrikAktif = false;
      _addLog('🔴 DEPREM ALGILANDI!', LogType.danger);
    }
  }

  // ── Komut Gönder ──
  Future<void> _sendCommand(String cmd) async {
    if (!_isConnected) {
      _addLog('❌ Bağlantı yok!', LogType.danger);
      return;
    }
    try {
      widget.connection.output.add(Uint8List.fromList(utf8.encode(cmd)));
      await widget.connection.output.allSent;
      _addLog('📤 Komut gönderildi: $cmd', LogType.info);
    } catch (e) {
      _addLog('❌ Gönderim hatası: $e', LogType.danger);
    }
  }

  // A komutu — Doğalgazı Sağla
  void _dogalgaziSagla() {
    _sendCommand('A');
    setState(() => _depremAlgilandi = false);
    _addLog('🔵 Doğalgaz güvenlik komutu gönderildi (A)', LogType.info);
  }

  // B komutu — Elektriği Sağla
  void _elektrigiSagla() {
    _sendCommand('B');
    setState(() => _depremAlgilandi = false);
    _addLog('🔵 Elektrik güvenlik komutu gönderildi (B)', LogType.info);
  }

  void _onDisconnected() {
    if (mounted) {
      setState(() => _isConnected = false);
      _addLog('🔌 Bağlantı kesildi', LogType.danger);
    }
  }

  void _addLog(String msg, LogType type) {
    final now = TimeOfDay.now();
    final time =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    _logs.insert(0, _LogEntry(time: time, message: msg, type: type));
    if (_logs.length > 100) _logs.removeLast();
  }

  // Bağlantıyı kes
  void _disconnect() async {
    await widget.connection.close();
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    widget.connection.dispose();
    _logScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    const SizedBox(height: 16),
                    _buildDepremStatus(),
                    const SizedBox(height: 16),
                    _buildStatusCards(),
                    const SizedBox(height: 16),
                    _buildControlButtons(),
                    const SizedBox(height: 16),
                    _buildLogPanel(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Üst Bar ──
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        border: const Border(bottom: BorderSide(color: Colors.white12)),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isConnected ? const Color(0xFF4CAF50) : Colors.red,
              boxShadow: [
                BoxShadow(
                  color: (_isConnected ? Colors.green : Colors.red)
                      .withOpacity(0.6),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.device.name ?? 'Arduino',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                Text(
                  _isConnected ? 'Bağlı' : 'Bağlantı Kesildi',
                  style: TextStyle(
                    color: _isConnected ? Colors.green : Colors.red,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.bluetooth_disabled,
                color: Colors.white54, size: 22),
            onPressed: _disconnect,
            tooltip: 'Bağlantıyı Kes',
          ),
        ],
      ),
    );
  }

  // ── Deprem Durumu Kartı ──
  Widget _buildDepremStatus() {
    final isAlarm = _depremAlgilandi;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isAlarm
            ? const Color(0xFFB71C1C).withOpacity(0.3)
            : const Color(0xFF1B5E20).withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isAlarm ? const Color(0xFFEF5350) : const Color(0xFF4CAF50),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: (isAlarm ? Colors.red : Colors.green).withOpacity(0.2),
            blurRadius: 16,
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            isAlarm ? Icons.warning_amber_rounded : Icons.shield_rounded,
            size: 48,
            color:
                isAlarm ? const Color(0xFFEF5350) : const Color(0xFF4CAF50),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isAlarm ? '⚠️ DEPREM ALGILANDI!' : '✅ SİSTEM NORMAL',
                  style: TextStyle(
                    color: isAlarm
                        ? const Color(0xFFEF5350)
                        : const Color(0xFF4CAF50),
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isAlarm
                      ? 'Doğalgaz ve elektrik kesildi.\nAşağıdan güvenlik sağlayın.'
                      : 'MPU6050 ivmeölçer aktif izlemede.',
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Doğalgaz & Elektrik Durum Kartları ──
  Widget _buildStatusCards() {
    return Row(
      children: [
        Expanded(
          child: _StatusCard(
            label: 'DOGALGAZ',
            isActive: _dogalgazAktif,
            activeIcon: Icons.gas_meter,
            inactiveIcon: Icons.gas_meter_outlined,
            activeColor: const Color(0xFF4CAF50),
            inactiveColor: const Color(0xFFEF5350),
            activeText: 'Açık',
            inactiveText: 'Kesildi',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatusCard(
            label: 'ELEKTRİK',
            isActive: _elektrikAktif,
            activeIcon: Icons.electrical_services,
            inactiveIcon: Icons.power_off,
            activeColor: const Color(0xFFFFB300),
            inactiveColor: const Color(0xFFEF5350),
            activeText: 'Açık',
            inactiveText: 'Kesildi',
          ),
        ),
      ],
    );
  }

  // ── Kontrol Butonları ──
  Widget _buildControlButtons() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'GÜVENLİK KONTROL PANELİ',
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 2,
            color: Colors.white38,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            // A Komutu — Doğalgaz
            Expanded(
              child: _ControlButton(
                label: 'DOGALGAZ',
                sublabel: 'Vanayı Aç (A)',
                icon: Icons.gas_meter,
                color: const Color(0xFF2E7D32),
                onTap: _isConnected ? _dogalgaziSagla : null,
              ),
            ),
            const SizedBox(width: 12),
            // B Komutu — Elektrik
            Expanded(
              child: _ControlButton(
                label: 'ELEKTRİK',
                sublabel: 'Röleyi Kapat (B)',
                icon: Icons.electrical_services,
                color: const Color(0xFFF57F17),
                onTap: _isConnected ? _elektrigiSagla : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Her ikisini birden sağla
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isConnected
                ? () async {
                    await _sendCommand('A');
                    await Future.delayed(const Duration(milliseconds: 300));
                    await _sendCommand('B');
                    setState(() => _depremAlgilandi = false);
                    _addLog('🔵 Tüm sistemler yeniden sağlandı', LogType.success);
                  }
                : null,
            icon: const Icon(Icons.restart_alt),
            label: const Text('TÜM SİSTEMLERİ SAĞLA (A + B)'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1565C0),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }

  // ── Log Paneli ──
  Widget _buildLogPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'SİSTEM KAYITLARI',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 2,
                color: Colors.white38,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () => setState(() => _logs.clear()),
              child: const Text(
                'Temizle',
                style: TextStyle(fontSize: 11, color: Colors.white38),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          height: 200,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: _logs.isEmpty
              ? const Center(
                  child: Text(
                    'Henüz kayıt yok...',
                    style: TextStyle(color: Colors.white24, fontSize: 12),
                  ),
                )
              : ListView.builder(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: _logs.length,
                  itemBuilder: (context, i) {
                    final log = _logs[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            log.time,
                            style: const TextStyle(
                                color: Colors.white24, fontSize: 10),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              log.message,
                              style: TextStyle(
                                color: log.type.color,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  YARDIMCI WİDGET'LAR
// ─────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  final String label;
  final bool isActive;
  final IconData activeIcon;
  final IconData inactiveIcon;
  final Color activeColor;
  final Color inactiveColor;
  final String activeText;
  final String inactiveText;

  const _StatusCard({
    required this.label,
    required this.isActive,
    required this.activeIcon,
    required this.inactiveIcon,
    required this.activeColor,
    required this.inactiveColor,
    required this.activeText,
    required this.inactiveText,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive ? activeColor : inactiveColor;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          Icon(isActive ? activeIcon : inactiveIcon, color: color, size: 32),
          const SizedBox(height: 8),
          Text(label,
              style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 10,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            isActive ? activeText : inactiveText,
            style: TextStyle(
                color: color, fontWeight: FontWeight.bold, fontSize: 15),
          ),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final String label;
  final String sublabel;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _ControlButton({
    required this.label,
    required this.sublabel,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: onTap != null
              ? color.withOpacity(0.15)
              : Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: onTap != null ? color : Colors.white12,
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Icon(icon,
                color: onTap != null ? color : Colors.white24, size: 30),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: onTap != null ? color : Colors.white24,
                fontWeight: FontWeight.bold,
                fontSize: 12,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              sublabel,
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  LOG MODELI
// ─────────────────────────────────────────────────────────────
enum LogType { success, info, warning, danger }

extension LogTypeColor on LogType {
  Color get color {
    switch (this) {
      case LogType.success:
        return const Color(0xFF4CAF50);
      case LogType.info:
        return const Color(0xFF42A5F5);
      case LogType.warning:
        return const Color(0xFFFFB300);
      case LogType.danger:
        return const Color(0xFFEF5350);
    }
  }
}

class _LogEntry {
  final String time;
  final String message;
  final LogType type;
  _LogEntry({required this.time, required this.message, required this.type});
}
