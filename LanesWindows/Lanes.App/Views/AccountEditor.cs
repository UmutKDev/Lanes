using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using Lanes.Core;

namespace Lanes.App;

/// <summary>Name, colour, letter, email, note and Claude Code folder of one account.</summary>
sealed class AccountEditor : Window
{
    public Profile Result { get; }

    readonly TextBox name = new() { Padding = new Thickness(4) };
    readonly TextBox monogram = new() { Padding = new Thickness(4), Width = 48, MaxLength = 2, HorizontalAlignment = HorizontalAlignment.Left };
    readonly TextBox email = new() { Padding = new Thickness(4) };
    readonly TextBox note = new() { Padding = new Thickness(4) };
    readonly TextBlock folder = new() { VerticalAlignment = VerticalAlignment.Center, TextTrimming = TextTrimming.CharacterEllipsis };
    readonly WrapPanel colors = new();
    string? chosenFolder;
    bool monogramFollowsName;

    public AccountEditor(Profile profile, bool isNew)
    {
        Result = profile;
        Title = isNew ? L.T("NewAccount") : L.T("EditAccount");
        Width = 440;
        SizeToContent = SizeToContent.Height;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        ShowInTaskbar = false;
        FontFamily = new FontFamily("Segoe UI Variable Text, Segoe UI");

        name.Text = profile.Name;
        monogram.Text = profile.Monogram;
        email.Text = profile.Email ?? "";
        note.Text = profile.Note ?? "";
        chosenFolder = profile.DefaultProjectFolder;
        monogramFollowsName = profile.Monogram == Profile.DefaultMonogram(profile.Name);
        name.TextChanged += (_, _) => { if (monogramFollowsName) monogram.Text = Profile.DefaultMonogram(name.Text); };
        monogram.TextChanged += (_, _) => { if (monogram.IsKeyboardFocused) monogramFollowsName = false; };

        foreach (var color in Enum.GetValues<ProfileColor>())
        {
            var swatch = new RadioButton
            {
                GroupName = "color",
                IsChecked = color == profile.Color,
                Tag = color,
                Margin = new Thickness(0, 0, 6, 6),
                ToolTip = color.ToString(),
                Template = SwatchTemplate(Ui.Brush(color)),
            };
            colors.Children.Add(swatch);
        }

        var form = new StackPanel { Margin = new Thickness(20) };
        void Field(string label, UIElement control, string? hint = null)
        {
            form.Children.Add(Ui.Text(label, 12, FontWeights.SemiBold));
            if (control is FrameworkElement fe) fe.Margin = new Thickness(0, 4, 0, hint == null ? 12 : 2);
            form.Children.Add(control);
            if (hint != null)
            {
                var h = Ui.Text(hint, 11, brush: (Brush)Application.Current.FindResource("Subtle"));
                h.Margin = new Thickness(0, 0, 0, 12);
                form.Children.Add(h);
            }
        }
        Field(L.T("Name"), name);
        Field(L.T("Color"), colors);
        Field(L.T("Letter"), monogram);
        Field(L.T("Email"), email, L.T("EmailHint"));
        Field(L.T("Note"), note);

        var folderRow = new DockPanel();
        var clear = Ui.Button(L.T("Clear"), () => { chosenFolder = null; UpdateFolder(); });
        var choose = Ui.Button(L.T("Choose"), ChooseFolder);
        DockPanel.SetDock(clear, Dock.Right);
        DockPanel.SetDock(choose, Dock.Right);
        folderRow.Children.Add(clear);
        folderRow.Children.Add(choose);
        folderRow.Children.Add(folder);
        Field(L.T("CodeFolder"), folderRow);
        UpdateFolder();

        if (isNew)
        {
            var hint = Ui.Text(L.T("SignInHint"), 11, brush: (Brush)Application.Current.FindResource("Subtle"));
            hint.Margin = new Thickness(0, 0, 0, 12);
            form.Children.Add(hint);
        }

        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 8, 0, 0) };
        var cancel = Ui.Button(L.T("Cancel"), () => DialogResult = false);
        cancel.IsCancel = true;
        var save = Ui.Button(L.T("Save"), SaveAndClose, primary: true);
        save.IsDefault = true;
        buttons.Children.Add(cancel);
        buttons.Children.Add(save);
        form.Children.Add(buttons);
        Content = form;
        Loaded += (_, _) => { name.Focus(); name.SelectAll(); };
    }

    static ControlTemplate SwatchTemplate(Brush fill)
    {
        var template = new ControlTemplate(typeof(RadioButton));
        var outer = new FrameworkElementFactory(typeof(Border));
        outer.SetValue(Border.WidthProperty, 26.0);
        outer.SetValue(Border.HeightProperty, 26.0);
        outer.SetValue(Border.CornerRadiusProperty, new CornerRadius(13));
        outer.SetValue(Border.BorderThicknessProperty, new Thickness(2));
        outer.SetValue(Border.BorderBrushProperty, Brushes.Transparent);
        outer.Name = "ring";
        var inner = new FrameworkElementFactory(typeof(Border));
        inner.SetValue(Border.MarginProperty, new Thickness(2));
        inner.SetValue(Border.CornerRadiusProperty, new CornerRadius(9));
        inner.SetValue(Border.BackgroundProperty, fill);
        outer.AppendChild(inner);
        template.VisualTree = outer;
        var trigger = new Trigger { Property = ToggleButton.IsCheckedProperty, Value = true };
        trigger.Setters.Add(new Setter(Border.BorderBrushProperty, Brushes.Black, "ring"));
        template.Triggers.Add(trigger);
        return template;
    }

    void UpdateFolder() => folder.Text = chosenFolder ?? L.T("HomeFolder");

    void ChooseFolder()
    {
        var dialog = new Microsoft.Win32.OpenFolderDialog { InitialDirectory = chosenFolder ?? Environment.GetFolderPath(Environment.SpecialFolder.UserProfile) };
        if (dialog.ShowDialog(this) == true)
        {
            chosenFolder = dialog.FolderName;
            UpdateFolder();
        }
    }

    void SaveAndClose()
    {
        var newName = name.Text.Trim();
        if (newName.Length == 0) { name.Focus(); return; }
        Result.Name = newName;
        var letter = monogram.Text.Trim();
        Result.Monogram = letter.Length == 0 ? Profile.DefaultMonogram(newName) : letter;
        Result.Email = string.IsNullOrWhiteSpace(email.Text) ? null : email.Text.Trim();
        Result.Note = string.IsNullOrWhiteSpace(note.Text) ? null : note.Text.Trim();
        Result.DefaultProjectFolder = chosenFolder;
        Result.Color = colors.Children.OfType<RadioButton>().FirstOrDefault(r => r.IsChecked == true)?.Tag is ProfileColor c ? c : Result.Color;
        DialogResult = true;
    }
}
