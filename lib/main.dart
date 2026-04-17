// ============================================================
// main.dart — ODAK Otomatik Deprem Acil Kesicisi
// Mobil Uygulama Ana Ekranı
//
// Haberleşme Önceliği:
//   Plan C → WiFi REST API  (ESP32 aynı ağda)
//   Plan A → Firebase RTDB  (internet üzerinden)
//   Plan B → BLE Bluetooth  (yakın mesafe, yedek)
// ============================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'firebase_options.dart';
import 'services/firebase_service.dart';
import 'services/ble_service.dart';
import 'services/wifi_api_service.dart';

// ================================================================
// FCM: arka plan mesaj handler (top-level zorunlu)
// ================================================================
@pragma('vm:entry-point')
Future<void> _fcmArkaplanHandler(RemoteMessage mesaj) async {
  debugPrint('FCM arka plan: ${mesaj.notification?.title}');
}

// ================================================================
// Uygulama girişi
// ================================================================
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var firebaseHazir = true;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('[Firebase] Başlatıldı ✅');
  } catch (e) {
    firebaseHazir = false;
    debugPrint('[Firebase] Başlatılamadı — WiFi/BLE moduna geçildi: $e');
    // firebase_options.dart dosyasındaki BURAYA_* alanlarını doldurun!
  }
  runApp(OdakApp(firebaseHazir: firebaseHazir));
}

// ================================================================
// Renk & Tasarım Sabitleri
// ================================================================
class OdakColors {
  static const Color primary      = Color(0xFF005EAC);
  static const Color primaryDark  = Color(0xFF003D7A);
  static const Color primaryLight = Color(0xFF1E88E5);
  static const Color success      = Color(0xFF2E7D32);
  static const Color warning      = Color(0xFFFF9800);
  static const Color danger       = Color(0xFFC62828);
  static const Color background   = Color(0xFFF5F7FA);
  static const Color surface      = Color(0xFFFFFFFF);
  static const Color textPrimary  = Color(0xFF1A1A2E);
  static const Color textSecondary= Color(0xFF6B7280);
  static const Color textTertiary = Color(0xFFBDBDBD);
}

class OdakSpacing {
  static const double xs  = 4;
  static const double sm  = 8;
  static const double md  = 16;
  static const double lg  = 24;
  static const double xl  = 32;
  static const double xxl = 48;
}

class OdakRadius {
  static const double sm     = 8;
  static const double md     = 12;
  static const double lg     = 16;
  static const double xl     = 20;
  static const double circle = 100;
}

// ================================================================
// Kök Widget
// ================================================================
class OdakApp extends StatelessWidget {
  final bool firebaseHazir;
  const OdakApp({super.key, this.firebaseHazir = true});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ODAK — Deprem Güvenlik',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.light(
          primary:            OdakColors.primary,
          onPrimary:          Colors.white,
          primaryContainer:   OdakColors.primaryLight,
          onPrimaryContainer: Colors.white,
          secondary:          OdakColors.warning,
          onSecondary:        Colors.white,
          error:              OdakColors.danger,
          onError:            Colors.white,
          surface:            OdakColors.surface,
          onSurface:          OdakColors.textPrimary,
        ),
        scaffoldBackgroundColor: OdakColors.background,
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          backgroundColor: OdakColors.primary,
          foregroundColor: Colors.white,
          elevation: 4,
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: 0.5,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: OdakColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(OdakRadius.lg),
            ),
            elevation: 3,
          ),
        ),
        cardTheme: CardThemeData(
          color: OdakColors.surface,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(OdakRadius.lg),
          ),
          margin: EdgeInsets.zero,
        ),
      ),
      home: AnaSayfa(firebaseHazir: firebaseHazir),
    );
  }
}

// ================================================================
// Ana Sayfa
// ================================================================
class AnaSayfa extends StatefulWidget {
  final bool firebaseHazir;
  const AnaSayfa({super.key, this.firebaseHazir = true});

