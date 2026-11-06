using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using Lanes.Core;

namespace Lanes.App.Platform;

/// <summary>Draws each account's icon: a rounded square in its colour with its letter.</summary>
static class IconFactory
{
    static readonly int[] Sizes = [16, 20, 24, 32, 40, 48, 64, 256];

    public static Bitmap Draw(ProfileColor color, string monogram, int size)
    {
        var bitmap = new Bitmap(size, size, PixelFormat.Format32bppArgb);
        using var g = Graphics.FromImage(bitmap);
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
        g.Clear(Color.Transparent);
        var (r, gr, b) = ProfileColors.Rgb(color);
        var inset = size >= 32 ? size / 16f : 0.5f;
        var rect = new RectangleF(inset, inset, size - 2 * inset, size - 2 * inset);
        var radius = rect.Width * 0.24f;
        using (var path = RoundedRect(rect, radius))
        using (var fill = new LinearGradientBrush(rect, Lighten(Color.FromArgb(r, gr, b), 0.12f), Color.FromArgb(r, gr, b), 90f))
        {
            g.FillPath(fill, path);
        }
        var text = ProfileColors.PrefersDarkText(color) ? Color.FromArgb(230, 20, 20, 20) : Color.White;
        using var font = new Font("Segoe UI Semibold", rect.Height * 0.52f, FontStyle.Bold, GraphicsUnit.Pixel);
        using var brush = new SolidBrush(text);
        var format = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center };
        var textRect = rect with { Y = rect.Y + rect.Height * 0.02f };
        g.DrawString(monogram, font, brush, textRect, format);
        return bitmap;
    }

    /// <summary>Writes the icon file if it is not there yet. The file name carries colour and letter, so a change makes a new file.</summary>
    public static string Ensure(Profile profile, ProfilePaths paths)
    {
        var file = paths.IconFile(profile);
        if (File.Exists(file)) return file;
        Directory.CreateDirectory(paths.IconsDirectory);
        foreach (var old in Directory.GetFiles(paths.IconsDirectory, profile.Id + "-*.ico"))
        {
            try { File.Delete(old); } catch (IOException) { /* still in use by a window; left for next time */ }
        }
        WriteIco(file, Sizes.Select(s => Draw(profile.Color, profile.Monogram, s)).ToList());
        return file;
    }

    static void WriteIco(string file, List<Bitmap> images)
    {
        var pngs = images.Select(image =>
        {
            using var ms = new MemoryStream();
            image.Save(ms, ImageFormat.Png);
            image.Dispose();
            return ms.ToArray();
        }).ToList();
        using var stream = File.Create(file + ".tmp");
        using (var w = new BinaryWriter(stream))
        {
            w.Write((short)0); w.Write((short)1); w.Write((short)pngs.Count);
            var offset = 6 + 16 * pngs.Count;
            for (var i = 0; i < pngs.Count; i++)
            {
                var size = Sizes[i];
                w.Write((byte)(size >= 256 ? 0 : size)); w.Write((byte)(size >= 256 ? 0 : size));
                w.Write((byte)0); w.Write((byte)0);
                w.Write((short)1); w.Write((short)32);
                w.Write(pngs[i].Length); w.Write(offset);
                offset += pngs[i].Length;
            }
            foreach (var png in pngs) w.Write(png);
        }
        File.Move(file + ".tmp", file, overwrite: true);
    }

    static GraphicsPath RoundedRect(RectangleF r, float radius)
    {
        var d = radius * 2;
        var path = new GraphicsPath();
        path.AddArc(r.X, r.Y, d, d, 180, 90);
        path.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        path.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        path.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        path.CloseFigure();
        return path;
    }

    static Color Lighten(Color c, float amount) => Color.FromArgb(
        c.R + (int)((255 - c.R) * amount), c.G + (int)((255 - c.G) * amount), c.B + (int)((255 - c.B) * amount));
}
