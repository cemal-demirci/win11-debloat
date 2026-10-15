// Cemal.cloud | Windows 11 Debloat app: colours, type and window chrome
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;

namespace CemalCloud.Win11Debloat
{
    internal static class Theme
    {
        // Graphite base, one "clean" accent, and signal colours that mean something in the log.
        public static readonly Color Bg = Hex(0x15181D);
        public static readonly Color Surface = Hex(0x1C2027);
        public static readonly Color SurfaceHover = Hex(0x232833);
        public static readonly Color Line = Hex(0x2B313B);
        public static readonly Color Text = Hex(0xE8ECF1);
        public static readonly Color Muted = Hex(0x8E98A8);
        public static readonly Color Accent = Hex(0x3DDC97);     // applied / clean
        public static readonly Color AccentHover = Hex(0x5BE6A9);
        public static readonly Color AccentDown = Hex(0x2FBF80);
        public static readonly Color OnAccent = Hex(0x0B2418);
        public static readonly Color Info = Hex(0x6CB8FF);       // steps, links, focus
        public static readonly Color Warn = Hex(0xF2B544);       // drift, skipped
        public static readonly Color Danger = Hex(0xFF6E6E);
        public static readonly Color Dry = Hex(0xA99CFF);        // preview lines
        public static readonly Color LogBg = Hex(0x12151A);
        public static readonly Color LogText = Hex(0xC3CAD5);
        public static readonly Color ToggleOff = Hex(0x3A414D);

        private static string uiFamily, displayFamily, monoFamily;

        public static Font Ui(float size, FontStyle style = FontStyle.Regular)
        {
            if (uiFamily == null) uiFamily = FirstInstalled("Segoe UI Variable Text", "Segoe UI");
            return new Font(uiFamily, size, style);
        }

        public static Font UiSemibold(float size)
        {
            string fam = FirstInstalled("Segoe UI Variable Text Semibold", "Segoe UI Semibold");
            return new Font(fam, size);
        }

        public static Font Display(float size)
        {
            if (displayFamily == null) displayFamily = FirstInstalled("Segoe UI Variable Display Semibold", "Segoe UI Semibold");
            return new Font(displayFamily, size);
        }

        public static Font Mono(float size)
        {
            if (monoFamily == null) monoFamily = FirstInstalled("Cascadia Mono", "Consolas");
            return new Font(monoFamily, size);
        }

        private static string FirstInstalled(params string[] names)
        {
            foreach (string n in names)
            {
                // GDI+ silently substitutes a missing family, so compare what we got back.
                using (var f = new Font(n, 10f))
                {
                    if (string.Equals(f.Name, n, StringComparison.OrdinalIgnoreCase)) return n;
                }
            }
            return names[names.Length - 1];
        }

        public static Color Hex(int rgb)
        {
            return Color.FromArgb((rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF);
        }

        public static Color Mix(Color a, Color b, float t)
        {
            if (t < 0) t = 0; if (t > 1) t = 1;
            return Color.FromArgb(
                (int)(a.A + (b.A - a.A) * t), (int)(a.R + (b.R - a.R) * t),
                (int)(a.G + (b.G - a.G) * t), (int)(a.B + (b.B - a.B) * t));
        }

        public static Color Fade(Color c, float alpha)
        {
            return Color.FromArgb((int)(255 * alpha), c);
        }

        public static GraphicsPath Round(RectangleF r, float radius)
        {
            var p = new GraphicsPath();
            float d = Math.Min(radius * 2, Math.Min(r.Width, r.Height));
            if (d <= 0.5f) { p.AddRectangle(r); return p; }
            p.AddArc(r.X, r.Y, d, d, 180, 90);
            p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
            p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
            p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
            p.CloseFigure();
            return p;
        }

        /// <summary>The "slimming" mark: three bars getting shorter, on the accent square.</summary>
        public static void DrawMark(Graphics g, RectangleF r)
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            using (var path = Round(r, r.Width * 0.24f))
            using (var b = new SolidBrush(Accent))
                g.FillPath(b, path);
            float x = r.X + r.Width * 0.22f, h = r.Height * 0.12f, gap = r.Height * 0.085f;
            float y = r.Y + (r.Height - (3 * h + 2 * gap)) / 2f;
            float[] widths = { 0.56f, 0.40f, 0.24f };
            using (var bar = new SolidBrush(OnAccent))
            {
                for (int i = 0; i < 3; i++)
                {
                    using (var p = Round(new RectangleF(x, y + i * (h + gap), r.Width * widths[i], h), h / 2f))
                        g.FillPath(bar, p);
                }
            }
        }

        // ---- window chrome (Windows 10 2004+ / 11; silently ignored elsewhere) -----------

        [DllImport("dwmapi.dll")]
        private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);

        public static void StyleTitleBar(IntPtr hwnd)
        {
            try
            {
                int on = 1;
                if (DwmSetWindowAttribute(hwnd, 20, ref on, 4) != 0)      // DWMWA_USE_IMMERSIVE_DARK_MODE
                    DwmSetWindowAttribute(hwnd, 19, ref on, 4);           // pre-20H1 value
                int caption = ColorRef(Bg), border = ColorRef(Line), text = ColorRef(Text);
                DwmSetWindowAttribute(hwnd, 35, ref caption, 4);          // DWMWA_CAPTION_COLOR (Windows 11)
                DwmSetWindowAttribute(hwnd, 34, ref border, 4);           // DWMWA_BORDER_COLOR
                DwmSetWindowAttribute(hwnd, 36, ref text, 4);             // DWMWA_TEXT_COLOR
            }
            catch (DllNotFoundException) { }
            catch (EntryPointNotFoundException) { }
        }

        private static int ColorRef(Color c)
        {
            return c.R | (c.G << 8) | (c.B << 16);
        }

        [DllImport("user32.dll")]
        private static extern bool SystemParametersInfo(int action, int param, ref bool value, int winIni);

        /// <summary>Windows "Animation effects" setting (off after the debloat's performance settings).</summary>
        public static bool AnimationsOn
        {
            get
            {
                bool on = true;
                try { SystemParametersInfo(0x1042, 0, ref on, 0); } catch { }   // SPI_GETCLIENTAREAANIMATION
                return on;
            }
        }
    }
}
