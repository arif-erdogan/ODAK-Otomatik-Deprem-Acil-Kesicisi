// ============================================================
// functions/index.js
// Deprem Güvenlik Sistemi — Firebase Cloud Functions
//
// Kurulum:
//   npm install -g firebase-tools
//   firebase login
//   firebase init functions   (projeyi seç, JavaScript)
//   bu dosyayı functions/index.js olarak kaydet
//   firebase deploy --only functions
// ============================================================

const functions = require("firebase-functions");
const admin     = require("firebase-admin");

admin.initializeApp();

// ============================================================
// TRIGGER 1: cihaz_durumu "tehlike" olduğunda push bildirim
// ============================================================
exports.depremBildirimi = functions
  .region("europe-west1")          // Türkiye'ye en yakın bölge
  .database.ref("/cihaz_durumu")
  .onUpdate(async (change, context) => {
    const eskiDeger  = change.before.val();
    const yeniDeger  = change.after.val();

    // Sadece "guvenli" → "tehlike" geçişinde tetikle
    // (Tekrarlayan "tehlike" yazımında bildirim gönderme)
    if (eskiDeger === yeniDeger) return null;
    if (yeniDeger !== "tehlike")  return null;

    console.log(`Deprem tetiklendi! Eski: ${eskiDeger} → Yeni: ${yeniDeger}`);

    const mesaj = {
      notification: {
        title: "⚠️ DEPREM ALGILANDI",
        body:  "Gaz ve elektrik kesildi. Güvende misiniz? Uygulamayı açın.",
      },
      android: {
        priority:     "high",
        notification: {
          channelId:   "deprem_kanal",
          priority:    "max",
          sound:       "default",
          visibility:  "public",
          // Ekran kilitliyken de göster:
          defaultVibrateTimings: true,
        },
      },
      apns: {
        payload: {
          aps: {
            sound:             "default",
            "content-available": 1,
            badge:             1,
          },
        },
        headers: {
          "apns-priority": "10",
        },
      },
      topic: "deprem_alarmi",      // Tüm abonelere gönder
    };

    try {
      const yanit = await admin.messaging().send(mesaj);
      console.log("FCM başarılı:", yanit);
      return yanit;
    } catch (hata) {
      console.error("FCM hatası:", hata);
      throw hata;
    }
  });

// ============================================================
// TRIGGER 2: Sistem aktif edildiğinde bilgilendirme bildirimi
// ============================================================
exports.sistemAktifBildirimi = functions
  .region("europe-west1")
  .database.ref("/cihaz_durumu")
  .onUpdate(async (change) => {
    const eskiDeger = change.before.val();
    const yeniDeger = change.after.val();

    // Sadece "tehlike" → "guvenli" geçişinde tetikle
    if (eskiDeger !== "tehlike" || yeniDeger !== "guvenli") return null;

    const mesaj = {
      notification: {
        title: "✅ Sistem Aktif Edildi",
        body:  "Gaz ve elektrik açıldı. Sistem normal çalışmaya devam ediyor.",
      },
      android: {
        priority:     "normal",
        notification: {
          channelId: "deprem_kanal",
          sound:     "default",
        },
      },
      topic: "deprem_alarmi",
    };

    try {
      const yanit = await admin.messaging().send(mesaj);
      console.log("Aktif bildirim gönderildi:", yanit);
      return yanit;
    } catch (hata) {
      console.error("Aktif bildirim hatası:", hata);
      throw hata;
    }
  });

// ============================================================
// TRIGGER 3: ESP32'nin sistemi_ac'ı "beklemede"ye aldığını
//            doğrulayarak loglama (isteğe bağlı)
// ============================================================
exports.komutTamamlandi = functions
  .region("europe-west1")
  .database.ref("/sistemi_ac")
  .onUpdate((change) => {
    const yeni = change.after.val();
    if (yeni === "beklemede") {
      console.log("ESP32 komutu aldı ve tamamladı.");
    }
    return null;
  });