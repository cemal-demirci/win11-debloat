// Cemal.cloud | Windows 11 Debloat app
// Runs the embedded, tested PowerShell scripts. The app holds no debloat logic
// of its own: what it runs is byte-for-byte the same Win11-Debloat.ps1 /
// Win11-Restore.ps1 that is published in the repository.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;

namespace CemalCloud.Win11Debloat
{
    internal static class ScriptRunner
    {
        public const string DebloatScript = "Win11-Debloat.ps1";
        public const string RestoreScript = "Win11-Restore.ps1";

        // Switches the app is allowed to pass to the scripts. Anything else is rejected.
        private static readonly HashSet<string> AllowedSwitches = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "-DryRun", "-KeepEdge", "-KeepOneDrive", "-KeepXbox", "-KeepThirdParty",
            "-KeepOutlookNew", "-SkipUiTweaks", "-SkipRestorePoint", "-Force"
        };

        [DllImport("kernel32.dll")]
        private static extern int GetOEMCP();

        public static string WorkDir
        {
            get { return Path.Combine(Path.Combine(Path.GetTempPath(), "CemalCloud"), "Win11Debloat"); }
        }

        public static string BackupDir
        {
            get
            {
                return Path.Combine(Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "CemalCloud"), "Win11Debloat");
            }
        }

        // 64-bit Windows PowerShell 5.1. A 32-bit process would get the 32-bit
        // PowerShell and the 32-bit registry view, which must never happen here.
        public static string PowerShellPath
        {
            get
            {
                string windir = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
                string sys = (Environment.Is64BitOperatingSystem && !Environment.Is64BitProcess) ? "Sysnative" : "System32";
                return Path.Combine(windir, sys + @"\WindowsPowerShell\v1.0\powershell.exe");
            }
        }

        public static string Version
        {
            get
            {
                Version v = Assembly.GetExecutingAssembly().GetName().Version;
                return v.Major + "." + v.Minor + "." + v.Build;
            }
        }

        /// <summary>Writes the embedded scripts to <paramref name="dir"/> and returns it.</summary>
        public static string Extract(string dir)
        {
            Directory.CreateDirectory(dir);
            foreach (string name in new[] { DebloatScript, RestoreScript })
            {
                using (Stream src = Assembly.GetExecutingAssembly().GetManifestResourceStream(name))
                {
                    if (src == null) throw new InvalidOperationException("embedded script missing: " + name);
                    using (FileStream dst = File.Create(Path.Combine(dir, name)))
                    {
                        src.CopyTo(dst);
                    }
                }
            }
            return dir;
        }

        public static Process Start(string script, IList<string> switches,
                                    Action<string> onLine, Action<int> onExit)
        {
            foreach (string s in switches)
            {
                if (!AllowedSwitches.Contains(s)) throw new ArgumentException("switch not allowed: " + s);
            }
            string dir = Extract(WorkDir);
            var cmd = new StringBuilder();
            cmd.Append("-NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"")
               .Append(Path.Combine(dir, script)).Append('"');
            foreach (string s in switches) cmd.Append(' ').Append(s);

            // Windows PowerShell writes redirected output in the OEM code page.
            Encoding enc = Encoding.GetEncoding(GetOEMCP());
            var psi = new ProcessStartInfo(PowerShellPath, cmd.ToString())
            {
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true,
                StandardOutputEncoding = enc,
                StandardErrorEncoding = enc,
                WorkingDirectory = dir
            };
            var p = new Process { StartInfo = psi, EnableRaisingEvents = true };
            p.OutputDataReceived += (o, e) => { if (e.Data != null) onLine(e.Data); };
            p.ErrorDataReceived += (o, e) => { if (e.Data != null) onLine(e.Data); };
            p.Exited += (o, e) =>
            {
                p.WaitForExit();   // flush the async readers before reporting
                onExit(p.ExitCode);
            };
            onLine("> " + script + (switches.Count > 0 ? " " + string.Join(" ", switches) : ""));
            p.Start();
            p.BeginOutputReadLine();
            p.BeginErrorReadLine();
            return p;
        }

        /// <summary>
        /// Headless mode for CI and scripting:
        ///   Win11-Debloat.exe --run &lt;logfile&gt; preview|apply|restore [-KeepEdge ...]
        /// </summary>
        public static int RunHeadless(string[] args)
        {
            string log = args[1];
            string mode = args.Length > 2 ? args[2].ToLowerInvariant() : "preview";
            var switches = new List<string>();
            for (int i = 3; i < args.Length; i++) switches.Add(args[i]);

            string script = DebloatScript;
            if (mode == "preview") switches.Insert(0, "-DryRun");
            else if (mode == "restore") { script = RestoreScript; switches.Clear(); }
            else if (mode != "apply") return 2;

            var lines = new List<string>();
            lines.Add("app " + Version + ", " + (Environment.Is64BitProcess ? "64-bit" : "32-bit")
                      + " process, powershell: " + PowerShellPath);
            int code = -1;
            try
            {
                using (var done = new System.Threading.ManualResetEvent(false))
                {
                    Start(script, switches,
                          line => { lock (lines) lines.Add(line); },
                          exit => { code = exit; done.Set(); });
                    done.WaitOne();
                }
            }
            catch (Exception ex)
            {
                lock (lines) lines.Add("error: " + ex.Message);
                code = 3;
            }
            lock (lines) lines.Add("exit code " + code);
            File.WriteAllLines(log, lines.ToArray(), new UTF8Encoding(false));
            return code;
        }
    }
}
