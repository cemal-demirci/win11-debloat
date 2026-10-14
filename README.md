# Windows 11 Debloat · Cemal.cloud

Windows 11'deki reklamları, Copilot'u ve telemetriyi tek komutla kapatan PowerShell scripti. Yaptığı her değişikliği kaydeder, beğenmezseniz tek komutla geri alırsınız.

[![ci](https://github.com/cemal-demirci/win11-debloat/actions/workflows/ci.yml/badge.svg)](https://github.com/cemal-demirci/win11-debloat/actions/workflows/ci.yml)
![license](https://img.shields.io/badge/license-MIT-blue)

## Neden?

Sıfır kurulmuş bir Windows 11 bile Copilot, Recall, Başlat menüsünde reklamlar, kendiliğinden kurulan uygulamalar, Xbox servisleri ve Microsoft'a giden telemetri ile gelir. Bunların bir kısmı Ayarlar'da hiç yoktur, bir kısmı da büyük güncellemelerden sonra geri açılır.

Bu script hepsini tek seferde kapatır. Diğer debloat araçlarından farkı, neyi değiştirdiğini kaydetmesidir. Pişman olursanız her şey geri alınabilir.

## Hızlı başlangıç

PowerShell'i **yönetici olarak** açın:

```powershell
irm https://raw.githubusercontent.com/cemal-demirci/win11-debloat/main/Win11-Debloat.ps1 -OutFile Win11-Debloat.ps1
irm https://raw.githubusercontent.com/cemal-demirci/win11-debloat/main/Win11-Restore.ps1 -OutFile Win11-Restore.ps1

# 1. Ne yapacağını görün (hiçbir şey değişmez)
powershell -ExecutionPolicy Bypass -File .\Win11-Debloat.ps1 -DryRun

# 2. Uygulayın, ardından bilgisayarı yeniden başlatın
powershell -ExecutionPolicy Bypass -File .\Win11-Debloat.ps1
```

Ayarlar, script'i çalıştıran kullanıcıya uygulanır. Temizlemek istediğiniz hesapla (yönetici olmalı) çalıştırın.

## Ne değişir?

| | |
|---|---|
| **Kaldırılır** | Copilot, Microsoft 365 hub, Bing Haberler ve Hava Durumu, Get Started, Feedback Hub, Solitaire, To Do, Haritalar, Mail ve Takvim, Phone Link, Cortana, kişisel Teams, Clipchamp, Widgets, Xbox uygulamaları, yeni Outlook, OneDrive, Edge (Microsoft izin veriyorsa), Spotify ve Netflix gibi üretici ve tanıtım uygulamaları |
| **Kapatılır** | Copilot ve Recall, Paint ve Not Defteri'ndeki yapay zeka özellikleri, telemetri ve reklam kimliği, Başlat menüsü önerileri ve reklamları, Başlat aramasında Bing, kilit ekranı reklamları, sessiz uygulama kurulumları, Game DVR |
| **Ayarlanır** | Dosya uzantıları ve gizli dosyalar görünür, klasik sağ tık menüsü geri gelir, Explorer "Bu Bilgisayar" ile açılır |
| **Dokunulmaz** | Microsoft Store, winget, Terminal, Fotoğraflar, Hesap Makinesi, Not Defteri, Paint, Ekran Alıntısı Aracı, iş Teams'i, klasik Outlook, WebView2, Windows Search, Get Help, Intune senkronizasyonu |

> **Dikkat:** Spotify, Netflix gibi üçüncü parti uygulamalar **tüm kullanıcılardan, verileriyle birlikte** kaldırılır. Kullanıyorsanız `-KeepThirdParty` ekleyin.

## Nasıl güvenli kalıyor?

Script hiçbir şeye dokunmadan önce:

1. Bir **System Restore noktası** oluşturur. Oluşturamazsa durur.
2. Etkilenen registry bölümlerini `.reg` dosyası olarak yedekler.
3. Kurulu uygulamaların listesini kaydeder.
4. Yaptığı her değişikliği `undo.json` dosyasına yazar.

Riskli durumlarda ilgili adımı atlar:

- OneDrive'da oturum açıksa veya klasörleriniz OneDrive'a yedekleniyorsa OneDrive kaldırılmaz. Bulutta duran dosyalarınıza erişim kaybolmasın diye.
- Başka bir tarayıcı kurulu değilse Edge kaldırılmaz.
- Windows 11 değilse hiç çalışmaz.

## Geri alma

```powershell
powershell -ExecutionPolicy Bypass -File .\Win11-Restore.ps1
```

Registry değerleri eski haline döner, kapatılan görevler açılır, OneDrive ve Edge winget ile yeniden kurulur. Kaldırılan Store uygulamaları listelenir, onları Store'dan tekrar kurabilirsiniz. Script'i birden fazla kez çalıştırdıysanız hepsi en yeniden eskiye doğru geri alınır.

Tamamen geri dönmek için "Cemal.cloud Win11-Debloat" restore noktası da kullanılabilir. Yedekler `%ProgramData%\CemalCloud\Win11Debloat\` altında durur.

## Seçenekler

| Parametre | Ne yapar |
|---|---|
| `-DryRun` | Hiçbir şeyi değiştirmez, yapılacakları listeler |
| `-KeepEdge` | Edge kaldırılmaz (ayarları yine sadeleşir) |
| `-KeepOneDrive` | OneDrive kaldırılmaz |
| `-KeepXbox` | Xbox uygulamaları, servisleri ve Game Bar kalır |
| `-KeepThirdParty` | Spotify, Netflix, Disney+ gibi üçüncü parti uygulamalar kalır |
| `-KeepOutlookNew` | Yeni Outlook uygulaması kalır |
| `-SkipUiTweaks` | Dosya uzantısı, sağ tık menüsü gibi arayüz ayarlarına dokunmaz |
| `-SkipRestorePoint` | Restore noktası oluşturulamasa da devam eder |
| `-Force` | Yukarıdaki güvenlik kontrollerini atlar, dikkatli kullanın |

## Bilmeniz gerekenler

- **Telemetri:** En düşük seviye sadece Enterprise ve Education sürümlerinde tam geçerlidir. Pro ve Home'da Windows bunu "Gerekli" seviyesinde tutar.
- **Edge:** Microsoft, Edge'in kaldırılmasına sadece bazı bölgelerde (AB) izin veriyor. Diğer bölgelerde Edge kalır ama arka plan özellikleri kapatılır.
- **Büyük güncellemeler** bazı uygulamaları geri getirebilir. Script'i tekrar çalıştırmak güvenlidir.
- **Şirket bilgisayarları:** Intune veya Group Policy ile yönetilen bir cihazda BT ekibinize sormadan çalıştırmayın.

## Nasıl test ediliyor?

Her değişiklikte GitHub Actions, script'i Windows Server 2025 üzerinde (Windows 11 24H2 ile aynı çekirdek) gerçekten çalıştırır ve şunları kontrol eder: `-DryRun` hiçbir şeyi değiştirmiyor, gerçek çalıştırma ayarları uyguluyor, ikinci çalıştırma sorun çıkarmıyor, restore her değeri eski haline döndürüyor.

Sunucu sürümünde olmayan masaüstü parçaları (Store uygulamaları, Edge kaldırma, OneDrive) bu testin dışında kalır. İlk kullanımda bir sanal makinede `-DryRun` ile denemenizi öneririz.

## Lisans

[MIT](LICENSE). Kendi sorumluluğunuzda kullanın.

---

<details>
<summary><b>English</b></summary>

Reversible Windows 11 debloat: Copilot, Recall, Xbox, Widgets, OneDrive, Edge (where Microsoft allows it), ads, suggestions and telemetry. Before changing anything it creates a restore point, exports the affected registry hives and records every change in `undo.json`; `Win11-Restore.ps1` rolls all pending runs back, newest first. Store, winget, Terminal, WebView2, work Teams, classic Outlook, Windows Search, Get Help and the Intune sync service are kept on purpose.

```powershell
powershell -ExecutionPolicy Bypass -File .\Win11-Debloat.ps1 -DryRun
powershell -ExecutionPolicy Bypass -File .\Win11-Debloat.ps1 [-KeepEdge] [-KeepOneDrive] [-KeepXbox] [-KeepThirdParty]
powershell -ExecutionPolicy Bypass -File .\Win11-Restore.ps1
```

CI runs a real dry run, debloat, repeat run and restore round trip on Windows Server 2025 for every commit. Desktop-only parts (Store apps, Edge removal, OneDrive) are not covered there; try `-DryRun` in a VM first.

</details>
