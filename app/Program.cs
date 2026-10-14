// Cemal.cloud | Windows 11 Debloat app: entry point
using System;
using System.Windows.Forms;

namespace CemalCloud.Win11Debloat
{
    internal static class Program
    {
        [STAThread]
        private static int Main(string[] args)
        {
            // Headless helpers (used by CI, also handy for scripting):
            //   --extract <dir>                               write the embedded scripts
            //   --run <log> preview|apply|restore [switches]   run without a window
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
            Application.Run(new MainForm());
            return 0;
        }
    }
}
