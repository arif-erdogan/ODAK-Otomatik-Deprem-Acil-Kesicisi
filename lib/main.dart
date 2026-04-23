// ============================================================
// main.dart — ODAK Otomatik Deprem Acil Kesicisi
// Mobil Uygulama Ana Ekranı  |  v3.3 (Cihaz Listesi)
//
// Haberleşme:
//   Bluetooth Serial (SPP) — Arduino Uno + HC-06
//   (WiFi ve Firebase kaldırıldı)
// ============================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'services/ble_service.dart';
import 'screens/devices_screen.dart';

// ================================================================
// Uygulama girişi
// ================================================================
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OdakApp());
}

// ================================================================
// Renk & Tasarım Sabitleri
// ================================================================
class OdakColors {
  static const Color primary = Color(0xFF005EAC);
  static const Color primaryDark = Color(0xFF003D7A);
  static const Color primaryLight = Color(0xFF1E88E5);
  static const Color success = Color(0xFF2E7D32);
  static const Color warning = Color(0xFFFF9800);
  static const Color danger = Color(0xFFC62828);
  static const Color background = Color(0xFFF5F7FA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF1A1A2E);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textTertiary = Color(0xFFBDBDBD);
}

class OdakSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

class OdakRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double circle = 100;
}

// ================================================================
// Kök Widget
// ================================================================
class OdakApp extends StatelessWidget {
  const OdakApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ODAK — Deprem Güvenlik',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.light(
          primary: OdakColors.primary,
          onPrimary: Colors.white,
          primaryContainer: OdakColors.primaryLight,
          onPrimaryContainer: Colors.white,
          secondary: OdakColors.warning,
          onSecondary: Colors.white,
          error: OdakColors.danger,
          onError: Colors.white,
          surface: OdakColors.surface,
          onSurface: OdakColors.textPrimary,
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
      home: const DevicesScreen(),
    );
  }
}

// ================================================================
// Ana Sayfa
// ================================================================
class AnaSayfa extends StatefulWidget {
  const AnaSayfa({super.key});

  @override
  State<AnaSayfa> createState() => _AnaSayfaState();
}

