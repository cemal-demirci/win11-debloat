## İndirme

**`Win11-Debloat.exe`** dosyasını indirip çalıştırın. Kurulum gerekmez, yönetici izni ister.

1. Seçenekleri işaretleyin. **Performans ayarları** saydamlığı ve animasyonları kapatır, arka plan uygulamalarını durdurur, masaüstünde yüksek performans güç planını açar (hepsi geri alınabilir; Defender, Windows Update ve işlemci korumalarına dokunulmaz).
2. **Önizle** ile nelerin değişeceğine bakın (hiçbir şey değişmez).
3. **Uygula**'ya basın, bitince bilgisayarı yeniden başlatın.
4. Beğenmezseniz **Geri al**.
5. Bir güncellemeden sonra **Kontrol et**: Windows'un geri açtıklarını listeler, isterseniz sadece onları düzeltir.
   **Nöbetçi** seçeneği bunu her oturum açışta kendisi yapar.

Uygulama imzasız olduğu için Windows "Bilgisayarınız korundu" uyarısı gösterebilir: **Ek bilgi → Yine de çalıştır**. Dosyanın doğruluğunu `SHA256SUMS.txt` ile kontrol edebilirsiniz:

```powershell
Get-FileHash .\Win11-Debloat.exe
```

PowerShell ile kullanmak isteyenler için `Win11-Debloat.ps1` ve `Win11-Restore.ps1` de eklidir. Ayrıntılar: [README](https://github.com/cemal-demirci/win11-debloat#readme)

---

**English:** download `Win11-Debloat.exe` and run it (no install, asks for admin). Tick the options, press **Önizle** (preview) to see what would change, then **Uygula** (apply) and restart; **Geri al** (restore) undoes everything. The **Performans ayarları** (performance) option applies performance settings that are safe to undo. After a Windows update, **Kontrol et** (check) lists what Windows turned back and fixes only that; the **Nöbetçi** (guard) option does it at every sign-in. The app is unsigned, so SmartScreen may warn: *More info → Run anyway*. Verify the download with `SHA256SUMS.txt`.
