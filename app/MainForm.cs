// Cemal.cloud | Windows 11 Debloat app: main window
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Windows.Forms;

namespace CemalCloud.Win11Debloat
{
    internal sealed class MainForm : Form
    {
        private enum Mode { Preview, Apply, Restore, Check, Reapply, GuardInstall, GuardRemove }

        private readonly CheckBox chkEdge, chkOneDrive, chkXbox, chkThirdParty, chkOutlook, chkUi, chkPerf, chkGaming, chkGuard;
        private readonly Button btnPreview, btnApply, btnCheck, btnRestore;
        private readonly Label lblStatus;
        private readonly ActivityLine activity;
        private readonly Header header;
        private readonly RichTextBox txtLog;
        private readonly ToolTip tips = new ToolTip { AutoPopDelay = 20000, InitialDelay = 400, OwnerDraw = true };
        private readonly Font tipFont = Theme.Ui(9f);

        private Process running;
        private Mode runningMode;
        private bool sawRestorePointFailure;
        private bool autoCheck;            // the silent drift check when the window opens
        private bool rebootPromptAfterGuard;
        private bool syncingGuard;         // set while the app changes chkGuard itself
        private int driftCount = -1;       // from the last check, -1 = not checked yet

        public MainForm()
        {
            SuspendLayout();
            AutoScaleDimensions = new SizeF(96f, 96f);   // sizes below are written for 100 % scaling
            AutoScaleMode = AutoScaleMode.Dpi;
            Text = "Windows 11 Debloat · Cemal.cloud";
            Font = Theme.Ui(9.75f);
            ForeColor = Theme.Text;
            BackColor = Theme.Bg;
            ClientSize = new Size(980, 650);
            MinimumSize = new Size(900, 600);
            StartPosition = FormStartPosition.CenterScreen;
            try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { }

            tips.Draw += DrawTip;
            tips.Popup += SizeTip;

            // ---- header -------------------------------------------------------------
            header = new Header();
            activity = new ActivityLine();

            // ---- options (left) -----------------------------------------------------
            var remove = new OptionGroup();
            chkEdge = Row(remove, "chkEdge", "Edge'i kaldır", "Başka bir tarayıcı yoksa kalır", true,
                "Başka bir tarayıcı kurulu değilse Edge kaldırılmaz. Microsoft kaldırmaya sadece bazı bölgelerde izin verir; kalırsa arka plan özellikleri kapatılır.");
            chkOneDrive = Row(remove, "chkOneDrive", "OneDrive'ı kaldır", "Oturum açıksa ya da yedekliyorsa kalır", true,
                "OneDrive'da oturum açıksa veya klasörleriniz yedekleniyorsa OneDrive kaldırılmaz, bulut dosyalarınız güvende kalır.");
            chkXbox = Row(remove, "chkXbox", "Xbox uygulamalarını kaldır", "Uygulamalar, servisler ve Game Bar", true,
                "Xbox uygulamaları, servisleri ve Game Bar. Oyun oynuyorsanız kapatın.");
            chkOutlook = Row(remove, "chkOutlook", "Yeni Outlook'u kaldır", "Klasik Outlook etkilenmez", true,
                "Sadece Windows ile gelen \"yeni Outlook\" uygulaması. Microsoft 365'teki klasik Outlook etkilenmez.");
            chkThirdParty = Row(remove, "chkThirdParty", "Üçüncü parti uygulamaları kaldır", "Spotify, Netflix, TikTok... verileriyle birlikte", true,
                "Üretici ve tanıtım amaçlı yüklenen uygulamalar tüm kullanıcılardan, verileriyle birlikte kaldırılır. Kullandıklarınız varsa kapatın.");

            var tune = new OptionGroup();
            chkUi = Row(tune, "chkUi", "Arayüz ayarları", "Dosya uzantıları, klasik sağ tık menüsü", true,
                "Dosya uzantılarını ve gizli dosyaları gösterir, klasik sağ tık menüsünü getirir, Explorer'ı \"Bu Bilgisayar\" ile açar.");
            chkPerf = Row(tune, "chkPerf", "Performans ayarları", "Saydamlık, animasyonlar, arka plan, güç planı", true,
                "Hepsi geri alınabilir: saydamlık ve animasyonlar kapanır (ClearType ve küçük resimler kalır), "
              + "Store uygulamaları arka planda çalışmaz, açılış gecikmesi kalkar, ön plandaki uygulamaya öncelik verilir, "
              + "servisler daha az svchost'ta toplanır. Masaüstü bilgisayarlarda yüksek performans güç planı; dizüstünde güç planına dokunulmaz. "
              + "Defender, Windows Update ve işlemci güvenlik korumalarına dokunulmaz.");
            chkGaming = Row(tune, "chkGaming", "Oyuncu ayarları", "Fare ivmesi, zamanlayıcı, Yapışkan Tuşlar", false,
                "İsteğe bağlı. Fare ivmesi (\"İşaretçi hassasiyetini artır\") kapanır, fare 1:1 hareket eder. Bir oyun yüksek zamanlayıcı "
              + "çözünürlüğü istediğinde tüm sisteme uygulanır, sürekli zorlanmaz. Shift'e 5 kez basınca çıkan Yapışkan Tuşlar / "
              + "Filtre Tuşları / Geçiş Tuşları pencereleri çıkmaz (özellikleri kullanıyorsanız açık kalır). Oyun Modu açık.");

            var guard = new OptionGroup();
            chkGuard = Row(guard, "chkGuard", "Nöbetçi", "Güncelleme bir şeyi geri açarsa oturum açınca düzeltir", ScriptRunner.GuardInstalled,
                "Her oturum açışınızdan 2 dakika sonra kontrol eder. Bir güncelleme ayarları geri açtıysa ya da uygulamaları "
              + "geri kurduysa yalnızca onları yeniden uygular, her şeyi kaydeder. Kayıt: guard.log. \"Geri al\" nöbetçiyi de kaldırır.");
            chkGuard.CheckedChanged += OnGuardToggled;

            var left = new Panel { Dock = DockStyle.Fill, AutoScroll = true, BackColor = Theme.Bg, Padding = new Padding(0, 0, 10, 0) };
            Theme.DarkScrollBars(left);
            Stack(left, Section("Kaldırılacaklar"), remove, Gap(), Section("Ayarlar"), tune, Gap(), Section("Koruma"), guard);

            // ---- actions, status, log (right) --------------------------------------
            btnPreview = MakeButton("btnPreview", "Önizle", ActionButton.Kind.Outline,
                "Hiçbir şeyi değiştirmez, nelerin yapılacağını listeler.");
            btnApply = MakeButton("btnApply", "Uygula", ActionButton.Kind.Primary,
                "Önce geri yükleme noktası ve yedek alır, sonra değişiklikleri uygular.");
            btnCheck = MakeButton("btnCheck", "Kontrol et", ActionButton.Kind.Outline,
                "Son uygulamadan bu yana Windows'un geri açtığı ayarları ve geri kurduğu uygulamaları listeler. Hiçbir şeyi değiştirmez.");
            btnRestore = MakeButton("btnRestore", "Geri al", ActionButton.Kind.Ghost,
                "Bu uygulamayla yapılan tüm değişiklikleri en yeniden eskiye doğru geri alır.");
            btnPreview.Click += (s, e) => Run(Mode.Preview, false);
            btnApply.Click += (s, e) => Run(Mode.Apply, false);
            btnCheck.Click += (s, e) => Run(Mode.Check, false);
            btnRestore.Click += (s, e) => Run(Mode.Restore, false);
            btnApply.Margin = new Padding(0, 0, 10, 0);
            btnCheck.Margin = new Padding(0, 0, 10, 0);
            btnRestore.Margin = new Padding(6, 0, 0, 0);

            var actions = new FlowLayoutPanel
            {
                Dock = DockStyle.Top,
                Height = 40,
                WrapContents = false,
                BackColor = Theme.Bg,
                Margin = Padding.Empty,
                Padding = Padding.Empty
            };
            actions.Controls.AddRange(new Control[] { btnPreview, btnApply, btnCheck, btnRestore });

            lblStatus = new Label
            {
                Name = "lblStatus",
                AccessibleName = "Durum",
                Text = "Hazır",
                Dock = DockStyle.Top,
                Height = 36,
                AutoSize = false,
                TextAlign = ContentAlignment.MiddleLeft,
                ForeColor = Theme.Muted,
                Font = Theme.Ui(9.5f),
                Padding = new Padding(2, 0, 0, 0)
            };

            txtLog = new RichTextBox
            {
                Name = "txtLog",
                AccessibleName = "Kayıt",
                ReadOnly = true,
                DetectUrls = false,
                WordWrap = true,
                ScrollBars = RichTextBoxScrollBars.Vertical,
                Dock = DockStyle.Fill,
                Font = Theme.Mono(9f),
                BackColor = Theme.LogBg,
                ForeColor = Theme.LogText,
                BorderStyle = BorderStyle.None,
                HideSelection = true
            };
            Theme.DarkScrollBars(txtLog);
            var logFrame = new LogFrame { Dock = DockStyle.Fill };
            logFrame.Controls.Add(txtLog);

            var footer = new FlowLayoutPanel { Dock = DockStyle.Bottom, Height = 34, Padding = new Padding(0, 10, 0, 0), BackColor = Theme.Bg };
            footer.Controls.Add(Link("Yedek klasörü", () =>
            {
                Directory.CreateDirectory(ScriptRunner.BackupDir);
                OpenUrl(ScriptRunner.BackupDir);
            }));
            footer.Controls.Add(Link("GitHub", () => OpenUrl("https://github.com/cemal-demirci/win11-debloat")));
            footer.Controls.Add(new Label { Text = "Cemal.cloud v" + ScriptRunner.Version, AutoSize = true, ForeColor = Theme.Muted, Margin = new Padding(14, 0, 0, 0) });

            var right = new Panel { Dock = DockStyle.Fill, BackColor = Theme.Bg, Padding = new Padding(14, 0, 0, 0) };
            right.Controls.Add(logFrame);    // fill: added first so the docked rows take their space first
            right.Controls.Add(footer);
            right.Controls.Add(lblStatus);
            right.Controls.Add(actions);

            var body = new TableLayoutPanel
            {
                Dock = DockStyle.Fill,
                ColumnCount = 2,
                RowCount = 1,
                BackColor = Theme.Bg,
                Padding = new Padding(22, 18, 22, 14)
            };
            body.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 404));
            body.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            body.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            left.Margin = Padding.Empty;
            right.Margin = Padding.Empty;
            body.Controls.Add(left, 0, 0);
            body.Controls.Add(right, 1, 0);