class _AnaSayfaState extends State<AnaSayfa>
    with SingleTickerProviderStateMixin {
  // ---------- Servisler ----------
  final _bt = BleService();

  // ---------- Durum ----------
  ArduinoDurum? _arduinoDurum;
  String _bilgiMetni = 'Bluetooth bağlantısı bekleniyor...';
  bool _islemVar = false;
  BtDurum _btDurum = BtDurum.hazir;

  // ---------- Abonelikler ----------
  StreamSubscription<BtDurum>? _btDurumAbone;
  StreamSubscription<ArduinoDurum>? _arduinoAbone;
  StreamSubscription<String>? _yanitAbone;

  // ---------- Animasyon ----------
  late AnimationController _animKontrol;
  late Animation<double> _opasiteAnim;

  // ----------------------------------------------------------------
  @override
  void initState() {
    super.initState();
    _animasyonKur();
    _bluetoothDinle();
    // Uygulama açılışında izin + BT akışını başlat
    WidgetsBinding.instance.addPostFrameCallback((_) => _baslatAkisi());
  }

  // ── Başlangıç Akışı ─────────────────────────────────────────
  Future<void> _baslatAkisi() async {
    // 1. Bluetooth açık mı?
    final btAcik = await _bt.bluetoothAcikMi();
    if (!mounted) return;

    if (!btAcik) {
      setState(() => _bilgiMetni = '⚠️ Bluetooth kapalı. Lütfen açın.');
      // baglan() zaten BT açma isteği yapıyor — direkt o akışa gir
      await _bluetoothBaglan();
      return;
    }

    // 2. İzinleri iste ("Yakındaki Cihazlar" diyaloğu burada açılır)
    setState(() => _bilgiMetni = '🔐 Bluetooth izinleri isteniyor...');
    final izinOk = await _bt.izinleriKontrolEt();
    if (!mounted) return;

    if (!izinOk) {
      // Kalıcı red → ayarlara yönlendir
      final kaliciRed = await _bt.izinKaliciRedMi();
      if (!mounted) return;

      if (kaliciRed) {
        _kaliciRedDiyalogu();
      } else {
        setState(() => _bilgiMetni =
            '❌ Bluetooth izinleri reddedildi. Tekrar denemek için dokunun.');
      }
      return;
    }

    // 3. İzinler tamam → otomatik bağlan
    await _bluetoothBaglan();
  }

  // ── Kalıcı Red Diyaloğu ─────────────────────────────────────
  void _kaliciRedDiyalogu() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(OdakRadius.xl)),
        title: const Row(
          children: [
            Icon(Icons.bluetooth_disabled_rounded,
                color: OdakColors.danger, size: 28),
            SizedBox(width: 10),
            Text('Bluetooth İzni Gerekli',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ],
        ),
        content: const Text(
          'ODAK uygulamasının çalışabilmesi için\n'
          '"Yakındaki Cihazlar" iznine ihtiyaç vardır.\n\n'
          'Ayarlar → Uygulamalar → ODAK → İzinler\n'
          'bölümünden izni etkinleştirin.',
          style: TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            icon: const Icon(Icons.settings_rounded, size: 16),
            label: const Text('Ayarları Aç'),
            style:
                ElevatedButton.styleFrom(backgroundColor: OdakColors.primary),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------
  void _animasyonKur() {
    _animKontrol = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _opasiteAnim = Tween<double>(begin: 0.6, end: 1.0).animate(
        CurvedAnimation(parent: _animKontrol, curve: Curves.easeInOut));
  }

  // ----------------------------------------------------------------
  void _bluetoothDinle() {
    // Bağlantı durumu
    _btDurumAbone = _bt.durumStream.listen((durum) {
      if (!mounted) return;
      setState(() {
        _btDurum = durum;
        _bilgiMetni = durum.metin;
        if (durum == BtDurum.komutGonderildi || durum == BtDurum.hata) {
          _islemVar = false;
        }
      });
    });

    // Arduino durum güncellemeleri
    _arduinoAbone = _bt.arduinoDurumStream.listen((durum) {
      if (!mounted) return;
      setState(() {
        _arduinoDurum = durum;
        if (durum.tehlikede) {
          _bilgiMetni = '⚠️ Deprem algılandı! Gaz ve elektrik kesildi.';
        } else {
          _bilgiMetni = '✅ Sistem güvende — Uptime: ${durum.uptimeSn}s';
        }
      });
    });

    // Komut yanıtları
    _yanitAbone = _bt.yanitStream.listen((yanit) {
      if (!mounted) return;
      if (yanit.startsWith('OK:')) {
        _snackGoster('✅ ${yanit.substring(3)} başarılı',
            renk: OdakColors.success);
      } else if (yanit.startsWith('ERR:')) {
        _snackGoster('❌ Hata: ${yanit.substring(4)}', renk: OdakColors.danger);
      } else if (yanit.startsWith('ALARM:')) {
        _snackGoster('⚠️ ${yanit.substring(6)}', renk: OdakColors.danger);
      }
    });
  }

  // ----------------------------------------------------------------
  Future<void> _bluetoothBaglan() async {
    setState(() {
      _islemVar = true;
      _bilgiMetni = '🔄 Arduino aranıyor...';
    });

    final sonuc = await _bt.baglan();

    if (!mounted) return;
    setState(() {
      _islemVar = false;
      _bilgiMetni = sonuc.basarili
          ? '✅ Bluetooth bağlandı — Arduino ile iletişim kuruldu.'
          : '❌ ${sonuc.mesaj}';
    });

    if (!sonuc.basarili) {
      _snackGoster(sonuc.mesaj, renk: OdakColors.danger);
    }
  }

  // ----------------------------------------------------------------
  // Elektrik Aktifleştir (Bluetooth)
  // ----------------------------------------------------------------
  Future<void> _elektrikAktif() async {
    if (_islemVar) return;
    setState(() {
      _islemVar = true;
      _bilgiMetni = 'Elektrik komutu gönderiliyor...';
    });

    final sonuc = await _bt.elektrikAktifEt();

    if (mounted) {
      setState(() {
        _islemVar = false;
        _bilgiMetni = sonuc.basarili
            ? '✅ Elektrik verildi (Bluetooth)'
            : '❌ ${sonuc.mesaj}';
      });
      if (!sonuc.basarili) _snackGoster(sonuc.mesaj, renk: OdakColors.danger);
    }
  }

  // ----------------------------------------------------------------
  // Doğalgaz Aktifleştir (Bluetooth)
  // ----------------------------------------------------------------
  Future<void> _dogalgazAktif() async {
    if (_islemVar) return;
    setState(() {
      _islemVar = true;
      _bilgiMetni = 'Doğalgaz komutu gönderiliyor...';
    });

    final sonuc = await _bt.dogalgazAktifEt();

    if (mounted) {
      setState(() {
        _islemVar = false;
        _bilgiMetni = sonuc.basarili
            ? '✅ Doğalgaz açıldı (Bluetooth)'
            : '❌ ${sonuc.mesaj}';
      });
      if (!sonuc.basarili) _snackGoster(sonuc.mesaj, renk: OdakColors.danger);
    }
  }

  // ----------------------------------------------------------------
  // Alarm Sıfırla (Bluetooth)
  // ----------------------------------------------------------------
  Future<void> _alarmSifirla() async {
    if (_islemVar) return;
    setState(() {
      _islemVar = true;
      _bilgiMetni = 'Alarm sıfırlanıyor...';
    });

    final sonuc = await _bt.alarmSifirla();

    if (mounted) {
      setState(() {
        _islemVar = false;
        _bilgiMetni = sonuc.basarili
            ? '✅ Alarm sıfırlandı — Sistemler açıldı'
            : '❌ ${sonuc.mesaj}';
      });
      if (!sonuc.basarili) _snackGoster(sonuc.mesaj, renk: OdakColors.danger);
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
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(OdakRadius.md)),
        margin: const EdgeInsets.all(OdakSpacing.md),
      ),
    );
  }

  // ----------------------------------------------------------------
  @override
  void dispose() {
    _animKontrol.dispose();
    _btDurumAbone?.cancel();
    _arduinoAbone?.cancel();
    _yanitAbone?.cancel();
    _bt.kapat();
    super.dispose();
  }

  // ================================================================
  // BUILD
  // ================================================================
  @override
  Widget build(BuildContext context) {
    final tehlikede = _arduinoDurum?.tehlikede ?? false;

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
          // Bluetooth bağlantı badge'i
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: _BluetoothBadge(
              durum: _btDurum,
              bagliMi: _bt.bagliMi,
              onTap: _bluetoothBaglan,
            ),
          ),
          // Yenile butonu
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Durum İste',
            onPressed: () {
              if (_bt.bagliMi) {
                _bt.durumIste();
              } else {
                _bluetoothBaglan();
              }
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
                durum: _arduinoDurum,
              ),
              const SizedBox(height: OdakSpacing.lg),

              // --- Bilgi / Bağlantı Durumu ---
              _BilgiKarti(
                metin: _bilgiMetni,
                btDurum: _btDurum,
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
              const SizedBox(height: OdakSpacing.md),

              // --- Alarm Sıfırla Butonu ---
              if (tehlikede)
                Padding(
                  padding: const EdgeInsets.only(bottom: OdakSpacing.md),
                  child: SizedBox(
                    width: double.infinity,
                    child: _KontrolButon(
                      onPressed: _islemVar ? null : _alarmSifirla,
                      isLoading: _islemVar,
                      icon: Icons.restart_alt_rounded,
                      label: 'Alarmı Sıfırla\n(Tümünü Aç)',
                      renk: OdakColors.danger,
                    ),
                  ),
                ),
              const SizedBox(height: OdakSpacing.md),

              // --- Bluetooth Kılavuz ---
              _BluetoothKlavuz(
                onTap: _bluetoothBaglan,
                bagli: _bt.bagliMi,
              ),

              // --- Sistem Bilgileri ---
              if (_arduinoDurum != null) ...[
                const SizedBox(height: OdakSpacing.lg),
                _SistemBilgiKarti(durum: _arduinoDurum!),
              ],
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
  final bool tehlikede;
  final Animation<double> animasyon;
  final ArduinoDurum? durum;

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
        padding: const EdgeInsets.symmetric(
            vertical: OdakSpacing.xl, horizontal: OdakSpacing.lg),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: tehlikede
                ? [OdakColors.danger, const Color(0xFFB71C1C)]
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
                tehlikede
                    ? Icons.warning_amber_rounded
                    : Icons.verified_user_rounded,
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
            if (tehlikede) ...[
              const SizedBox(height: OdakSpacing.md),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(OdakRadius.circle),
                ),
                child: const Text(
                  'Deprem algılandı — Gaz ve elektrik kesildi!',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ================================================================
// Bilgi Kartı Widget
// ================================================================
class _BilgiKarti extends StatelessWidget {
  final String metin;
  final BtDurum btDurum;
  final bool islemVar;

  const _BilgiKarti({
    required this.metin,
    required this.btDurum,
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
    if (metin.contains('⚠️') || btDurum == BtDurum.hata)
      return OdakColors.danger;
    if (btDurum == BtDurum.bagli) return OdakColors.success;
    if (btDurum == BtDurum.komutGonderildi) return OdakColors.success;
    if (btDurum == BtDurum.taraniyor || btDurum == BtDurum.baglaniyor)
      return OdakColors.primary;
    return OdakColors.textTertiary;
  }

  IconData _ikonSec() {
    if (metin.contains('⚠️') || btDurum == BtDurum.hata)
      return Icons.error_outline_rounded;
    if (btDurum == BtDurum.bagli) return Icons.bluetooth_connected_rounded;
    if (btDurum == BtDurum.komutGonderildi)
      return Icons.check_circle_outline_rounded;
    if (btDurum == BtDurum.taraniyor) return Icons.bluetooth_searching_rounded;
    return Icons.info_outline_rounded;
  }
}

// ================================================================
// Kontrol Butonu Widget
// ================================================================
class _KontrolButon extends StatefulWidget {
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData icon;
  final String label;
  final Color renk;

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
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 150));
    _scale = Tween<double>(begin: 1.0, end: 0.94)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

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
            boxShadow: disabled
                ? []
                : [
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
                      width: 36,
                      height: 36,
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
// Bluetooth Badge (AppBar)
// ================================================================
class _BluetoothBadge extends StatelessWidget {
  final BtDurum durum;
  final bool bagliMi;
  final VoidCallback onTap;

  const _BluetoothBadge({
    required this.durum,
    required this.bagliMi,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color renk;
    final IconData ikon;
    final String etiket;

    if (bagliMi || durum == BtDurum.bagli) {
      renk = const Color(0xFF4CAF50);
      ikon = Icons.bluetooth_connected_rounded;
      etiket = 'BT ✓';
    } else if (durum == BtDurum.hata || durum == BtDurum.kapali) {
      renk = const Color(0xFFEF5350);
      ikon = Icons.bluetooth_disabled_rounded;
      etiket = 'BT ✗';
    } else if (durum == BtDurum.taraniyor || durum == BtDurum.baglaniyor) {
      renk = OdakColors.warning;
      ikon = Icons.bluetooth_searching_rounded;
      etiket = 'Arıyor...';
    } else {
      renk = Colors.white54;
      ikon = Icons.bluetooth_rounded;
      etiket = 'Bağlan';
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
            Text(etiket,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: renk)),
          ],
        ),
      ),
    );
  }
}

