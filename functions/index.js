const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();

// cihaz_durumu değişince otomatik tetiklenir
exports.depremBildirimi = functions.database
  .ref("/cihaz_durumu")
  .onUpdate(async (change) => {
    const yeniDeger = change.after.val();
    if (yeniDeger !== "tehlike") return null;

    const mesaj = {
      notification: {
        title: "⚠️ DEPREM ALGILANDI",
        body: "Gaz ve elektrik kesildi. Güvende misiniz?",
      },
      topic: "deprem_alarmi",  // Tüm abonelere gönder
    };

    return admin.messaging().send(mesaj);
  });