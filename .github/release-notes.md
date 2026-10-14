## İndirme

**`Win11-Debloat.exe`** dosyasını indirip çalıştırın. Kurulum gerekmez, yönetici izni ister.

1. Seçenekleri işaretleyin.
2. **Önizle** ile nelerin değişeceğine bakın (hiçbir şey değişmez).
3. **Uygula**'ya basın, bitince bilgisayarı yeniden başlatın.
4. Beğenmezseniz **Geri al**.

Uygulama imzasız olduğu için Windows "Bilgisayarınız korundu" uyarısı gösterebilir: **Ek bilgi → Yine de çalıştır**. Dosyanın doğruluğunu `SHA256SUMS.txt` ile kontrol edebilirsiniz:

```powershell
Get-FileHash .\Win11-Debloat.exe
```

PowerShell ile kullanmak isteyenler için `Win11-Debloat.ps1` ve `Win11-Restore.ps1` de eklidir. Ayrıntılar: [README](https://github.com/cemal-demirci/win11-debloat#readme)

---

**English:** download `Win11-Debloat.exe` and run it (no install, asks for admin). Tick the options, press **Önizle** (preview) to see what would change, then **Uygula** (apply) and restart; **Geri al** (restore) undoes everything. The app is unsigned, so SmartScreen may warn: *More info → Run anyway*. Verify the download with `SHA256SUMS.txt`.
