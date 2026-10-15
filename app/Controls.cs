// Cemal.cloud | Windows 11 Debloat app: hand-drawn controls
//
// Every control here is still the standard Windows control underneath (a BUTTON
// window), so keyboard, screen readers, UI Automation and the CI window test keep
// working: BM_CLICK presses it, BM_GETCHECK reads a switch.
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

namespace CemalCloud.Win11Debloat
{
    internal static class Msg
    {
        public const int BM_GETCHECK = 0x00F0, BM_CLICK = 0x00F5;
    }

    /// <summary>On/off switch. A CheckBox, painted as a switch.</summary>
    internal sealed class ToggleSwitch : CheckBox
    {
        private float pos;                       // 0 = off, 1 = on (animated)
        private readonly Timer anim = new Timer { Interval = 15 };

        public ToggleSwitch()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            AutoSize = false;
            Size = new Size(46, 26);
            Cursor = Cursors.Hand;
            anim.Tick += (s, e) =>
            {
                float target = Checked ? 1f : 0f;
                pos += (target - pos) * 0.35f;
                if (Math.Abs(target - pos) < 0.02f) { pos = target; anim.Stop(); }
                Invalidate();
            };
        }

        protected override void OnCheckedChanged(EventArgs e)
        {
            base.OnCheckedChanged(e);
            if (IsHandleCreated && Visible && Theme.AnimationsOn) anim.Start();
            else { pos = Checked ? 1f : 0f; Invalidate(); }
        }

        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            pos = Checked ? 1f : 0f;
        }

        protected override void OnEnabledChanged(EventArgs e) { base.OnEnabledChanged(e); Invalidate(); }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.Clear(Parent != null ? Parent.BackColor : Theme.Surface);
            g.SmoothingMode = SmoothingMode.AntiAlias;
            float s = DeviceDpi / 96f;
            var track = new RectangleF(3 * s, 4 * s, Width - 6 * s, Height - 8 * s);
            float a = Enabled ? 1f : 0.4f;

            using (var path = Theme.Round(track, track.Height / 2))
            using (var b = new SolidBrush(Theme.Fade(Theme.Mix(Theme.ToggleOff, Theme.Accent, pos), a)))
                g.FillPath(b, path);

            float d = track.Height - 6 * s;
            float x = track.X + 3 * s + (track.Width - d - 6 * s) * pos;
            using (var b = new SolidBrush(Theme.Fade(Theme.Mix(Theme.Hex(0xC9CFD8), Theme.OnAccent, pos), a)))
                g.FillEllipse(b, x, track.Y + 3 * s, d, d);

            if (Focused && ShowFocusCues)
            {
                using (var path = Theme.Round(RectangleF.Inflate(track, 2 * s, 2 * s), track.Height / 2 + 2 * s))
                using (var p = new Pen(Theme.Info, 1.5f * s))
                    g.DrawPath(p, path);
            }
        }

        protected override void WndProc(ref Message m)
        {
            // A user-painted button does not answer these itself.
            if (m.Msg == Msg.BM_GETCHECK) { m.Result = (IntPtr)(Checked ? 1 : 0); return; }
            if (m.Msg == Msg.BM_CLICK) { if (Enabled) OnClick(EventArgs.Empty); m.Result = IntPtr.Zero; return; }
            base.WndProc(ref m);
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing) anim.Dispose();
            base.Dispose(disposing);
        }
    }

    /// <summary>Action button: filled (the one main action), outlined, or text only.</summary>
    internal sealed class ActionButton : Button
    {
        public enum Kind { Primary, Outline, Ghost }

        private readonly Kind kind;
        private bool hover, down;

        public ActionButton(Kind kind)
        {
            this.kind = kind;
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            FlatStyle = FlatStyle.Flat;
            FlatAppearance.BorderSize = 0;
            Cursor = Cursors.Hand;
            Font = kind == Kind.Primary ? Theme.UiSemibold(10f) : Theme.Ui(10f);
            Height = 38;
        }

        public void FitWidth()
        {
            Size t = TextRenderer.MeasureText(Text, Font);
            Width = Math.Max(t.Width + (kind == Kind.Ghost ? 24 : 40), kind == Kind.Ghost ? 72 : 108);
        }

        protected override void OnMouseEnter(EventArgs e) { hover = true; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { hover = false; down = false; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnMouseDown(MouseEventArgs e) { down = true; Invalidate(); base.OnMouseDown(e); }
        protected override void OnMouseUp(MouseEventArgs e) { down = false; Invalidate(); base.OnMouseUp(e); }
        protected override void OnEnabledChanged(EventArgs e) { base.OnEnabledChanged(e); Invalidate(); }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.Clear(Parent != null ? Parent.BackColor : Theme.Bg);
            g.SmoothingMode = SmoothingMode.AntiAlias;
            float s = DeviceDpi / 96f;
            var r = new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f);
            float a = Enabled ? 1f : 0.38f;
            Color fill = Color.Empty, border = Color.Empty, text;

            switch (kind)
            {
                case Kind.Primary:
                    fill = down ? Theme.AccentDown : hover ? Theme.AccentHover : Theme.Accent;
                    text = Theme.OnAccent;
                    break;
                case Kind.Outline:
                    fill = down ? Theme.Line : hover ? Theme.SurfaceHover : Theme.Surface;
                    border = hover ? Theme.Muted : Theme.Line;
                    text = Theme.Text;
                    break;
                default:
                    if (hover || down) fill = Theme.Surface;
                    text = hover ? Theme.Text : Theme.Muted;
                    break;
            }

            using (var path = Theme.Round(r, 8 * s))
            {
                if (!fill.IsEmpty) using (var b = new SolidBrush(Theme.Fade(fill, a))) g.FillPath(b, path);
                if (!border.IsEmpty) using (var p = new Pen(Theme.Fade(border, a), 1f)) g.DrawPath(p, path);
            }
            if (Focused && ShowFocusCues)
            {
                using (var path = Theme.Round(RectangleF.Inflate(r, -2 * s, -2 * s), 6 * s))
                using (var p = new Pen(kind == Kind.Primary ? Theme.OnAccent : Theme.Info, 1.5f * s))
                    g.DrawPath(p, path);
            }
            TextRenderer.DrawText(g, Text, Font, Rectangle.Round(r), Theme.Fade(text, a),
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine);
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == Msg.BM_CLICK) { if (Enabled) PerformClick(); m.Result = IntPtr.Zero; return; }
            base.WndProc(ref m);
        }
    }

    /// <summary>One setting: title and a short line on the left, a switch on the right.</summary>
    internal sealed class OptionRow : Control
    {
        public readonly ToggleSwitch Switch;
        private readonly string title, detail;
        private readonly Font titleFont = Theme.Ui(10f), detailFont = Theme.Ui(8.75f);
        private bool hover;

        public OptionRow(string name, string title, string detail, bool on)
        {
            this.title = title;
            this.detail = detail;
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            BackColor = Theme.Surface;
            Height = 50;
            Dock = DockStyle.Top;
            Cursor = Cursors.Hand;
            Switch = new ToggleSwitch
            {
                Name = name,
                Text = title,              // what screen readers and UI Automation read
                AccessibleName = title,
                AccessibleDescription = detail,
                Checked = on,
                Anchor = AnchorStyles.Right
            };
            Controls.Add(Switch);
            Switch.EnabledChanged += (s, e) => Invalidate();
            Switch.MouseEnter += (s, e) => { hover = true; Invalidate(); };
            Switch.MouseLeave += (s, e) => { hover = ClientRectangle.Contains(PointToClient(MousePosition)); Invalidate(); };
        }

        protected override void OnLayout(LayoutEventArgs e)
        {
            base.OnLayout(e);
            if (Switch == null) return;                 // setting Height in the constructor lays out early
            Switch.Location = new Point(Width - Switch.Width - (int)(12 * DeviceDpi / 96f), (Height - Switch.Height) / 2);
        }

        protected override void OnMouseEnter(EventArgs e) { hover = true; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { hover = false; Invalidate(); base.OnMouseLeave(e); }

        protected override void OnClick(EventArgs e)
        {
            base.OnClick(e);
            if (Switch.Enabled) { Switch.Focus(); Switch.Checked = !Switch.Checked; }
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.Clear(Theme.Surface);
            float s = DeviceDpi / 96f;
            if (hover && Switch.Enabled)
            {
                g.SmoothingMode = SmoothingMode.AntiAlias;
                using (var path = Theme.Round(new RectangleF(4 * s, 2 * s, Width - 8 * s, Height - 4 * s), 6 * s))
                using (var b = new SolidBrush(Theme.SurfaceHover))
                    g.FillPath(b, path);
            }
            float a = Switch.Enabled ? 1f : 0.5f;
            int left = (int)(16 * s), right = Switch.Left - (int)(12 * s);
            int th = titleFont.Height, dh = detailFont.Height, top = (Height - th - dh - (int)(2 * s)) / 2;
            var flags = TextFormatFlags.Left | TextFormatFlags.SingleLine | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix;
            TextRenderer.DrawText(g, title, titleFont, new Rectangle(left, top, right - left, th), Theme.Fade(Theme.Text, a), flags);
            TextRenderer.DrawText(g, detail, detailFont, new Rectangle(left, top + th + (int)(2 * s), right - left, dh), Theme.Fade(Theme.Muted, a), flags);
            base.OnPaint(e);                            // raises Paint: the group draws the divider
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing) { titleFont.Dispose(); detailFont.Dispose(); }
            base.Dispose(disposing);
        }
    }

    /// <summary>A group of rows on one rounded surface, with hairlines between them.</summary>
    internal sealed class OptionGroup : Panel
    {
        public OptionGroup()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            BackColor = Theme.Surface;
            Padding = new Padding(1, 4, 1, 4);
            Dock = DockStyle.Top;
        }

        public OptionRow Add(OptionRow row)
        {
            Controls.Add(row);
            row.BringToFront();                         // Dock=Top: the last child in the collection docks first
            Height = Padding.Vertical;
            foreach (Control c in Controls) Height += c.Height;
            return row;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.Clear(Parent != null ? Parent.BackColor : Theme.Bg);
            g.SmoothingMode = SmoothingMode.AntiAlias;
            float s = DeviceDpi / 96f;
            using (var path = Theme.Round(new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f), 10 * s))
            {
                using (var b = new SolidBrush(Theme.Surface)) g.FillPath(b, path);
                using (var p = new Pen(Theme.Line)) g.DrawPath(p, path);
            }
        }

        protected override void OnPaintBackground(PaintEventArgs e) { }

        protected override void OnControlAdded(ControlEventArgs e)
        {
            base.OnControlAdded(e);
            e.Control.Paint += PaintDivider;
        }

        private void PaintDivider(object sender, PaintEventArgs e)
        {
            var row = (Control)sender;
            if (row.Bottom >= Height - Padding.Bottom - 1) return;    // no line under the last row
            float s = DeviceDpi / 96f;
            using (var p = new Pen(Theme.Line))
                e.Graphics.DrawLine(p, 16 * s, row.Height - 1, row.Width - 16 * s, row.Height - 1);
        }
    }

    /// <summary>A small rounded label with a coloured dot: the state of this PC at a glance.</summary>
    internal sealed class StatePill : Control
    {
        private Color dot = Theme.Muted;

        public StatePill()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            Font = Theme.Ui(9f);
            Height = 28;
        }

        public void Set(string text, Color dotColor)
        {
            Text = text;
            AccessibleName = text;
            dot = dotColor;
            Width = TextRenderer.MeasureText(text, Font).Width + (int)(34 * DeviceDpi / 96f);
            Invalidate();
            if (Parent != null) Parent.PerformLayout();
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.Clear(Parent != null ? Parent.BackColor : Theme.Bg);
            g.SmoothingMode = SmoothingMode.AntiAlias;
            float s = DeviceDpi / 96f;
            var r = new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f);
            using (var path = Theme.Round(r, r.Height / 2))
            {
                using (var b = new SolidBrush(Theme.Surface)) g.FillPath(b, path);
                using (var p = new Pen(Theme.Line)) g.DrawPath(p, path);
            }
            float d = 8 * s;
            using (var b = new SolidBrush(dot)) g.FillEllipse(b, 12 * s, (Height - d) / 2, d, d);
            TextRenderer.DrawText(g, Text, Font, new Rectangle((int)(26 * s), 0, Width - (int)(32 * s), Height), Theme.Text,
                TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine | TextFormatFlags.NoPrefix);
        }
    }

    /// <summary>Hairline under the header. While a script runs, a short segment travels along it.</summary>
    internal sealed class ActivityLine : Control
    {
        private readonly Timer timer = new Timer { Interval = 16 };
        private float phase;
        private bool busy;

        public ActivityLine()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer, true);
            Height = 2;
            Dock = DockStyle.Top;
            timer.Tick += (s, e) => { phase = (phase + 0.012f) % 1.4f; Invalidate(); };
        }

        public bool Busy
        {
            get { return busy; }
            set
            {
                busy = value;
                phase = 0;
                if (busy && Theme.AnimationsOn) timer.Start(); else timer.Stop();
                Invalidate();
            }
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.Clear(Theme.Line);
            if (!busy) return;
            if (!timer.Enabled) { using (var b = new SolidBrush(Theme.Accent)) g.FillRectangle(b, ClientRectangle); return; }
            float w = Width * 0.35f, x = (phase - 0.35f) * Width;
            var r = new RectangleF(x, 0, w, Height);
            using (var b = new LinearGradientBrush(new RectangleF(x - 1, 0, w + 2, Height), Theme.Line, Theme.Accent, 0f))
            {
                var blend = new ColorBlend
                {
                    Colors = new[] { Theme.Line, Theme.Accent, Theme.Accent, Theme.Line },
                    Positions = new[] { 0f, 0.4f, 0.6f, 1f }
                };
                b.InterpolationColors = blend;
                g.FillRectangle(b, r);
            }
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing) timer.Dispose();
            base.Dispose(disposing);
        }
    }

    /// <summary>Rounded frame for the log.</summary>
    internal sealed class LogFrame : Panel
    {
        public LogFrame()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            BackColor = Theme.LogBg;
            Padding = new Padding(14, 12, 6, 10);
        }

        protected override void OnPaintBackground(PaintEventArgs e) { }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.Clear(Parent != null ? Parent.BackColor : Theme.Bg);
            g.SmoothingMode = SmoothingMode.AntiAlias;
            float s = DeviceDpi / 96f;
            using (var path = Theme.Round(new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f), 10 * s))
            {
                using (var b = new SolidBrush(Theme.LogBg)) g.FillPath(b, path);
                using (var p = new Pen(Theme.Line)) g.DrawPath(p, path);
            }
        }
    }

    /// <summary>Header: mark, name, one line on what it does, and the state pills on the right.</summary>
    internal sealed class Header : Panel
    {
        public readonly StatePill RunState = new StatePill(), GuardState = new StatePill();
        private readonly Font titleFont = Theme.Display(17f), subFont = Theme.Ui(9.75f);

        public Header()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            BackColor = Theme.Bg;
            Dock = DockStyle.Top;
            Height = 78;
            Controls.Add(RunState);
            Controls.Add(GuardState);
        }

        protected override void OnLayout(LayoutEventArgs e)
        {
            base.OnLayout(e);
            if (RunState == null || GuardState == null) return;
            int s8 = (int)(8 * DeviceDpi / 96f), right = Width - (int)(22 * DeviceDpi / 96f);
            int y = (Height - RunState.Height) / 2;
            GuardState.Location = new Point(right - GuardState.Width, y);
            RunState.Location = new Point(GuardState.Left - s8 - RunState.Width, y);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.Clear(Theme.Bg);
            float s = DeviceDpi / 96f;
            float m = 40 * s;
            Theme.DrawMark(g, new RectangleF(22 * s, (Height - m) / 2, m, m));
            int x = (int)(76 * s);
            int top = (Height - titleFont.Height - subFont.Height) / 2 - (int)(1 * s);
            var flags = TextFormatFlags.Left | TextFormatFlags.SingleLine | TextFormatFlags.NoPrefix;
            TextRenderer.DrawText(g, "Windows 11 Debloat", titleFont, new Point(x - (int)(2 * s), top), Theme.Text, flags);
            TextRenderer.DrawText(g, "Reklamsız, sessiz ve hızlı bir Windows. Yapılan her şey geri alınabilir.", subFont,
                new Point(x, top + titleFont.Height), Theme.Muted, flags);
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing) { titleFont.Dispose(); subFont.Dispose(); }
            base.Dispose(disposing);
        }
    }
}
