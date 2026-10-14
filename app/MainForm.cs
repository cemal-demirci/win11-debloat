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
        private enum Mode { Preview, Apply, Restore }

        private static readonly Color Accent = Color.FromArgb(37, 99, 235);
        private static readonly Color Muted = Color.FromArgb(100, 100, 110);

        private readonly CheckBox chkEdge, chkOneDrive, chkXbox, chkThirdParty, chkOutlook, chkUi;
        private readonly Button btnPreview, btnApply, btnRestore;
        private readonly Label lblStatus;
        private readonly ProgressBar progress;
        private readonly TextBox txtLog;
        private readonly ToolTip tips = new ToolTip { AutoPopDelay = 15000 };

        private Process running;
        private Mode runningMode;
        private bool sawRestorePointFailure;

        public MainForm()
        {
            SuspendLayout();
            AutoScaleDimensions = new SizeF(96f, 96f);   // sizes below are written for 100 % scaling
            AutoScaleMode = AutoScaleMode.Dpi;
            Text = "Windows 11 Debloat · Cemal.cloud";
            Font = new Font("Segoe UI", 9.75f);
            ClientSize = new Size(780, 640);
            MinimumSize = new Size(640, 560);
            StartPosition = FormStartPosition.CenterScreen;
            BackColor = Color.White;
            try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { }

            // ---- header -------------------------------------------------------------
            var title = new Label
            {
                Text = "Windows 11 Debloat",
                Font = new Font("Segoe UI Semibold", 16f),
                AutoSize = true,
                Margin = new Padding(0, 0, 0, 2)
            };
            var subtitle = new Label
            {
                Text = "Reklamları, Copilot'u ve telemetriyi kapatır. Her değişiklik kaydedilir, \"Geri al\" ile eski haline döner.",
                ForeColor = Muted,
                AutoSize = true,
                MaximumSize = new Size(740, 0)
            };

            // ---- options ------------------------------------------------------------
            chkEdge = Option("chkEdge", "Edge'i kaldır",
                "Başka bir tarayıcı kurulu değilse Edge kaldırılmaz. Microsoft kaldırmaya sadece bazı bölgelerde izin verir; kalırsa arka plan özellikleri kapatılır.");
            chkOneDrive = Option("chkOneDrive", "OneDrive'ı kaldır",
                "OneDrive'da oturum açıksa veya klasörleriniz yedekleniyorsa OneDrive kaldırılmaz, bulut dosyalarınız güvende kalır.");
            chkXbox = Option("chkXbox", "Xbox uygulamalarını kaldır",
                "Xbox uygulamaları, servisleri ve Game Bar. Oyun oynuyorsanız işareti kaldırın.");
            chkThirdParty = Option("chkThirdParty", "Üçüncü parti uygulamaları kaldır (Spotify, Netflix...)",
                "Üretici ve tanıtım amaçlı yüklenen uygulamalar tüm kullanıcılardan, verileriyle birlikte kaldırılır. Kullandıklarınız varsa işareti kaldırın.");
            chkOutlook = Option("chkOutlook", "Yeni Outlook'u kaldır",
                "Sadece Windows ile gelen \"yeni Outlook\" uygulaması. Microsoft 365'teki klasik Outlook etkilenmez.");
            chkUi = Option("chkUi", "Arayüz ayarları (dosya uzantıları, klasik sağ tık menüsü)",
                "Dosya uzantılarını ve gizli dosyaları gösterir, klasik sağ tık menüsünü getirir, Explorer'ı \"Bu Bilgisayar\" ile açar.");

            var options = new TableLayoutPanel
            {
                ColumnCount = 2,
                AutoSize = true,
                AutoSizeMode = AutoSizeMode.GrowAndShrink,
                Dock = DockStyle.Top,
                Padding = new Padding(8, 4, 8, 6)
            };
            options.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
            options.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
            options.Controls.Add(chkEdge, 0, 0);
            options.Controls.Add(chkOneDrive, 1, 0);
            options.Controls.Add(chkXbox, 0, 1);
            options.Controls.Add(chkOutlook, 1, 1);
            options.Controls.Add(chkThirdParty, 0, 2);
            options.SetColumnSpan(chkThirdParty, 2);
            options.Controls.Add(chkUi, 0, 3);
            options.SetColumnSpan(chkUi, 2);

            var always = new Label
            {
                Text = "Her durumda kapatılır: Copilot, Recall, reklamlar ve öneriler, Başlat aramasında Bing, telemetri.\n"
                     + "Dokunulmaz: Store, winget, Terminal, iş Teams'i, klasik Outlook, Windows Search.",
                ForeColor = Muted,
                AutoSize = true,
                MaximumSize = new Size(700, 0),
                Margin = new Padding(3, 10, 3, 4)
            };
            options.Controls.Add(always, 0, 4);
            options.SetColumnSpan(always, 2);

            var optionsBox = new GroupBox
            {
                Text = "Seçenekler",
                Dock = DockStyle.Top,
                AutoSize = true,
                AutoSizeMode = AutoSizeMode.GrowAndShrink,
                Padding = new Padding(6)
            };
            optionsBox.Controls.Add(options);

            // ---- actions ------------------------------------------------------------
            btnPreview = ActionButton("btnPreview", "Önizle", false,
                "Hiçbir şeyi değiştirmez, nelerin yapılacağını listeler.");
            btnApply = ActionButton("btnApply", "Uygula", true,
                "Önce geri yükleme noktası ve yedek alır, sonra değişiklikleri uygular.");
            btnRestore = ActionButton("btnRestore", "Geri al",
                false, "Bu uygulamayla yapılan tüm değişiklikleri en yeniden eskiye doğru geri alır.");
            btnPreview.Click += (s, e) => Run(Mode.Preview, false);
            btnApply.Click += (s, e) => Run(Mode.Apply, false);
            btnRestore.Click += (s, e) => Run(Mode.Restore, false);

            progress = new ProgressBar
            {
                Style = ProgressBarStyle.Marquee,
                MarqueeAnimationSpeed = 0,
                Width = 120,
                Height = 10,
                Margin = new Padding(12, 14, 6, 0),
                Visible = false
            };
            lblStatus = new Label
            {
                Name = "lblStatus",
                AccessibleName = "Durum",
                Text = "Hazır",
                AutoSize = true,
                ForeColor = Muted,
                Margin = new Padding(8, 10, 0, 0)
            };
            var actions = new FlowLayoutPanel
            {
                Dock = DockStyle.Top,
                AutoSize = true,
                Padding = new Padding(0, 10, 0, 8),
                WrapContents = false
            };
            actions.Controls.AddRange(new Control[] { btnPreview, btnApply, btnRestore, progress, lblStatus });

            // ---- log ----------------------------------------------------------------
            txtLog = new TextBox
            {
                Name = "txtLog",
                AccessibleName = "Kayıt",
                Multiline = true,
                ReadOnly = true,
                MaxLength = int.MaxValue,   // default 32767 would silently cut long logs
                ScrollBars = ScrollBars.Vertical,
                WordWrap = false,
                Dock = DockStyle.Fill,
                Font = new Font("Consolas", 9f),
                BackColor = Color.FromArgb(30, 30, 30),
                ForeColor = Color.FromArgb(212, 212, 212),
                BorderStyle = BorderStyle.None
            };
            txtLog.Text = "Önce \"Önizle\" ile nelerin değişeceğine bakın, sonra \"Uygula\".\r\n"
                        + "Yedekler: " + ScriptRunner.BackupDir + "\r\n";

            // ---- footer -------------------------------------------------------------
            var repo = new LinkLabel { Text = "github.com/cemal-demirci/win11-debloat", AutoSize = true, LinkColor = Accent };
            repo.LinkClicked += (s, e) => OpenUrl("https://github.com/cemal-demirci/win11-debloat");
            var backups = new LinkLabel { Text = "Yedek klasörünü aç", AutoSize = true, LinkColor = Accent, Margin = new Padding(16, 3, 3, 3) };
            backups.LinkClicked += (s, e) =>
            {
                Directory.CreateDirectory(ScriptRunner.BackupDir);
                OpenUrl(ScriptRunner.BackupDir);
            };
            var version = new Label { Text = "v" + ScriptRunner.Version, AutoSize = true, ForeColor = Muted, Margin = new Padding(16, 3, 3, 3) };
            var footer = new FlowLayoutPanel { Dock = DockStyle.Bottom, AutoSize = true, Padding = new Padding(0, 8, 0, 0) };
            footer.Controls.AddRange(new Control[] { repo, backups, version });

            // ---- layout -------------------------------------------------------------
            var head = new FlowLayoutPanel
            {
                Dock = DockStyle.Top,
                FlowDirection = FlowDirection.TopDown,
                AutoSize = true,
                WrapContents = false,
                Padding = new Padding(0, 0, 0, 10)
            };
            head.Controls.Add(title);
            head.Controls.Add(subtitle);

            var logHost = new Panel { Dock = DockStyle.Fill, Padding = new Padding(8), BackColor = txtLog.BackColor };
            logHost.Controls.Add(txtLog);

            var root = new Panel { Dock = DockStyle.Fill, Padding = new Padding(18, 14, 18, 12) };
            root.Controls.Add(logHost);     // fill: added first so docking leaves it the remaining space
            root.Controls.Add(footer);
            root.Controls.Add(actions);
            root.Controls.Add(optionsBox);
            root.Controls.Add(head);
            Controls.Add(root);

            AcceptButton = btnPreview;
            FormClosing += OnFormClosing;
            Shown += (s, e) =>
            {
                txtLog.Select(txtLog.TextLength, 0);   // do not start with the log text selected
                btnPreview.Focus();
            };
            ResumeLayout(false);
            PerformLayout();
        }

        // ---------------------------------------------------------------------------

        private CheckBox Option(string name, string text, string tip)
        {
            var c = new CheckBox
            {
                Name = name,
                Text = text,
                AccessibleName = text,
                Checked = true,
                AutoSize = true,
                Margin = new Padding(3, 4, 12, 4)
            };
            tips.SetToolTip(c, tip);
            return c;
        }

        private Button ActionButton(string name, string text, bool primary, string tip)
        {
            var b = new Button
            {
                Name = name,
                Text = text,
                AccessibleName = text,
                AutoSize = true,
                MinimumSize = new Size(110, 34),
                Margin = new Padding(0, 0, 8, 0),
                FlatStyle = FlatStyle.System
            };
            if (primary)
            {
                b.FlatStyle = FlatStyle.Flat;
                b.BackColor = Accent;
                b.ForeColor = Color.White;
                b.FlatAppearance.BorderSize = 0;
                b.Font = new Font(Font, FontStyle.Bold);
            }
            tips.SetToolTip(b, tip);
            return b;
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
            return s;
        }

        private void Run(Mode mode, bool skipRestorePoint)
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
            else
            {
                script = ScriptRunner.DebloatScript;
                switches = SelectedSwitches();
                if (mode == Mode.Preview) switches.Insert(0, "-DryRun");
                if (skipRestorePoint) switches.Add("-SkipRestorePoint");
            }

            txtLog.Clear();
            sawRestorePointFailure = false;
            SetBusy(true, mode == Mode.Preview ? "Önizleniyor..." : mode == Mode.Apply ? "Uygulanıyor..." : "Geri alınıyor...");
            runningMode = mode;
            try
            {
                running = ScriptRunner.Start(script, switches, OnLine, OnExit);
            }
            catch (Exception ex)
            {
                running = null;
                AppendLine("Başlatılamadı: " + ex.Message);
                SetBusy(false, "Hata");
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
                if (code == 0)
                {
                    SetBusy(false, mode == Mode.Preview ? "Önizleme bitti, hiçbir şey değişmedi"
                                  : mode == Mode.Apply ? "Bitti" : "Geri alındı");
                    if (mode != Mode.Preview && Confirm(
                            "İşlem tamamlandı. Tüm değişikliklerin geçerli olması için bilgisayarı yeniden başlatmanız gerekiyor.\n\n"
                          + "Şimdi yeniden başlatılsın mı?"))
                        Process.Start(new ProcessStartInfo("shutdown.exe", "/r /t 5") { UseShellExecute = false, CreateNoWindow = true });
                    return;
                }

                SetBusy(false, "Hata (kod " + code + ")");
                if (mode == Mode.Apply && sawRestorePointFailure && Confirm(
                        "Sistem geri yükleme noktası oluşturulamadı ve hiçbir şey değiştirilmedi.\n\n"
                      + "Geri yükleme noktası olmadan devam edebilirsiniz. Değişiklikler yine kaydedilir ve \"Geri al\" ile geri alınabilir.\n\n"
                      + "Geri yükleme noktası olmadan devam edilsin mi?"))
                {
                    Run(Mode.Apply, true);
                }
            }));
        }

        private void AppendLine(string line)
        {
            txtLog.AppendText(line + "\r\n");
        }

        private void SetBusy(bool busy, string status)
        {
            btnPreview.Enabled = btnApply.Enabled = btnRestore.Enabled = !busy;
            foreach (var c in new[] { chkEdge, chkOneDrive, chkXbox, chkThirdParty, chkOutlook, chkUi }) c.Enabled = !busy;
            progress.Visible = busy;
            progress.MarqueeAnimationSpeed = busy ? 30 : 0;
            lblStatus.Text = status;
            UseWaitCursor = busy;
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
