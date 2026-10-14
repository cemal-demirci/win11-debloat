<div align="center">

```
  ____                     _       _                 _
 / ___|___ _ __ ___   __ _| |  ___| | ___  _   _  __| |
| |   / _ \ '_ ` _ \ / _` | | / __| |/ _ \| | | |/ _` |
| |__|  __/ | | | | | (_| | || (__| | (_) | |_| | (_| |
 \____\___|_| |_| |_|\__,_|_(_)___|_|\___/ \__,_|\__,_|
```

# Windows 11 Debloat

**Copilot, Recall, reklam ve telemetriyi kaldıran, her değişikliği geri alınabilir şekilde kaydeden Windows 11 temizliği.**

[![ci](https://github.com/cemal-demirci/win11-debloat/actions/workflows/ci.yml/badge.svg)](https://github.com/cemal-demirci/win11-debloat/actions/workflows/ci.yml)
![license](https://img.shields.io/badge/license-MIT-blue)

[cemal.cloud](https://cemal.cloud)

</div>

---

Windows 11 için agresif ama geri alınabilir temizlik. Hedef: iş istasyonunda reklamsız, telemetrisi kısılmış, Copilot'suz bir sistem.

> **Test:** Her commit'te GitHub Actions'ta Windows Server 2025 (Windows 11 24H2 ile aynı taban) üzerinde gerçekten çalıştırılır: `-DryRun` hiçbir registry değerini değiştirmez, gerçek çalıştırma ayarları uygular, ikinci çalıştırma güvenlidir ve `Win11-Restore.ps1` her değeri eski haline döndürür. Sunucu imajında olmayan masaüstü kısımları (Store uygulamaları, Edge kaldırma, OneDrive) bu testte çalışmaz. Masaüstü Windows 11'de ilk kullanımda bir VM'de `-DryRun` ile deneyin.

## İndirme

Yönetici olarak açılmış PowerShell'de:

```powershell
irm https://raw.githubusercontent.com/cemal-demirci/win11-debloat/main/Win11-Debloat.ps1 -OutFile Win11-Debloat.ps1
irm https://raw.githubusercontent.com/cemal-demirci/win11-debloat/main/Win11-Restore.ps1 -OutFile Win11-Restore.ps1
```

## Kullanım

Yönetici olarak açılmış PowerShell'de:

```powershell
powershell -ExecutionPolicy Bypass -File .\Win11-Debloat.ps1 -DryRun   # sadece göster
powershell -ExecutionPolicy Bypass -File .\Win11-Debloat.ps1           # uygula
powershell -ExecutionPolicy Bypass -File .\Win11-Restore.ps1           # geri al
```

HKCU ayarları script'i çalıştıran kullanıcıya uygulanır. Temizlemek istediğiniz hesapla (yönetici olmalı) çalıştırın.

## Parametreler

| Parametre | Etki |
|---|---|
| `-DryRun` | Hiçbir şeyi değiştirmez, yapılacakları listeler |
| `-KeepEdge` | Edge kaldırılmaz (Edge politikaları yine uygulanır) |
| `-KeepOneDrive` | OneDrive kaldırılmaz |
| `-KeepXbox` | Xbox uygulamaları, servisleri ve Game Bar kalır |
| `-KeepOutlookNew` | "Yeni Outlook" uygulaması kalır (klasik Outlook zaten etkilenmez) |
| `-KeepThirdParty` | Spotify, Netflix, Disney+, Prime Video, LinkedIn, Messenger, Instagram, TikTok, X, Plex, McAfee ve oyunlar kalır |
| `-SkipUiTweaks` | Dosya uzantıları, klasik sağ tık menüsü gibi arayüz ayarları atlanır |
| `-SkipRestorePoint` | Restore noktası oluşturulamazsa da devam eder |
| `-Force` | Güvenlik kontrollerini atlar (aşağıya bakın) |

## Ne yapar

**Kaldırılan uygulamalar (tüm kullanıcılar ve yeni kullanıcılar için):**
Copilot, Microsoft 365 (Office) hub, Bing News / Weather / Search, Get Started, Feedback Hub, Solitaire, People, To Do, Power Automate, Maps, Film & TV, Alarms, Sound Recorder, Journal, Mixed Reality, 3D Viewer, Paint 3D, Skype, OneNote (UWP), Mail & Calendar, Phone Link, Dev Home, Cortana, Teams (ücretsiz/kişisel), Family, Clipchamp, Widgets, Xbox uygulamaları, yeni Outlook, OEM ve tanıtım uygulamaları.

> ⚠️ Üçüncü parti uygulamalar (Spotify, Netflix vb.) varsayılan olarak **tüm kullanıcılardan, verileriyle birlikte** kaldırılır. Kullanıyorsanız `-KeepThirdParty` ekleyin.

**Kapatılanlar:**
- Copilot, Recall, Click to Do, Paint ve Notepad'deki üretken AI özellikleri
- Telemetri (politika ile en düşük seviye), reklam kimliği, kişiye özel deneyimler, etkinlik geçmişi, hata raporlama
- `DiagTrack`, `MapsBroker`, `RetailDemo`, `WMPNetworkSvc` servisleri ve telemetri zamanlanmış görevleri
- Başlat menüsü önerileri, kilit ekranı reklamları, sessiz uygulama kurulumları, Başlat aramasında Bing
- Widgets / Haberler, Game DVR (Xbox modunda)
- Edge: başlangıç hızlandırma, arka plan modu, kenar çubuğu, alışveriş, öneriler. Ardından Edge kaldırılmaya çalışılır.
- OneDrive kaldırılır, yeniden kurulumu politika ile engellenir

**Arayüz:** dosya uzantıları ve gizli dosyalar görünür, Explorer "Bu Bilgisayar" ile açılır, klasik sağ tık menüsü, görev çubuğunda sadece arama ikonu.

## Bilerek dokunulmayanlar

Microsoft Store, winget (App Installer), Terminal, Fotoğraflar, Hesap Makinesi, Not Defteri, Paint, Ekran Alıntısı Aracı, Kamera, Media Player, **Get Help** (Ayarlar'daki sorun gidericiler bunun üzerinden çalışır), iş Teams'i (`MSTeams`), klasik Outlook, WebView2, Windows Search servisi (Outlook araması için), yazdırma, WSL, Hyper-V ve **`dmwappushservice`** (Intune / MDM senkronizasyonu buna bağlı).

## Güvenlik kontrolleri

Script şu durumlarda ilgili adımı atlar (`-Force` ile aşılabilir):

- Windows 11 değilse (build 22000 altı) hiç çalışmaz.
- OneDrive'da oturum açıksa veya klasörler OneDrive'a yedekleniyorsa OneDrive kaldırılmaz. Çevrimiçi dosyalar ve bekleyen yüklemeler kaybolmasın diye.
- Başka bir tarayıcı kurulu değilse Edge kaldırılmaz.
- Restore noktası oluşturulamazsa script durur (`-SkipRestorePoint` ile devam eder).

## Yedek ve geri alma

Her çalıştırma `%ProgramData%\CemalCloud\Win11Debloat\<tarih-saat>\` klasörüne yazar:

| Dosya | İçerik |
|---|---|
| `undo.json` | Her registry değerinin eski hali, kapatılan görevler, kaldırılan bileşenler |
| `*.reg` | Etkilenen registry dallarının dışa aktarımı |
| `apps-before.csv` | Kaldırmadan önceki uygulama listesi |
| `debloat.log` | Çalıştırma kaydı |

`Win11-Restore.ps1` geri alınmamış tüm çalıştırmaları en yeniden eskiye doğru geri alır. Registry değerlerini eski haline döndürür (script'in oluşturduğu boş anahtarları da siler), görevleri ve özellikleri tekrar açar, OneDrive ve Edge'i winget ile yeniden kurar. Kaldırılan Store uygulamalarını listeler, bunları Store'dan tekrar kurabilirsiniz. Tamamen geri dönmek için "Cemal.cloud Win11-Debloat" restore noktası da kullanılabilir.

## Bilinen sınırlar

- **Telemetri seviyesi:** `AllowTelemetry=0` sadece Enterprise / Education sürümlerinde tam etkilidir. Pro ve Home bunu "Required" seviyesine çeker.
- **Edge kaldırma:** Microsoft bunu sadece bazı bölgelerde (AB / AEA) izin veriyor. Başka bölgelerde kaldırıcı reddeder, Edge kalır ama politikalarla susturulmuş olur.
- **Widgets düğmesi:** 24H2 ve sonrasında UCPD koruması `TaskbarDa` değerinin yazılmasını engelleyebilir. Widgets politika ile zaten kapatıldığı için sonuç değişmez, özette "Failed" olarak görünebilir.
- **Büyük güncellemeler** (feature update) bazı uygulamaları geri getirebilir. Script'i tekrar çalıştırmak güvenlidir. Sadece değişen kısımlar uygulanır ve ayrı bir geri alma kaydı tutulur.

## Prensipler

1. **Önce göster.** Dry-run modu ile neyin değişeceğini önce görün.
2. **Yedek al.** Değişiklikten önce yedek ve geri alma dosyası yazılır.
3. **Geri alınabilir.** Her değişikliğin geri dönüş yolu var.
4. **Kritik olana dokunma.** Sistemi ayakta tutan parçalar korunur.
5. **Sessiz hata yok.** Kontrol yapılamıyorsa script güvenli tarafta kalır ve durur.

## Sorumluluk

Bu scriptler sistem ayarlarını değiştirir ve yazılım kaldırır. Kendi sorumluluğunuzda kullanın, önce test ortamında deneyin. Kurumsal yönetilen cihazlarda BT ekibinizle konuşmadan çalıştırmayın.

## Diğer Cemal.cloud araçları

| Repo | |
|---|---|
| [`ubuntu-server-debloat`](https://github.com/cemal-demirci/ubuntu-server-debloat) | snap, telemetri ve gereksiz servisleri kaldırır. Kritik bir paketi etkileyecekse hiçbir şey yapmadan durur. |
| [`k8s-debloat`](https://github.com/cemal-demirci/k8s-debloat) | Traefik ve ServiceLB olmadan sade k3s kurulumu ve her cluster için varsayılanı dry-run olan temizlik scripti. |
| [`ffmpeg-broadcast`](https://github.com/cemal-demirci/ffmpeg-broadcast) | Yayıncılık için sade FFmpeg build'i ve 19 hazır yayın preseti: XDCAM, AVC-Intra, IMX, ProRes, DNxHD, DVB, HLS, SRT. |

## Lisans

[MIT](LICENSE)

---

<details>
<summary><b>English</b></summary>

Aggressive but reversible Windows 11 debloat: Copilot, Recall, Xbox, Widgets, OneDrive, Edge (where Microsoft allows it), ads, suggestions and telemetry. Before changing anything it creates a restore point, exports the affected registry hives and records every change in `undo.json`; `Win11-Restore.ps1` rolls all pending runs back, newest first. Store, winget, Terminal, WebView2, work Teams, classic Outlook, Windows Search, Get Help and the Intune sync service (`dmwappushservice`) are kept on purpose.

```powershell
powershell -ExecutionPolicy Bypass -File .\Win11-Debloat.ps1 -DryRun
powershell -ExecutionPolicy Bypass -File .\Win11-Debloat.ps1 [-KeepEdge] [-KeepOneDrive] [-KeepXbox] [-KeepThirdParty]
powershell -ExecutionPolicy Bypass -File .\Win11-Restore.ps1
```

CI runs a real dry run, debloat, repeat run and restore round trip on Windows Server 2025 for every commit. Desktop-only parts (Store apps, Edge removal, OneDrive) are not covered there; try `-DryRun` in a VM first.

</details>