// ================================================================
// Bluetooth Kılavuz Kartı
// ================================================================
class _BluetoothKlavuz extends StatelessWidget {
  final VoidCallback onTap;
  final bool bagli;
  const _BluetoothKlavuz({required this.onTap, this.bagli = false});

  @override
  Widget build(BuildContext context) {
    final renk = bagli ? OdakColors.success : OdakColors.primary;
    final metin = bagli
        ? 'Arduino bağlı — Bluetooth üzerinden izleniyor.'
        : 'Arduino\'ya bağlanmak için dokunun.\n'
            'HC-06 modülü açık ve eşleştirilmiş olmalıdır. (PIN: 1234)';
    final ikon = bagli
        ? Icons.bluetooth_connected_rounded
        : Icons.bluetooth_searching_rounded;

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

// ================================================================
// Sistem Bilgi Kartı (Arduino durumu gösterir)
// ================================================================
class _SistemBilgiKarti extends StatelessWidget {
  final ArduinoDurum durum;
  const _SistemBilgiKarti({required this.durum});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(OdakSpacing.md),
      decoration: BoxDecoration(
        color: OdakColors.surface,
        borderRadius: BorderRadius.circular(OdakRadius.lg),
        border: Border.all(
          color: OdakColors.primary.withValues(alpha: 0.15),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: OdakColors.primary.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.developer_board_rounded,
                  size: 18, color: OdakColors.primary),
              SizedBox(width: 8),
              Text(
                'Arduino Bilgileri',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: OdakColors.textPrimary,
                ),
              ),
            ],
          ),
          const Divider(height: 20),
          _bilgiSatiri(
              'Deprem',
              durum.depremAlgilandi ? '⚠️ ALGILANDI' : '✅ Yok',
              durum.depremAlgilandi ? OdakColors.danger : OdakColors.success),
          _bilgiSatiri('Doğalgaz', durum.gazAcik ? '✅ Açık' : '🔴 Kapalı',
              durum.gazAcik ? OdakColors.success : OdakColors.danger),
          _bilgiSatiri('Elektrik', durum.elektrikAcik ? '✅ Açık' : '🔴 Kesik',
              durum.elektrikAcik ? OdakColors.success : OdakColors.danger),
          _bilgiSatiri('Deprem Sayacı', '${durum.depremSayaci}/3',
              OdakColors.textSecondary),
          _bilgiSatiri('Eşik Değer', '${durum.esikDeger} m/s²',
              OdakColors.textSecondary),
          _bilgiSatiri('Uptime', _formatUptime(durum.uptimeSn),
              OdakColors.textSecondary),
        ],
      ),
    );
  }

  Widget _bilgiSatiri(String baslik, String deger, Color renk) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(baslik,
              style: const TextStyle(
                  fontSize: 12, color: OdakColors.textSecondary)),
          Text(deger,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: renk)),
        ],
      ),
    );
  }

  String _formatUptime(int sn) {
    final saat = sn ~/ 3600;
    final dakika = (sn % 3600) ~/ 60;
    final saniye = sn % 60;
    if (saat > 0) return '${saat}sa ${dakika}dk';
    if (dakika > 0) return '${dakika}dk ${saniye}sn';
    return '${saniye}sn';
  }
}