  @override
  State<AnaSayfa> createState() => _AnaSayfaState();
}

class _AnaSayfaState extends State<AnaSayfa>
    with SingleTickerProviderStateMixin {

  // ---------- Servisler ----------
  FirebaseService?   _fb;
  final _ble  = BleService();
  final _wifi = WifiApiService();

  // ---------- Durum ----------
  CihazDurumu?       _cihazDurumu;
  String             _bilgiMetni = 'Sistem bekleniyor...';
  bool               _islemVar   = false;
  BleDurum?          _bleDurum;
  WifiBaglantiDurumu _wifiDurum  = WifiBaglantiDurumu.bilinmiyor;

  // ---------- Abonelikler ----------
  StreamSubscription<CihazDurumu>?        _fbAbone;
  StreamSubscription<BleDurum>?           _bleAbone;
  StreamSubscription<EspDurum>?           _wifiAbone;
  StreamSubscription<WifiBaglantiDurumu>? _wifiBaglantiAbone;

  // ---------- Animasyon ----------
  late AnimationController _animKontrol;
  late Animation<double>   _opasiteAnim;

  // ----------------------------------------------------------------
  @override
  void initState() {
    super.initState();
    _animasyonKur();
    _bleDinle();
    _wifiDinle();

    if (widget.firebaseHazir) {
      _fb = FirebaseService();
      _firebaseDinle();
      _fcmKur();
    } else {
      _bilgiMetni = 'Firebase yok — WiFi/BLE modu aktif.';
    }
  }

  // ----------------------------------------------------------------
  void _animasyonKur() {
    _animKontrol = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _opasiteAnim = Tween<double>(begin: 0.6, end: 1.0)
        .animate(CurvedAnimation(parent: _animKontrol, curve: Curves.easeInOut));
  }

  // ----------------------------------------------------------------
  void _firebaseDinle() {
    _fbAbone = _fb!.cihazDurumu.listen(
      (durum) => setState(() {
        _cihazDurumu = durum;
        _bilgiMetni  = durum.tehlikede
            ? '⚠️ Deprem algılandı! Gaz ve elektrik kesildi.'
            : '✅ Sistem güvende — Sinyal: ${durum.sinyalKalitesi}';
        if (!durum.tehlikede) _islemVar = false;
      }),
      onError: (e) => setState(() => _bilgiMetni = '🔴 Firebase hatası: $e'),
    );
  }

  // ----------------------------------------------------------------
  void _bleDinle() {
    _bleAbone = _ble.durumStream.listen((durum) {
      if (!mounted) return;
      setState(() {
        _bleDurum   = durum;
        _bilgiMetni = durum.metin;
        if (durum == BleDurum.komutGonderildi || durum == BleDurum.hata) {
          _islemVar = false;
        }
      });
    });
  }

  // ----------------------------------------------------------------
  void _wifiDinle() {
    _wifiBaglantiAbone = _wifi.baglantiStream.listen((durum) {
      if (!mounted) return;
      setState(() => _wifiDurum = durum);
    });
    _wifiAbone = _wifi.espDurumStream.listen((espDurum) {
      if (!mounted) return;
      setState(() {
        _bilgiMetni = espDurum.tehlikede
            ? '⚠️ ESP32: Deprem algılandı! Gaz ve elektrik kesildi.'
            : '✅ ESP32 Güvende — Sinyal: ${espDurum.sinyalKalitesi}';
      });
    });
  }

  // ----------------------------------------------------------------
  void _ipDialogGoster() {
    // Mevcut IP'yi göster (boşsa SoftAP varsayılanı)
    final controller = TextEditingController(text: _wifi.espIpAdresi);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OdakRadius.xl),
        ),
        title: const Row(
          children: [
            Icon(Icons.router, color: OdakColors.primary),
            SizedBox(width: 8),
            Text('ESP32 WiFi Bağlantısı'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // SoftAP hızlı bağlantı butonu
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _wifi.softApBaglantisiKur();
                setState(() => _bilgiMetni = 'SoftAP bağlantısı test ediliyor...');
                _wifiBaglantiTest();
              },
              icon: const Icon(Icons.wifi_tethering, size: 16),
              label: const Text('SoftAP ile Otomatik Bağlan\n(192.168.4.1)',
                  style: TextStyle(fontSize: 12)),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(child: Divider()),
                  Padding(padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('veya manuel IP', style: TextStyle(fontSize: 11))),
                  Expanded(child: Divider()),
                ],
              ),
            ),
            const Text(
              'ESP32 farklı bir ağdaysa IP\'sini girin.\n'
              'IP\'yi Arduino Serial Monitor\'dan öğrenebilirsiniz.',
              style: TextStyle(fontSize: 12, color: OdakColors.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'IP Adresi',
                hintText: '192.168.4.1',
                prefixIcon: const Icon(Icons.lan),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(OdakRadius.md),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              final ip = controller.text.trim();
              if (ip.isNotEmpty) {
                _wifi.espIpAdresi = ip;
                setState(() => _bilgiMetni = 'ESP32 bağlantısı test ediliyor...');
                Navigator.pop(ctx);
                _wifiBaglantiTest();
              }
            },
            icon: const Icon(Icons.wifi, size: 16),
            label: const Text('Manuel Bağlan'),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------
  Future<void> _wifiBaglantiTest() async {
    setState(() => _bilgiMetni = '🔄 ESP32 aranıyor...');
    final baglandi = await _wifi.ping();
    if (!mounted) return;
    if (baglandi) {
      setState(() => _bilgiMetni = '✅ ESP32 bağlandı — WiFi SoftAP üzerinden.');
      _wifi.pollingBaslat(saniye: 3);
    } else {
      setState(() => _bilgiMetni =
          '❌ ESP32\'ye ulaşılamadı. "ODAK_Sistem" ağına bağlı olduğunuzdan emin olun.');
      _snackGoster(
        'ESP32 bağlantısı başarısız. WiFi ağını kontrol edin.',
        renk: OdakColors.danger,
      );
    }
  }

  // ----------------------------------------------------------------
  Future<void> _fcmKur() async {
    FirebaseMessaging.onBackgroundMessage(_fcmArkaplanHandler);
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);
    await messaging.subscribeToTopic('deprem_alarmi');
    FirebaseMessaging.onMessage.listen((mesaj) {
      final baslik = mesaj.notification?.title ?? '';
      final govde  = mesaj.notification?.body  ?? '';
      _snackGoster('$baslik — $govde', renk: OdakColors.danger);
    });
  }

  // ----------------------------------------------------------------
  // Elektrik Aktifleştir  (WiFi → Firebase → BLE)
  // ----------------------------------------------------------------
  Future<void> _elektrikAktif() async {
    if (_islemVar) return;
    setState(() { _islemVar = true; _bilgiMetni = 'Elektrik komutu gönderiliyor...'; });

    if (_wifi.ipGirildi) {
      final sonuc = await _wifi.elektrikAktifEt();
      if (sonuc.basarili) {
        if (mounted) setState(() { _bilgiMetni = '✅ Elektrik verildi (WiFi)'; _islemVar = false; });
        return;
      }
    }

    if (widget.firebaseHazir && _fb != null) {
      try {
        await _fb!.elektrikAktifEt();
        if (mounted) setState(() { _bilgiMetni = '✅ Elektrik komutu gönderildi.'; _islemVar = false; });
        return;
      } catch (_) {}
    }

    final sonuc = await _ble.elektrikAktifEt();
    if (mounted) {
      if (!sonuc.basarili) _snackGoster(sonuc.mesaj, renk: OdakColors.danger);
      setState(() => _islemVar = false);
    }
  }

  // ----------------------------------------------------------------
  // Doğalgaz Aktifleştir  (WiFi → Firebase → BLE)
  // ----------------------------------------------------------------
  Future<void> _dogalgazAktif() async {
    if (_islemVar) return;
    setState(() { _islemVar = true; _bilgiMetni = 'Doğalgaz komutu gönderiliyor...'; });

    if (_wifi.ipGirildi) {
      final sonuc = await _wifi.gazAc();
      if (sonuc.basarili) {
        if (mounted) setState(() { _bilgiMetni = '✅ Doğalgaz açıldı (WiFi)'; _islemVar = false; });
        return;
      }
    }

    if (widget.firebaseHazir && _fb != null) {
      try {
        await _fb!.dogalgazAktifEt();
        if (mounted) setState(() { _bilgiMetni = '✅ Doğalgaz komutu gönderildi.'; _islemVar = false; });
        return;
      } catch (_) {}
    }

    final sonuc = await _ble.dogalgazAktifEt();
    if (mounted) {
      if (!sonuc.basarili) _snackGoster(sonuc.mesaj, renk: OdakColors.danger);
      setState(() => _islemVar = false);
    }
  }

  // ----------------------------------------------------------------
  void _snackGoster(String mesaj, {Color renk = OdakColors.success}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mesaj, style: const TextStyle(color: Colors.white)),
        backgroundColor: renk,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(OdakRadius.md)),
        margin: const EdgeInsets.all(OdakSpacing.md),
      ),
    );
  }

  // ----------------------------------------------------------------
  @override
  void dispose() {
    _animKontrol.dispose();
    _fbAbone?.cancel();
    _bleAbone?.cancel();
    _wifiAbone?.cancel();
    _wifiBaglantiAbone?.cancel();
    _ble.kapat();
    _wifi.kapat();
    super.dispose();
  }

  // ================================================================
  // BUILD
  // ================================================================
  @override
  Widget build(BuildContext context) {
    final tehlikede = _cihazDurumu?.tehlikede ?? false;

    return Scaffold(
      backgroundColor: OdakColors.background,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('odak_logo_1.png', height: 30, fit: BoxFit.contain),
            const SizedBox(width: 10),
            const Text('ODAK'),
          ],
        ),
        actions: [
          // WiFi bağlantı badge'i
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: _WifiBadge(
              durum: _wifiDurum,
              ipGirildi: _wifi.ipGirildi,
              onTap: _ipDialogGoster,
            ),
          ),
          // Yenile butonu
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Yenile',
            onPressed: () {
              if (_wifi.ipGirildi) _wifiBaglantiTest();
              if (widget.firebaseHazir && _fb != null) _fb!.anlikDurum();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(OdakSpacing.lg),
          child: Column(
            children: [
              // --- Durum Kartı ---
              _DurumKarti(
                tehlikede: tehlikede,
                animasyon: _opasiteAnim,
                durum: _cihazDurumu,
              ),
              const SizedBox(height: OdakSpacing.lg),

              // --- Bilgi / Bağlantı Durumu ---
              _BilgiKarti(
                metin: _bilgiMetni,
                bleDurum: _bleDurum,
                wifiDurum: _wifiDurum,
                islemVar: _islemVar,
              ),
              const SizedBox(height: OdakSpacing.xl),

              // --- Kontrol Butonları ---
              Row(
                children: [
                  Expanded(
                    child: _KontrolButon(
                      onPressed: _islemVar ? null : _elektrikAktif,
                      isLoading: _islemVar,
                      icon: Icons.electrical_services_rounded,
                      label: 'Elektrik\nAktifleştir',
                      renk: OdakColors.warning,
                    ),
                  ),
                  const SizedBox(width: OdakSpacing.lg),
                  Expanded(
                    child: _KontrolButon(
                      onPressed: _islemVar ? null : _dogalgazAktif,
                      isLoading: _islemVar,
                      icon: Icons.local_fire_department_rounded,
                      label: 'Doğalgaz\nAktifleştir',
                      renk: OdakColors.primaryLight,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: OdakSpacing.lg),

              // --- WiFi bağlantı kutu ---
              _WifiKlavuz(
                onTap: _ipDialogGoster,
                bagli: _wifiDurum == WifiBaglantiDurumu.bagli,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ================================================================
// Durum Kartı Widget
// ================================================================
class _DurumKarti extends StatelessWidget {
  final bool               tehlikede;
  final Animation<double>  animasyon;
  final CihazDurumu?       durum;

  const _DurumKarti({
    required this.tehlikede,
    required this.animasyon,
    required this.durum,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animasyon,
      builder: (ctx, child) => Opacity(
        opacity: tehlikede ? animasyon.value : 1.0,
        child: child,
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: OdakSpacing.xl, horizontal: OdakSpacing.lg),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: tehlikede
                ? [OdakColors.danger, Color(0xFFB71C1C)]
                : [OdakColors.primaryDark, OdakColors.primary],
          ),
          borderRadius: BorderRadius.circular(OdakRadius.xl),
          boxShadow: [
            BoxShadow(
              color: (tehlikede ? OdakColors.danger : OdakColors.primary)
                  .withValues(alpha: 0.4),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.18),
              ),
              child: Icon(
                tehlikede ? Icons.warning_amber_rounded : Icons.verified_user_rounded,
                size: 40,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: OdakSpacing.lg),
            Text(
              tehlikede ? 'GAZ VE ELEKTRİK KESİLDİ' : 'SİSTEM GÜVENLİ',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
              textAlign: TextAlign.center,
            ),
            if (durum != null && tehlikede) ...[
              const SizedBox(height: OdakSpacing.md),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(OdakRadius.circle),
                ),
                child: Text(
                  'Son deprem: ${_formatZaman(durum!.sonDepremZamani)}',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatZaman(int ts) {
    if (ts == 0) return 'bilinmiyor';
    final dt = DateTime.fromMillisecondsSinceEpoch(ts);
    return '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
  }
}

// ================================================================
// Bilgi Kartı Widget
// ================================================================
class _BilgiKarti extends StatelessWidget {
  final String             metin;
  final BleDurum?          bleDurum;
  final WifiBaglantiDurumu wifiDurum;
  final bool               islemVar;

  const _BilgiKarti({
    required this.metin,
    required this.bleDurum,
    required this.wifiDurum,
    required this.islemVar,
  });

  @override
  Widget build(BuildContext context) {
    final Color renk = _renkSec();
    final IconData ikon = _ikonSec();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(OdakSpacing.md),
      decoration: BoxDecoration(
        color: OdakColors.surface,
        borderRadius: BorderRadius.circular(OdakRadius.lg),
        border: Border.all(color: renk.withValues(alpha: 0.2), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: renk.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: renk.withValues(alpha: 0.12),
            ),
            child: islemVar
                ? Padding(
                    padding: const EdgeInsets.all(10),
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(renk),
                    ),
                  )
                : Icon(ikon, size: 20, color: renk),
          ),
          const SizedBox(width: OdakSpacing.md),
          Expanded(
            child: Text(
              metin,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: OdakColors.textPrimary,
                height: 1.4,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Color _renkSec() {
    if (metin.contains('⚠️') || bleDurum == BleDurum.hata) return OdakColors.danger;
    if (wifiDurum == WifiBaglantiDurumu.bagli) return OdakColors.success;
    if (bleDurum == BleDurum.komutGonderildi) return OdakColors.success;
    if (bleDurum != null) return OdakColors.primary;
    return OdakColors.textTertiary;
  }

  IconData _ikonSec() {
    if (metin.contains('⚠️') || bleDurum == BleDurum.hata) return Icons.error_outline_rounded;
    if (wifiDurum == WifiBaglantiDurumu.bagli) return Icons.wifi_rounded;
    if (bleDurum == BleDurum.komutGonderildi) return Icons.check_circle_outline_rounded;
    if (bleDurum != null) return Icons.bluetooth_rounded;
    return Icons.info_outline_rounded;
  }
}

// ================================================================
// Kontrol Butonu Widget
// ================================================================
class _KontrolButon extends StatefulWidget {
  final VoidCallback? onPressed;
  final bool          isLoading;
  final IconData      icon;
  final String        label;
  final Color         renk;

  const _KontrolButon({
    required this.onPressed,
    required this.isLoading,
    required this.icon,
    required this.label,
    required this.renk,
  });

  @override
  State<_KontrolButon> createState() => _KontrolButonState();
}

class _KontrolButonState extends State<_KontrolButon>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 150));
    _scale = Tween<double>(begin: 1.0, end: 0.94)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  void _onTap() {
    if (widget.onPressed == null || widget.isLoading) return;
    _ctrl.forward().then((_) => _ctrl.reverse());
    widget.onPressed!();
  }

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onPressed == null;
    return ScaleTransition(
      scale: _scale,
      child: GestureDetector(
        onTap: _onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 130,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: disabled
                  ? [const Color(0xFFBDBDBD), const Color(0xFF9E9E9E)]
                  : [widget.renk, widget.renk.withValues(alpha: 0.75)],
            ),
            borderRadius: BorderRadius.circular(OdakRadius.xl),
            boxShadow: disabled ? [] : [
              BoxShadow(
                color: widget.renk.withValues(alpha: 0.35),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              widget.isLoading
                  ? const SizedBox(
                      width: 36, height: 36,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Icon(widget.icon, size: 40, color: Colors.white),
              const SizedBox(height: 10),
              Text(
                widget.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ================================================================
// WiFi Badge (AppBar)
// ================================================================
class _WifiBadge extends StatelessWidget {
  final WifiBaglantiDurumu durum;
  final bool               ipGirildi;
  final VoidCallback        onTap;

  const _WifiBadge({
    required this.durum,
    required this.ipGirildi,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color  renk;
    final IconData ikon;
    final String   etiket;

    switch (durum) {
      case WifiBaglantiDurumu.bagli:
        renk = const Color(0xFF4CAF50); ikon = Icons.wifi_rounded; etiket = 'WiFi ✓';
      case WifiBaglantiDurumu.baglanamadi:
      case WifiBaglantiDurumu.zamanasimiAsildi:
        renk = const Color(0xFFEF5350); ikon = Icons.wifi_off_rounded; etiket = 'Bağlantı Yok';
      default:
        renk = ipGirildi ? OdakColors.warning : Colors.white54;
        ikon = Icons.wifi_find_rounded;
        etiket = ipGirildi ? 'Test Et' : 'IP Gir';
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(OdakRadius.circle),
          border: Border.all(color: renk.withValues(alpha: 0.7), width: 1.2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(ikon, size: 13, color: renk),
            const SizedBox(width: 4),
            Text(etiket, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: renk)),
          ],
        ),
      ),
    );
  }
}

// ================================================================
// WiFi Kılavuz Kartı (IP girilmemişse göster)
// ================================================================
class _WifiKlavuz extends StatelessWidget {
  final VoidCallback onTap;
  final bool         bagli;
  const _WifiKlavuz({required this.onTap, this.bagli = false});

  @override
  Widget build(BuildContext context) {
    final renk  = bagli ? OdakColors.success : OdakColors.primary;
    final metin = bagli
        ? 'ESP32 bağlı — "ODAK_Sistem" ağı üzerinden izleniyor.'
        : 'ESP32 bağlantısı için dokun.\n"ODAK_Sistem" WiFi ağına bağlı olduğunuzdan emin olun.';
    final ikon  = bagli
        ? Icons.wifi_rounded
        : Icons.tips_and_updates_rounded;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: double.infinity,
        padding: const EdgeInsets.all(OdakSpacing.md),
        decoration: BoxDecoration(
          color: renk.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(OdakRadius.lg),
          border: Border.all(color: renk.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(ikon, color: renk, size: 22),
            const SizedBox(width: OdakSpacing.md),
            Expanded(
              child: Text(
                metin,
                style: TextStyle(
                  fontSize: 12,
                  color: renk,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, size: 14, color: renk),
          ],
        ),
      ),
    );
  }
}
