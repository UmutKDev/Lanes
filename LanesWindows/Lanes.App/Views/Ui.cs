using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Lanes.App.Platform;
using Lanes.Core;

namespace Lanes.App;

/// <summary>Small helpers for building the windows in code.</summary>
static class Ui
{
    public static SolidColorBrush Brush(ProfileColor color)
    {
        var (r, g, b) = ProfileColors.Rgb(color);
        return new SolidColorBrush(Color.FromRgb(r, g, b));
    }

    public static Image Badge(Profile profile, int size)
    {
        using var bitmap = IconFactory.Draw(profile.Color, profile.Monogram, size * 2);
        var source = System.Windows.Interop.Imaging.CreateBitmapSourceFromHBitmap(
            bitmap.GetHbitmap(System.Drawing.Color.Transparent), IntPtr.Zero, Int32Rect.Empty, BitmapSizeOptions.FromEmptyOptions());
        return new Image { Source = source, Width = size, Height = size };
    }

    public static TextBlock Text(string text, double size = 13, FontWeight? weight = null, Brush? brush = null) => new()
    {
        Text = text,
        FontSize = size,
        FontWeight = weight ?? FontWeights.Normal,
        Foreground = brush ?? Brushes.Black,
        TextWrapping = TextWrapping.Wrap,
    };

    public static Button Button(string title, Action action, bool primary = false)
    {
        var button = new Button { Content = title, Margin = new Thickness(6, 0, 0, 0), IsDefault = false };
        if (primary) button.FontWeight = FontWeights.SemiBold;
        button.Click += (_, _) => action();
        return button;
    }
}