            Controls.Add(body);
            Controls.Add(activity);
            Controls.Add(header);

            Welcome();
            UpdatePills();

            AcceptButton = btnPreview;
            FormClosing += OnFormClosing;
            Shown += (s, e) =>
            {
                txtLog.Select(txtLog.TextLength, 0);   // do not start with the log text selected
                btnPreview.Focus();
                // Applied before? Quietly check whether Windows turned anything back.
                if (ScriptRunner.StateExists) Run(Mode.Check, false, false, true);
            };
            ResumeLayout(false);
            PerformLayout();
        }

        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            Theme.StyleTitleBar(Handle);
        }

        protected override void OnLoad(EventArgs e)
        {
            base.OnLoad(e);
            // Small screens / high scaling: never open taller or wider than the work area.
            Rectangle wa = Screen.FromControl(this).WorkingArea;
            if (Height > wa.Height) Height = wa.Height;
            if (Width > wa.Width) Width = wa.Width;
            Location = new Point(wa.Left + (wa.Width - Width) / 2, wa.Top + (wa.Height - Height) / 2);
        }

        // ---------------------------------------------------------------------------

        private CheckBox Row(OptionGroup group, string name, string title, string detail, bool on, string tip)
        {
            OptionRow row = group.Add(new OptionRow(name, title, detail, on));
            tips.SetToolTip(row, tip);
            tips.SetToolTip(row.Switch, tip);
            return row.Switch;
        }

        private ActionButton MakeButton(string name, string text, ActionButton.Kind kind, string tip)
        {
            var b = new ActionButton(kind) { Name = name, Text = text, AccessibleName = text };
            b.FitWidth();
            tips.SetToolTip(b, tip);
            return b;
        }

        private static Label Section(string text)
        {
            return new Label
            {
                Text = text,
                Dock = DockStyle.Top,
                AutoSize = false,
                Height = 26,
                TextAlign = ContentAlignment.TopLeft,
                ForeColor = Theme.Muted,
                Font = Theme.UiSemibold(9.5f),
                Padding = new Padding(4, 0, 0, 0)
            };
        }

        private static Control Gap()
        {
            return new Panel { Dock = DockStyle.Top, Height = 10, BackColor = Theme.Bg };
        }

        private static void Stack(Control parent, params Control[] items)
        {
            // Dock=Top docks the last child in the collection first, so bring each new one to the front.
            foreach (Control c in items) { parent.Controls.Add(c); c.BringToFront(); }
        }

        private static LinkLabel Link(string text, System.Action onClick)
        {
            var l = new LinkLabel
            {
                Text = text,
                AutoSize = true,
                LinkColor = Theme.Info,
                ActiveLinkColor = Theme.Text,
                VisitedLinkColor = Theme.Info,
                LinkBehavior = LinkBehavior.HoverUnderline,
                Margin = new Padding(0, 0, 14, 0)
            };
            l.LinkClicked += (s, e) => onClick();
            return l;
        }

        private void DrawTip(object sender, DrawToolTipEventArgs e)
        {
            e.Graphics.Clear(Theme.Surface);
            using (var p = new Pen(Theme.Line)) e.Graphics.DrawRectangle(p, 0, 0, e.Bounds.Width - 1, e.Bounds.Height - 1);
            TextRenderer.DrawText(e.Graphics, e.ToolTipText, tipFont, Rectangle.Inflate(e.Bounds, -10, -8), Theme.Text,
                TextFormatFlags.WordBreak | TextFormatFlags.Left | TextFormatFlags.NoPrefix);
        }

        private void SizeTip(object sender, PopupEventArgs e)
        {
            string text = tips.GetToolTip(e.AssociatedControl);
            Size sz = TextRenderer.MeasureText(text, tipFont, new Size(360, 0), TextFormatFlags.WordBreak | TextFormatFlags.NoPrefix);
            e.ToolTipSize = new Size(sz.Width + 20, sz.Height + 16);
        }

        private void Welcome()
        {
            AppendLine("Her durumda kapanır: Copilot, Recall, reklamlar, telemetri.");
            AppendLine("Dokunulmaz: Store, winget, Defender, Windows Update.");
            AppendLine("Yedekler: " + ScriptRunner.BackupDir);
            AppendLine("");
            AppendLine("> Önce \"Önizle\": hiçbir şeyi değiştirmeden gösterir.");
        }

        private void UpdatePills()
        {
            if (!ScriptRunner.StateExists)
                header.RunState.Set("Henüz uygulanmadı", Theme.Muted);
            else if (driftCount > 0)
                header.RunState.Set(driftCount + " ayar geri döndü", Theme.Warn);
            else
            {
                string when = ScriptRunner.LastRunTime();
                header.RunState.Set(when == null ? "Uygulandı" : "Uygulandı, " + when, Theme.Accent);
            }
            bool g = ScriptRunner.GuardInstalled;
            header.GuardState.Set(g ? "Nöbetçi açık" : "Nöbetçi kapalı", g ? Theme.Accent : Theme.Muted);
        }

        private List<string> SelectedSwitches()
        {
            var s = new List<string>();
            if (!chkEdge.Checked) s.Add("-KeepEdge");
            if (!chkOneDrive.Checked) s.Add("-KeepOneDrive");
            if (!chkXbox.Checked) s.Add("-KeepXbox");
            if (!chkThirdParty.Checked) s.Add("-KeepThirdParty");
            if (!chkOutlook.Checked) s.Add("-KeepOutlookNew");
            if (!chkUi.Checked) s.Add("-SkipUiTweaks");
            if (!chkPerf.Checked) s.Add("-SkipPerformance");
            if (chkGaming.Checked) s.Add("-GamingTweaks");
            return s;
        }

        private void Run(Mode mode, bool skipRestorePoint, bool clearLog = true, bool auto = false)
        {
            if (running != null) return;

            if (mode == Mode.Apply && !skipRestorePoint && !Confirm(
                    "Seçili uygulamalar kaldırılacak ve ayarlar değiştirilecek.\n\n"
                  + "Başlamadan önce bir sistem geri yükleme noktası ve yedek alınır, "
                  + "\"Geri al\" ile her şey eski haline döndürülebilir.\n\nDevam edilsin mi?"))
                return;
            if (mode == Mode.Restore && !Confirm(
                    "Bu uygulamayla yapılan değişiklikler geri alınacak. Kaldırılan OneDrive ve Edge yeniden kurulur.\n\nDevam edilsin mi?"))
                return;

            List<string> switches;
            string script;
            if (mode == Mode.Restore)
            {
                script = ScriptRunner.RestoreScript;
                switches = new List<string>();
            }
            else if (mode == Mode.Check || mode == Mode.Reapply || mode == Mode.GuardInstall || mode == Mode.GuardRemove)
            {
                script = ScriptRunner.DebloatScript;
                switches = new List<string>
                {
                    mode == Mode.Check ? "-Check" : mode == Mode.Reapply ? "-Reapply"
                  : mode == Mode.GuardInstall ? "-InstallGuard" : "-RemoveGuard"
                };
            }
            else
            {
                script = ScriptRunner.DebloatScript;
                switches = SelectedSwitches();
                if (mode == Mode.Preview) switches.Insert(0, "-DryRun");
                if (skipRestorePoint) switches.Add("-SkipRestorePoint");
            }

            if (clearLog) txtLog.Clear();
            else if (txtLog.TextLength > 0) AppendLine("");
            sawRestorePointFailure = false;
            autoCheck = auto;
            SetBusy(true, BusyText(mode));
            runningMode = mode;
            try
            {
                running = ScriptRunner.Start(script, switches, OnLine, OnExit);
            }
            catch (Exception ex)
            {
                running = null;
                AppendLine("error: başlatılamadı: " + ex.Message);
                SetBusy(false, "Hata");
                lblStatus.ForeColor = Theme.Danger;
            }
        }

        private void OnLine(string line)
        {
            if (line.IndexOf("restore point failed", StringComparison.OrdinalIgnoreCase) >= 0)
                sawRestorePointFailure = true;
            BeginInvoke((Action)(() => AppendLine(line)));
        }

        private void OnExit(int code)
        {
            BeginInvoke((Action)(() =>
            {
                Mode mode = runningMode;
                running = null;
                if (mode == Mode.Check) { OnCheckDone(code); return; }
                if (mode == Mode.GuardInstall || mode == Mode.GuardRemove) { OnGuardDone(mode, code); return; }
                if (code == 0 && mode == Mode.Apply && (chkGuard.Checked || ScriptRunner.GuardInstalled))
                {
                    // Apply finished: install (or refresh) the guard as ticked, or remove it, then offer the restart.
                    driftCount = 0;
                    rebootPromptAfterGuard = true;
                    SetBusy(false, "Bitti");
                    Run(chkGuard.Checked ? Mode.GuardInstall : Mode.GuardRemove, false, false);
                    return;
                }
                if (code == 0 && mode == Mode.Restore) { SetGuardBox(false); driftCount = -1; }
                if (code == 0 && (mode == Mode.Apply || mode == Mode.Reapply)) driftCount = 0;
                if (code == 0)
                {
                    SetBusy(false, mode == Mode.Preview ? "Önizleme bitti, hiçbir şey değişmedi"
                                  : mode == Mode.Apply ? "Bitti" : mode == Mode.Reapply ? "Yeniden uygulandı" : "Geri alındı");
                    if (mode != Mode.Preview) lblStatus.ForeColor = Theme.Accent;
                    if (mode != Mode.Preview) OfferRestart();
                    return;
                }

                SetBusy(false, "Hata (kod " + code + ")");
                lblStatus.ForeColor = Theme.Danger;
                if (mode == Mode.Apply && sawRestorePointFailure && Confirm(
                        "Sistem geri yükleme noktası oluşturulamadı ve hiçbir şey değiştirilmedi.\n\n"
                      + "Geri yükleme noktası olmadan devam edebilirsiniz. Değişiklikler yine kaydedilir ve \"Geri al\" ile geri alınabilir.\n\n"
                      + "Geri yükleme noktası olmadan devam edilsin mi?"))
                {
                    Run(Mode.Apply, true);
                }
            }));
        }

        private void OnCheckDone(int code)
        {
            bool auto = autoCheck;
            autoCheck = false;
            if (code == 0) { driftCount = 0; SetBusy(false, "Kontrol: her şey yerinde"); lblStatus.ForeColor = Theme.Accent; return; }
            if (code == 2) { SetBusy(false, "Bu bilgisayarda henüz uygulanmamış"); return; }
            if (code != ScriptRunner.DriftExitCode) { SetBusy(false, "Kontrol hatası (kod " + code + ")"); return; }

            int n = ScriptRunner.LastDriftCount();
            driftCount = n > 0 ? n : 1;
            string what = n > 0 ? n + " değişikliği" : "bazı değişiklikleri";
            SetBusy(false, "Windows " + what + " geri almış");
            lblStatus.ForeColor = Theme.Warn;
            if (!auto && Confirm("Son uygulamadan bu yana Windows " + what + " geri almış (ayrıntılar kayıtta).\n\n"
                               + "Sadece bunlar, son seferki seçeneklerle yeniden uygulansın mı?"))
                Run(Mode.Reapply, false, false);
        }

        private void OnGuardDone(Mode mode, int code)
        {
            bool installed = ScriptRunner.GuardInstalled;
            SetGuardBox(installed);
            if (code == 0) { SetBusy(false, installed ? "Bitti, nöbetçi kuruldu" : "Bitti, nöbetçi kaldırıldı"); lblStatus.ForeColor = Theme.Accent; }
            else { SetBusy(false, "Nöbetçi " + (mode == Mode.GuardInstall ? "kurulamadı" : "kaldırılamadı") + " (kod " + code + ")"); lblStatus.ForeColor = Theme.Danger; }
            if (rebootPromptAfterGuard) { rebootPromptAfterGuard = false; OfferRestart(); }
        }

        private void OnGuardToggled(object sender, EventArgs e)
        {
            if (syncingGuard || running != null) return;
            // Not applied yet: the guard is installed together with "Uygula".
            if (!ScriptRunner.StateExists) return;
            if (chkGuard.Checked != ScriptRunner.GuardInstalled)
                Run(chkGuard.Checked ? Mode.GuardInstall : Mode.GuardRemove, false, false);
        }

        private void SetGuardBox(bool value)
        {
            syncingGuard = true;
            try { chkGuard.Checked = value; } finally { syncingGuard = false; }
        }

        private void OfferRestart()
        {
            if (Confirm("İşlem tamamlandı. Tüm değişikliklerin geçerli olması için bilgisayarı yeniden başlatmanız gerekiyor.\n\n"
                      + "Şimdi yeniden başlatılsın mı?"))
                Process.Start(new ProcessStartInfo("shutdown.exe", "/r /t 5") { UseShellExecute = false, CreateNoWindow = true });
        }

        private static string BusyText(Mode mode)
        {
            switch (mode)
            {
                case Mode.Preview: return "Önizleniyor...";
                case Mode.Apply: return "Uygulanıyor...";
                case Mode.Check: return "Kontrol ediliyor...";
                case Mode.Reapply: return "Yeniden uygulanıyor...";
                case Mode.GuardInstall: return "Nöbetçi kuruluyor...";
                case Mode.GuardRemove: return "Nöbetçi kaldırılıyor...";
                default: return "Geri alınıyor...";
            }
        }

        private void AppendLine(string line)
        {
            txtLog.SelectionStart = txtLog.TextLength;
            txtLog.SelectionLength = 0;
            txtLog.SelectionColor = LineColor(line);
            txtLog.AppendText(line + "\n");
            txtLog.SelectionColor = txtLog.ForeColor;
            txtLog.ScrollToCaret();
        }

        // What each line of the scripts means, by its marker.
        private static Color LineColor(string line)
        {
            string t = line.TrimStart();
            if (t.StartsWith("==>")) return Theme.Info;
            if (t.StartsWith("+ ") || t.StartsWith("PASS")) return Theme.Accent;
            if (t.StartsWith("! ") || t.StartsWith("DRIFT")) return Theme.Warn;
            if (t.StartsWith("[dry]")) return Theme.Dry;
            if (t.StartsWith("> ")) return Theme.Muted;
            if (t.StartsWith("error", StringComparison.OrdinalIgnoreCase) || t.StartsWith("FAIL")
                || t.IndexOf("Unexpected error", StringComparison.Ordinal) >= 0) return Theme.Danger;
            if (t.StartsWith("Cemal.cloud |") || t.StartsWith("Done.") || t.StartsWith("Reapplied.")) return Theme.Text;
            return Theme.LogText;
        }

        private void SetBusy(bool busy, string status)
        {
            btnPreview.Enabled = btnApply.Enabled = btnCheck.Enabled = btnRestore.Enabled = !busy;
            foreach (var c in new[] { chkEdge, chkOneDrive, chkXbox, chkThirdParty, chkOutlook, chkUi, chkPerf, chkGaming, chkGuard }) c.Enabled = !busy;
            activity.Busy = busy;
            lblStatus.Text = status;
            lblStatus.ForeColor = busy ? Theme.Text : Theme.Muted;
            if (!busy) UpdatePills();
        }

        private bool Confirm(string message)
        {
            return MessageBox.Show(this, message, Text, MessageBoxButtons.YesNo, MessageBoxIcon.Question,
                                   MessageBoxDefaultButton.Button2) == DialogResult.Yes;
        }

        private void OnFormClosing(object sender, FormClosingEventArgs e)
        {
            if (running == null) return;
            MessageBox.Show(this,
                "İşlem devam ediyor. Yarıda kesmek sistemi tutarsız bırakabilir, lütfen bitmesini bekleyin.",
                Text, MessageBoxButtons.OK, MessageBoxIcon.Information);
            e.Cancel = true;
        }

        private static void OpenUrl(string target)
        {
            try { Process.Start(new ProcessStartInfo(target) { UseShellExecute = true }); } catch { }
        }
    }
}
