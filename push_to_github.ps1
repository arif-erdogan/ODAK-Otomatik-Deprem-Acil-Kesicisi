#!/usr/bin/env pwsh
# ODAK v1.1 — GitHub Push Script
# Çalıştır: Sağ tık → "PowerShell ile çalıştır"
# veya: powershell -ExecutionPolicy Bypass -File push_to_github.ps1

Set-Location "c:\ODAK"

Write-Host "`n=== ODAK v1.1 GitHub Push ===" -ForegroundColor Cyan
Write-Host "Repository: https://github.com/arif-erdogan/ODAK-Otomatik-Deprem-Acil-Kesicisi`n" -ForegroundColor Gray

# 1. Remote kontrol ve ayarla
Write-Host "[1/5] Remote kontrol..." -ForegroundColor Yellow
$remotes = git remote
if ($remotes -notcontains "origin") {
    Write-Host "  Origin ekleniyor..." -ForegroundColor Gray
    git remote add origin https://github.com/arif-erdogan/ODAK-Otomatik-Deprem-Acil-Kesicisi.git
} else {
    git remote set-url origin https://github.com/arif-erdogan/ODAK-Otomatik-Deprem-Acil-Kesicisi.git
}
git remote -v

# 2. Tüm değişiklikleri ekle
Write-Host "`n[2/5] Dosyalar ekleniyor..." -ForegroundColor Yellow
git add -A
Write-Host "  Değişen dosyalar:" -ForegroundColor Gray
git status --short

# 3. Commit
Write-Host "`n[3/5] Commit yapiliyor..." -ForegroundColor Yellow
git commit -m "v1.1: Baglanti sorunlari duzeltildi + Firebase ayarlari eklendi

ESP32 Firmware (odak_esp32.ino):
- gaz_acik / elektrik_acik durum alanlari /api/status'a eklendi
- /api/ping endpoint eklendi (canlilık testi)
- LED alarm mantigi duzeltildi (yonlu reset — gaz/elektrik bagimsiz)
- SoftAP IP atama gecikmesi: delay(500) eklendi
- SSID: ODAK_Sistem / Sifre: odak1234

Flutter (wifi_api_service.dart):
- ipGirildi mantik hatasi duzeltildi
- SoftAP otomatik baglanti: softApBaglantisiKur()
- EspDurum modeli: gaz_acik + elektrik_acik alanlari eklendi
- Polling cift baslatma korumasi eklendi

Flutter (main.dart):
- firebase_options.dart import edildi
- Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)

Android Gradle (Firebase plugin):
- settings.gradle.kts: com.google.gms.google-services v4.4.2 eklendi
- app/build.gradle.kts: google-services plugin uygulanidi

Yeni dosyalar:
- lib/firebase_options.dart — Firebase konfigurasyonu (key girilecek)
- android/app/google-services.json — Firebase JSON sablonu
- odak_api_contract.md — v1.1 API kontrati
- esp32_firmware/KURULUM.md — Guncel kurulum kilavuzu
- push_to_github.ps1 — Bu script

.gitignore:
- google-services.json, firebase_options.dart, secrets.h eklendi"

# 4. Push
Write-Host "`n[4/5] GitHub push..." -ForegroundColor Yellow
$branch = git branch --show-current
if (-not $branch) { $branch = "master" }
Write-Host "  Branch: $branch" -ForegroundColor Gray

git push origin $branch

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n[5/5] PUSH BASARILI! ✅" -ForegroundColor Green
    Write-Host "`nhttps://github.com/arif-erdogan/ODAK-Otomatik-Deprem-Acil-Kesicisi" -ForegroundColor Cyan
    Write-Host "`n!!! Unutmayın: firebase_options.dart ve google-services.json dosyalarına" -ForegroundColor Yellow
    Write-Host "    Firebase Console'dan aldığınız key'leri yapıştırın!" -ForegroundColor Yellow
} else {
    Write-Host "`n[5/5] Push basarisiz ❌" -ForegroundColor Red
    Write-Host "Deneyebilirsiniz: git push --set-upstream origin $branch" -ForegroundColor Yellow
    Write-Host "veya: git push -u origin master" -ForegroundColor Yellow
}

Write-Host "`nDevam etmek icin bir tuşa basin..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
