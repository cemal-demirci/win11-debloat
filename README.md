# Windows 11 Debloat · Cemal.cloud

[![Sürüm](https://img.shields.io/github/v/release/cemal-demirci/win11-debloat?label=s%C3%BCr%C3%BCm&color=e3b341)](https://github.com/cemal-demirci/win11-debloat/releases)
[![Lisans: MIT](https://img.shields.io/badge/lisans-MIT-blue)](LICENSE)
[![Denetim](https://github.com/cemal-demirci/win11-debloat/actions/workflows/ci.yml/badge.svg)](https://github.com/cemal-demirci/win11-debloat/actions)
![Windows 11](https://img.shields.io/badge/Windows-11-0078D4)

**Windows 11'i reklam panosu olmaktan çıkarın. Tek tıkla, istediğiniz an geri alınabilir şekilde.**

Sıfır kurulmuş bir Windows 11 açılır açılmaz Başlat menüsünde kurmadığınız uygulamalar, görev çubuğunda Copilot,
kilit ekranında "öneriler", arka planda da Microsoft'a giden telemetri ile gelir. Bir kısmı Ayarlar'da hiç yoktur,
bir kısmı ilk büyük güncellemede geri açılır.

Temizlemek kolaydır; zor olan geri dönmektir. Bu yüzden Win11 Debloat **yaptığı her değişikliği kaydeder**:

- başlamadan önce bir **sistem geri yükleme noktası** oluşturur,
- değiştirdiği her registry değerinin **eski halini** `undo.json`'a yazar,
- beğenmezseniz **Geri al** butonu her şeyi eski haline döndürür.

116 KB'lık tek bir uygulamadır, kurulum gerekmez. Arka planda bu repodaki PowerShell scriptlerini çalıştırır ve ne
yaptığını canlı olarak gösterir.

## İndirme ve kullanım

[**Releases**](https://github.com/cemal-demirci/win11-debloat/releases/latest) sayfasından `Win11-Debloat.exe`'yi indirin
ve çalıştırın. Yönetici izni ister.

1. Kullandıklarınızın (Edge, Xbox, Spotify...) işaretini kaldırın.
2. **Önizle** ile nelerin değişeceğine bakın. Bu adımda hiçbir şey değişmez.
3. **Uygula**'ya basın, bitince bilgisayarı yeniden başlatın.
4. Beğenmezseniz **Geri al**.

> Uygulama imzasız olduğu için Windows "Bilgisayarınız korundu" uyarısı gösterebilir: **Ek bilgi → Yine de çalıştır**.
> İndirdiğiniz dosyayı Releases sayfasındaki `SHA256SUMS.txt` ile doğrulayabilirsiniz.

Uygulama yerine scriptleri doğrudan kullanmak isterseniz, yönetici PowerShell'de:

```powershell
irm https://raw.githubusercontent.com/cemal-demirci/win11-debloat/main/Win11-Debloat.ps1 -OutFile Win11-Debloat.ps1
irm https://raw.githubusercontent.com/cemal-demirci/win11-debloat/main/Win11-Restore.ps1 -OutFile Win11-Restore.ps1

powershell -ExecutionPolicy Bypass -File .\Win11-Debloat.ps1 -DryRun   # önizle
powershell -ExecutionPolicy Bypass -File .\Win11-Debloat.ps1           # uygula
powershell -ExecutionPolicy Bypass -File .\Win11-Restore.ps1           # geri al
```

## Elle mi, Win11 Debloat ile mi?

| | Ayarlar'dan elle | Win11 Debloat |
|---|---|---|
| Copilot ve Recall | Kısmen | ✅ Politika ile kapatılır |
| Başlat önerileri, kilit ekranı reklamları, sessiz uygulama kurulumları | Tek tek, bir kısmı yok | ✅ |
| Başlat aramasında Bing | Ayarlar'da yok | ✅ |
| Ön yüklü uygulamalar | Tek tek, sadece sizin hesabınızdan | ✅ Tüm kullanıcılardan ve yeni hesaplardan |
| Telemetri | "Gerekli" seviyesine kadar | ✅ Politika ile en düşük seviye |
| Güncellemeden sonra | Baştan | Tekrar çalıştırın, sadece değişenler uygulanır |
| Geri dönüş | Ne yaptığınızı hatırlamanız gerekir | ✅ Tek tık |

## Ne değişir?

| | |
|---|---|
| **Kaldırılır** | Copilot, Microsoft 365 hub, Bing Haberler ve Hava Durumu, Get Started, Feedback Hub, Solitaire, To Do, Haritalar, Mail ve Takvim, Phone Link, Cortana, kişisel Teams, Clipchamp, Widgets, Xbox uygulamaları, yeni Outlook, OneDrive, Edge (Microsoft izin veriyorsa), Spotify ve Netflix gibi üretici ve tanıtım uygulamaları |
| **Kapatılır** | Copilot ve Recall, Paint ve Not Defteri'ndeki yapay zekâ özellikleri, telemetri ve reklam kimliği, Başlat önerileri ve reklamları, Başlat aramasında Bing, kilit ekranı reklamları, sessiz uygulama kurulumları, Game DVR |
| **Ayarlanır** | Dosya uzantıları ve gizli dosyalar görünür, klasik sağ tık menüsü geri gelir, Explorer "Bu Bilgisayar" ile açılır |
| **Dokunulmaz** | Microsoft Store, winget, Terminal, Fotoğraflar, Hesap Makinesi, Not Defteri, Paint, Ekran Alıntısı Aracı, iş Teams'i, klasik Outlook, WebView2, Windows Search, Get Help, Intune senkronizasyonu |

> **Dikkat:** Spotify, Netflix gibi üçüncü parti uygulamalar **tüm kullanıcılardan, verileriyle birlikte** kaldırılır.
> Kullanıyorsanız uygulamada işaretini kaldırın (PowerShell'de `-KeepThirdParty`).

Bazı durumlarda ilgili adım bilerek atlanır:

- OneDrive'da oturum açıksa ya da klasörleriniz OneDrive'a yedekleniyorsa **OneDrive kaldırılmaz**; bulutta duran
  dosyalarınıza erişim kaybolmaz.
- Başka bir tarayıcı kurulu değilse **Edge kaldırılmaz**.
- Geri yükleme noktası oluşturulamazsa hiçbir şey değişmez; uygulama devam edip etmeyeceğinizi sorar.

## Ne çalıştırır, nereye dokunur?

- **Çalıştırdığı:** yalnızca bu repodaki `Win11-Debloat.ps1` ve `Win11-Restore.ps1`. Uygulamanın içindeki kopyaları
  repodakilerle bayt bayt aynıdır (CI her derlemede kontrol eder).
- **Yazdığı:** Windows ayarları (registry, servisler, zamanlanmış görevler) ve yedekler için
  `%ProgramData%\CemalCloud\Win11Debloat\`.
- **Ağ:** debloat hiçbir yere bağlanmaz. Yalnızca **Geri al**, kaldırılmış OneDrive ve Edge'i yeniden kurmak için winget kullanır.
- **Kimin ayarları:** bilgisayar genelindeki ayarlar herkese, kişisel ayarlar uygulamayı çalıştıran hesaba uygulanır.

## Test ettik

Her commit'te GitHub Actions üç ayrı testi **gerçek bir Windows'ta** çalıştırır (Windows Server 2025, Windows 11 24H2
ile aynı çekirdek):

| Test | Sonuç (son çalıştırma) |
|---|---|
| Önizle → Uygula → tekrar Uygula → Geri al | 36 kontrol geçti. Uygulama 93 registry değerini değiştirdi, Geri al hepsini eski haline döndürdü. Önizleme hiçbir şeye dokunmadı. |
| Uygulama, penceresiz | Gömülü scriptler repodakilerle aynı. 64-bit PowerShell kullanılıyor. Önizle, Uygula ve Geri al uygulama üzerinden sorunsuz. |
| Uygulama, penceresiyle | Pencere açıldı, Edge'in işareti tıklamayla kaldırıldı, **Önizle**'ye basıldı. Script `-KeepEdge` ile çalıştı, sonuç pencerede göründü. |

Dürüst not: sunucu sürümünde Store uygulamaları, Edge kaldırma ve OneDrive olmadığı için bu kısımlar testin dışında
kalıyor. İlk kullanımda bir sanal makinede **Önizle** ile başlayın.

## Seçenekler

| Uygulamada | PowerShell'de | Ne yapar |
|---|---|---|
| Önizle | `-DryRun` | Hiçbir şeyi değiştirmez, yapılacakları listeler |
| Edge'i kaldır (işaretsiz) | `-KeepEdge` | Edge kalır, ayarları yine sadeleşir |
| OneDrive'ı kaldır (işaretsiz) | `-KeepOneDrive` | OneDrive kalır |
| Xbox uygulamalarını kaldır (işaretsiz) | `-KeepXbox` | Xbox uygulamaları, servisleri ve Game Bar kalır |
| Üçüncü parti uygulamaları kaldır (işaretsiz) | `-KeepThirdParty` | Spotify, Netflix, Disney+ gibi uygulamalar kalır |
| Yeni Outlook'u kaldır (işaretsiz) | `-KeepOutlookNew` | Yeni Outlook kalır |
| Arayüz ayarları (işaretsiz) | `-SkipUiTweaks` | Dosya uzantısı, sağ tık menüsü gibi ayarlara dokunmaz |
| | `-SkipRestorePoint` | Geri yükleme noktası oluşturulamasa da devam eder |
| | `-Force` | Güvenlik kontrollerini atlar, dikkatli kullanın |

## Bilmeniz gerekenler

- **Telemetri:** en düşük seviye yalnızca Enterprise ve Education sürümlerinde tam geçerlidir. Pro ve Home'da Windows
  bunu "Gerekli" seviyesinde tutar.
- **Edge:** Microsoft kaldırmaya yalnızca bazı bölgelerde (AB) izin verir. Diğer bölgelerde Edge kalır ama arka plan
  özellikleri kapatılır.
- **Şirket bilgisayarları:** Intune ya da Group Policy ile yönetilen bir cihazda BT ekibinize sormadan çalıştırmayın.

## Lisans

[MIT](LICENSE). Kendi sorumluluğunuzda kullanın.

---

## English

**Windows 11 Debloat** removes ads, Copilot, Recall, preinstalled apps and telemetry in one click, and records every
change so it can be undone in one click. It is a 116 KB app (no install) that runs the PowerShell scripts in this
repository and shows their output live.

- **Download:** `Win11-Debloat.exe` from [Releases](https://github.com/cemal-demirci/win11-debloat/releases/latest).
  Untick what you use, press **Önizle** (preview), then **Uygula** (apply) and restart. **Geri al** (restore) undoes everything.
- **Safety:** restore point, registry export and an undo manifest before any change. OneDrive is kept when it is signed
  in, Edge is kept when no other browser is installed. Store, winget, Terminal, work Teams, classic Outlook, Windows
  Search, Get Help and Intune sync are never touched.
- **Scripts:** `Win11-Debloat.ps1 [-DryRun] [-KeepEdge] [-KeepOneDrive] [-KeepXbox] [-KeepThirdParty]`, `Win11-Restore.ps1`.
- **Tested:** every commit runs a real preview / apply / repeat / restore round trip, the app headless and the app window
  (UI clicks) on Windows Server 2025. Desktop-only parts (Store apps, Edge removal, OneDrive) are not covered there;
  start with a preview in a VM.
- **License:** MIT.
