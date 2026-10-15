// Cemal.cloud | Windows 11 Debloat app: entry point
using System;
using System.Windows.Forms;

namespace CemalCloud.Win11Debloat
{
    internal static class Program
    {
        /// <summary>Unexpected error: write it next to the extracted scripts and tell the user where.</summary>
        private static void Crash(Exception ex)
        {
            string file = System.IO.Path.Combine(ScriptRunner.WorkDir, "crash.log");
            try
            {
                System.IO.Directory.CreateDirectory(ScriptRunner.WorkDir);
                System.IO.File.AppendAllText(file, DateTime.Now.ToString("s") + " v" + ScriptRunner.Version + "\r\n" + ex + "\r\n\r\n");
            }
            catch { }
            if (Environment.GetEnvironmentVariable("GITHUB_ACTIONS") != null) Environment.Exit(3);
            MessageBox.Show("Beklenmeyen bir hata oluştu:\n\n" + (ex == null ? "?" : ex.Message) + "\n\nAyrıntılar: " + file,
                            "Windows 11 Debloat", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }

        [STAThread]
        private static int Main(string[] args)
        {
            // Headless helpers (used by CI, also handy for scripting):
            //   --extract <dir>                               write the embedded scripts
            //   --run <log> preview|apply|restore|check|reapply|guard-install|guard-remove [switches]
            if (args.Length == 2 && args[0] == "--extract")
            {
                ScriptRunner.Extract(args[1]);
                return 0;
            }
            if (args.Length >= 2 && args[0] == "--run")
            {
                return ScriptRunner.RunHeadless(args);
            }

            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);
            Application.ThreadException += (s, e) => Crash(e.Exception);
            AppDomain.CurrentDomain.UnhandledException += (s, e) => Crash(e.ExceptionObject as Exception);
            try
            {
                Application.Run(new MainForm());
            }
            catch (Exception ex)
            {
                Crash(ex);
                return 1;
            }
            return 0;
        }
    }
}
