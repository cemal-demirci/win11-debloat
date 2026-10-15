# Windows 11 Debloat · Cemal.cloud

[![Sürüm](https://img.shields.io/github/v/release/cemal-demirci/win11-debloat?label=s%C3%BCr%C3%BCm&color=e3b341)](https://github.com/cemal-demirci/win11-debloat/releases)
[![Lisans: MIT](https://img.shields.io/badge/lisans-MIT-blue)](LICENSE)
[![Denetim](https://github.com/cemal-demirci/win11-debloat/actions/workflows/ci.yml/badge.svg)](https://github.com/cemal-demirci/win11-debloat/actions)
![Windows 11](https://img.shields.io/badge/Windows-11-0078D4)

**Windows 11'i reklam panosu olmaktan çıkarın ve hızlandırın. Tek tıkla, istediğiniz an geri alınabilir şekilde.**

Sıfır kurulmuş bir Windows 11 açılır açılmaz Başlat menüsünde kurmadığınız uygulamalar, görev çubuğunda Copilot,
kilit ekranında "öneriler", arka planda da Microsoft'a giden telemetri ile gelir. Bir kısmı Ayarlar'da hiç yoktur,
bir kısmı ilk büyük güncellemede geri açılır.

Temizlemek kolaydır; zor olan geri dönmektir. Bu yüzden Win11 Debloat **yaptığı her değişikliği kaydeder**:

- başlamadan önce bir **sistem geri yükleme noktası** oluşturur,
- değiştirdiği her registry değerinin **eski halini** `undo.json`'a yazar,
- beğenmezseniz **Geri al** butonu her şeyi eski haline döndürür.

Neyi uyguladığını da kaydettiği için, bir Windows güncellemesi sonrası **neyin geri döndüğünü** tek tek söyleyebilir
ve yalnızca onları düzeltir. İsterseniz bunu her oturum açışta kendisi yapar.

148 KB'lık tek bir uygulamadır, kurulum gerekmez. Arka planda bu repodaki PowerShell scriptlerini çalıştırır ve ne
yaptığını canlı olarak gösterir.

## İndirme ve kullanım

[**Releases**](https://github.com/cemal-demirci/win11-debloat/releases/latest) sayfasından `Win11-Debloat.exe`'yi indirin
ve çalıştırın. Yönetici izni ister.

1. Kullandıklarınızın (Edge, Xbox, Spotify...) işaretini kaldırın.
2. **Önizle** ile nelerin değişeceğine bakın. Bu adımda hiçbir şey değişmez.
3. **Uygula**'ya basın, bitince bilgisayarı yeniden başlatın.
4. Beğenmezseniz **Geri al**.
5. Bir güncellemeden sonra **Kontrol et**: Windows bir şeyi geri açtıysa listeler ve düzeltmeyi önerir.

> Uygulama imzasız olduğu için Windows "Bilgisayarınız korundu" uyarısı gösterebilir: **Ek bilgi → Yine de çalıştır**.
> İndirdiğiniz dosyayı Releases sayfasındaki `SHA256SUMS.txt` ile doğrulayabilirsiniz.

Uygulama yerine scriptleri doğrudan kullanmak isterseniz, yönetici PowerShell'de:

```powershell
irm https://raw.githubusercontent.com/cemal-demirci/win11-debloat/main/Win11-Debloat.ps1 -OutFile Win11-Debloat.ps1
irm https://raw.githubusercontent.com/cemal-demirci/win11-debloat/main/Win11-Restore.ps1 -OutFile Win11-Restore.ps1

powershell -ExecutionPolicy Bypass -File .\Win11-Debloat.ps1 -DryRun   # önizle
powershell -ExecutionPolicy Bypass -File .\Win11-Debloat.ps1           # uygula
powershell -ExecutionPolicy Bypass -File .\Win11-Debloat.ps1 -Check    # ne geri döndü?
powershell -ExecutionPolicy Bypass -File .\Win11-Debloat.ps1 -Reapply  # sadece geri dönenleri düzelt
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
| Saydamlık, animasyonlar, arka plan uygulamaları, güç planı | Ayarlar'da dağınık, bir kısmı hiç yok | ✅ Tek seçenek, hepsi geri alınabilir |
| Güncellemeden sonra | Fark etmezsiniz, baştan başlarsınız | ✅ **Kontrol et** neyin geri döndüğünü söyler, **Nöbetçi** kendisi düzeltir |
| Geri dönüş | Ne yaptığınızı hatırlamanız gerekir | ✅ Tek tık |

## Nöbetçi: güncellemeden sonra geri gelenler

Büyük Windows güncellemeleri bazı politikaları sıfırlar, kaldırdığınız uygulamaları geri kurar, kapattığınız görevleri
yeniden açar. Çoğu zaman bunu aylar sonra, Başlat menüsünde yine bir reklam gördüğünüzde fark edersiniz.

Win11 Debloat her çalıştırmada neyi yerine koyduğunu kaydeder (`state.json`). Böylece sonradan neyin geri döndüğünü
tahmin etmez, karşılaştırır:

| | Ne yapar |
|---|---|
| **Kontrol et** | Son uygulamadan beri değişen registry değerlerini, yeniden açılan zamanlanmış görevleri, geri gelen uygulamaları, yeniden kurulan Edge ve OneDrive'ı listeler. Hiçbir şeyi değiştirmez. Uygulama her açılışta bu kontrolü kendisi de yapar. |
| **Düzeltme** | **Kontrol et** bir şey bulursa sorar ve yalnızca geri dönenleri, son seferki seçeneklerinizle tekrar uygular. Her değişiklik yine kaydedilir, **Geri al** bunları da geri alır. |
| **Nöbetçi** | Her oturum açışınızdan 2 dakika sonra kontrol eder. Bir şey geri dönmüşse düzeltir ve `guard.log`'a yazar, dönmemişse hiçbir şey yapmaz. |

Nöbetçi, yönetici yetkisiyle çalışan bir zamanlanmış görevdir ("Cemal.cloud Win11 Debloat Guard"). Çalıştırdığı
scriptin kopyası `Program Files` altında durur, oraya yalnızca yöneticiler yazabilir. Seçeneğin işaretini
kaldırdığınızda ya da **Geri al**'a bastığınızda görev ve kopyası silinir.

## Performans ayarları

Güvenliği düşüren ve geri alınamayan hiçbir ayar yoktur. Hepsi registry ve güç planı üzerinden yapılır, **Geri al**
hepsini eski haline getirir.

| | Ne yapar |
|---|---|
| **Görüntü** | Saydamlık, pencere ve görev çubuğu animasyonları, solma ve gölge efektleri kapanır. Menüler beklemeden açılır. ClearType yazı yumuşatma ve küçük resimler kalır. |
| **Arka plan** | Store uygulamaları kapalıyken arka planda çalışmaz. Açılışta başlayan programlar 10 saniye bekletilmez. Bilgisayar bakım için uykudan uyandırılmaz. Windows güncellemeleri sizin bağlantınızdan başka bilgisayarlara dağıtılmaz. |
| **Sistem** | Ön plandaki uygulama işlemcide öncelik alır. Multimedya zamanlayıcısı arka plana daha az pay ayırır. NTFS her dosya okumasında "son erişim" zamanı yazmaz. İkon önbelleği büyür. Servisler daha az `svchost` sürecinde toplanır. |
| **Güç (yalnızca masaüstü)** | "Cemal.cloud Performans" güç planı (Ultimate ya da High performance kopyası) açılır, güç kısma (power throttling) kapanır. Pil bulunan bilgisayarlarda (dizüstü, tablet, UPS) güç ayarlarına dokunulmaz. |

Bilerek **dokunulmayanlar:** Defender, Windows Update, işlemci güvenlik korumaları (Spectre / Meltdown), sayfa dosyası,
SysMain ve hazırda bekletme. Bunlar ya güvenliği düşürür ya da kazancı tartışmalıdır.

Bilmeniz gerekenler:

- Store'dan kurulan bazı uygulamalar (ör. WhatsApp) kapalıyken bildirim göndermeyebilir. Masaüstü uygulamaları
  etkilenmez.
- Xbox uygulamalarını tutarsanız servisler gruplanmaz; Game Bar'ın düzgün çalışması için ayrı kalmaları gerekir.
- Ayarların çoğu yeniden başlattıktan sonra geçerli olur. **Kontrol et**, ilk çalıştırmadan önceki süreç, `svchost`,
  çalışan servis sayısını ve bellek kullanımını bugünküyle yan yana gösterir. Fark kendi bilgisayarınızda ölçülür.
- Oyunlarda FPS artışı beklemeyin. Kazanç, sistemin daha az iş yapmasından ve tepki süresinden gelir.

İstemezseniz uygulamada **Performans ayarları**'nın işaretini kaldırın (PowerShell'de `-SkipPerformance`).

### Oyuncu ayarları (isteğe bağlı)

Varsayılan olarak kapalıdır. Uygulamada **Oyuncu ayarları**'nı işaretleyin (PowerShell'de `-GamingTweaks`):

| | Ne yapar |
|---|---|
| **Fare ivmesi** | "İşaretçi hassasiyetini artır" kapanır, fare elinizle 1:1 hareket eder. |
| **Zamanlayıcı** | Bir oyun yüksek zamanlayıcı çözünürlüğü istediğinde bu tüm sisteme uygulanır (Windows 10 2004 öncesi davranış). Sürekli yüksek çözünürlük zorlanmaz, boştayken pil ve enerji harcanmaz. |
| **Erişilebilirlik kısayolları** | Oyun ortasında Shift'e 5 kez basınca ya da Shift'i basılı tutunca çıkan Yapışkan Tuşlar ve Filtre Tuşları pencereleri, NumLock'ta Geçiş Tuşları penceresi çıkmaz. Yalnızca kısayol kapanır; bu özellikleri kullanıyorsanız açık kalırlar. |
| **Oyun Modu** | Açık olduğundan emin olunur. |

Fare ayarı bir sonraki oturum açışta, zamanlayıcı ayarı yeniden başlatınca geçerli olur.

## Ne değişir?

| | |
|---|---|
| **Kaldırılır** | Copilot, Microsoft 365 hub, Bing Haberler ve Hava Durumu, Get Started, Feedback Hub, Solitaire, To Do, Haritalar, Mail ve Takvim, Phone Link, Cortana, kişisel Teams, Clipchamp, Widgets, Xbox uygulamaları, yeni Outlook, OneDrive, Edge (Microsoft izin veriyorsa), Spotify ve Netflix gibi üretici ve tanıtım uygulamaları |
| **Kapatılır** | Copilot ve Recall, Paint ve Not Defteri'ndeki yapay zekâ özellikleri, telemetri ve reklam kimliği, Başlat önerileri ve reklamları, Başlat aramasında Bing, kilit ekranı reklamları, sessiz uygulama kurulumları, Game DVR |
| **Hızlandırılır** | Saydamlık ve animasyonlar, arka plan uygulamaları, açılış gecikmesi, işlemci önceliği, servis gruplama, masaüstünde güç planı (ayrıntılar yukarıda) |
| **Ayarlanır** | Dosya uzantıları ve gizli dosyalar görünür, klasik sağ tık menüsü geri gelir, Explorer "Bu Bilgisayar" ile açılır |
| **Dokunulmaz** | Defender, Windows Update, işlemci güvenlik korumaları, Microsoft Store, winget, Terminal, Fotoğraflar, Hesap Makinesi, Not Defteri, Paint, Ekran Alıntısı Aracı, iş Teams'i, klasik Outlook, WebView2, Windows Search, Get Help, Intune senkronizasyonu |

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
  `%ProgramData%\CemalCloud\Win11Debloat\`. Bu klasöre yalnızca yöneticiler yazabilir. **Geri al** ve Nöbetçi,
  yönetici olmayan birinin bıraktığı dosyaları okumaz. Nöbetçi açıksa scriptin bir kopyası
  `%ProgramFiles%\CemalCloud\Win11Debloat\` altına konur.
- **Ağ:** debloat hiçbir yere bağlanmaz. Yalnızca **Geri al**, kaldırılmış OneDrive ve Edge'i yeniden kurmak için winget kullanır.
- **Kimin ayarları:** bilgisayar genelindeki ayarlar herkese, kişisel ayarlar uygulamayı çalıştıran hesaba uygulanır.

## Test ettik

Her commit'te GitHub Actions üç ayrı testi **gerçek bir Windows'ta** çalıştırır (Windows Server 2025, Windows 11 24H2
ile aynı çekirdek):

| Test | Sonuç (son çalıştırma) |
|---|---|
| Önizle → Uygula (oyuncu ayarlarıyla) → Nöbetçi → tekrar Uygula → Geri al | 100 kontrol geçti. Uygulama 111 registry değerini değiştirdi ve performans güç planını açtı. Geri al hepsini, güç planı dahil, eski haline döndürdü. Önizleme hiçbir şeye dokunmadı. |
| Windows güncellemesi taklidi | Telemetri politikası sıfırlandı, Copilot politikası silindi, bir görev yeniden açıldı. **Kontrol et** üçünü de buldu, **Yeniden uygula** düzeltti. Nöbetçi görevi kuruldu, yeni bir değişikliği kendi başına çalışıp düzeltti. |
| Uygulama, penceresiz | Gömülü scriptler repodakilerle aynı. 64-bit PowerShell kullanılıyor. Önizle, Uygula, Kontrol et, Nöbetçi kur / kaldır ve Geri al uygulama üzerinden sorunsuz. |
| Uygulama, penceresiyle | Pencere açıldı, Edge'in işareti tıklamayla kaldırıldı, **Önizle**'ye basıldı. Script `-KeepEdge` ile çalıştı, sonuç pencerede göründü. Bir politika geri değiştirildikten sonra açılan yeni pencere bunu kendiliğinden fark etti. |

Dürüst not: sunucu sürümünde Store uygulamaları, Edge kaldırma ve OneDrive olmadığı için bu kısımlar testin dışında
kalıyor. CI makinesi yeniden başlatılamadığı için performans ayarlarının yeniden başlatma sonrası etkisi orada
ölçülemiyor; testler ayarların doğru yazıldığını ve geri alındığını doğruluyor. İlk kullanımda bir sanal makinede **Önizle** ile başlayın.

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
| Performans ayarları (işaretsiz) | `-SkipPerformance` | Saydamlık, animasyon, arka plan, zamanlayıcı ve güç ayarlarına dokunmaz |
| Oyuncu ayarları (işaretli) | `-GamingTweaks` | Fare ivmesi kapalı, zamanlayıcı çözünürlüğü, erişilebilirlik kısayolları kapalı, Oyun Modu açık |
| Kontrol et | `-Check` | Neyin geri döndüğünü listeler, hiçbir şeyi değiştirmez (çıkış kodu 10: değişen var) |
| Kontrol et → Evet | `-Reapply` | Yalnızca geri dönenleri son seferki seçeneklerle tekrar uygular |
| Nöbetçi | `-InstallGuard`, `-RemoveGuard` | Oturum açınca kontrol edip düzelten görevi kurar / kaldırır |
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

**Windows 11 Debloat** removes ads, Copilot, Recall, preinstalled apps and telemetry, applies performance settings in
one click, and records every change so it can be undone in one click. It is a 148 KB app (no install) that runs the PowerShell scripts in this
repository and shows their output live.

- **Download:** `Win11-Debloat.exe` from [Releases](https://github.com/cemal-demirci/win11-debloat/releases/latest).
  Untick what you use, press **Önizle** (preview), then **Uygula** (apply) and restart. **Geri al** (restore) undoes everything.
- **Performance:** settings that are safe to undo: transparency and animations off (ClearType and thumbnails stay),
  background Store apps off, no startup delay, foreground priority and MMCSS, NTFS last-access off, larger icon cache,
  service host grouping (not with Xbox kept), no P2P update upload, and on desktops without a battery a high
  performance power plan with power throttling off. Defender, Windows Update and CPU mitigations are never touched.
  `-SkipPerformance` leaves all of it alone; **Kontrol et** shows processes, service hosts, running services and memory
  before the first run vs now.
- **Gaming (optional, `-GamingTweaks`):** mouse acceleration off, timer resolution requests system-wide again (nothing
  forced), Sticky / Filter / Toggle Keys shortcut prompts off (only the shortcut bit; the features keep their state),
  Game Mode on.
- **Guard:** every run saves what it put in place (`state.json`). **Kontrol et** (`-Check`) lists what Windows turned
  back since then (registry values, re-enabled tasks, returned apps, reinstalled Edge / OneDrive) and `-Reapply` fixes
  only those. The optional **Nöbetçi** (`-InstallGuard`) is a sign-in task that does this by itself and logs to
  `guard.log`; restore removes it.
- **Safety:** restore point, registry export and an undo manifest before any change. The backup folder is
  admin-writable only, and restore / the guard ignore files not owned by an administrator. OneDrive is kept when it is signed
  in, Edge is kept when no other browser is installed. Store, winget, Terminal, work Teams, classic Outlook, Windows
  Search, Get Help and Intune sync are never touched.
- **Scripts:** `Win11-Debloat.ps1 [-DryRun] [-KeepEdge] [-KeepOneDrive] [-KeepXbox] [-KeepThirdParty]`, `Win11-Restore.ps1`.
- **Tested:** every commit runs a real preview / apply / guard / repeat / restore round trip (100 checks, including a
  simulated feature update that the check finds and the guard task fixes by itself), the app headless and the app
  window (UI clicks, drift noticed on start) on Windows Server 2025. Desktop-only parts (Store apps, Edge removal, OneDrive) are not covered there;
  start with a preview in a VM.
- **License:** MIT.
