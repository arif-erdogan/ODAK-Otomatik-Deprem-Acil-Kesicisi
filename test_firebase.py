import firebase_admin
from firebase_admin import credentials, db

# ============================================================
# test_firebase.py
# Firebase Python Admin SDK test betiği
# ============================================================
# Kullanmadan önce:
# pip install firebase-admin
# ============================================================

# 1. Service Account JSON dosyasını gösterin
cred = credentials.Certificate("serviceAccountKey.json")

# 2. Firebase uygulamasını başlatın
# databaseURL kısmına kendi Realtime Database URL'nizi yazın!
firebase_admin.initialize_app(cred, {
    'databaseURL': 'https://PROJE_ID_BURAYA-default-rtdb.firebaseio.com'
})

# Örnek Kullanım:
def cihaz_durumu_oku():
    ref = db.reference('/cihaz_durumu')
    print("Mevcut cihaz durumu:", ref.get())

if __name__ == '__main__':
    cihaz_durumu_oku()
