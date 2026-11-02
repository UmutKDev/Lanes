using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Lanes.Core;

namespace Lanes.App;

/// <summary>The account list: open, Claude Code, edit, reorder and delete.</summary>
sealed class MainWindow : Window
{
    readonly AppController controller;
    readonly StackPanel list = new();
    readonly StackPanel notices = new();

    public MainWindow(AppController controller)
    {
        this.controller = controller;
        Title = "Lanes";
        Width = 560;
        Height = 600;
        MinWidth = 440;
        MinHeight = 320;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Background = Brushes.White;
        FontFamily = new FontFamily("Segoe UI Variable Text, Segoe UI");
        Icon = System.Windows.Media.Imaging.BitmapFrame.Create(new Uri("pack://application:,,,/Assets/Lanes.ico"));

        var header = new DockPanel { Margin = new Thickness(20, 18, 20, 10) };
        var add = Ui.Button(L.T("AddAccount"), AddAccount, primary: true);
        DockPanel.SetDock(add, Dock.Right);
        header.Children.Add(add);
        header.Children.Add(Ui.Text(L.T("Accounts"), 22, FontWeights.SemiBold));

        var root = new DockPanel();
        DockPanel.SetDock(header, Dock.Top);
        root.Children.Add(header);
        DockPanel.SetDock(notices, Dock.Top);
        notices.Margin = new Thickness(20, 0, 20, 0);
        root.Children.Add(notices);
        root.Children.Add(new ScrollViewer
        {
            Content = list,
            Padding = new Thickness(20, 4, 20, 20),
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
        });
        Content = root;

        controller.Changed += Rebuild;
        Closed += (_, _) => controller.Changed -= Rebuild;
        Rebuild();
    }

    void Rebuild()
    {
        BuildNotices();
        list.Children.Clear();
        var profiles = controller.Library.ActiveProfiles.ToList();
        if (profiles.Count == 0) list.Children.Add(Ui.Text(L.T("Empty"), 13, brush: (Brush)FindResource("Subtle")));
        for (var i = 0; i < profiles.Count; i++) list.Children.Add(Row(profiles[i], i, profiles.Count));
    }

    void BuildNotices()
    {
        notices.Children.Clear();
        switch (controller.Installation)
        {
            case ClaudeInstallation.Missing:
                notices.Children.Add(Notice(L.T("ClaudeMissingTitle"), L.T("ClaudeMissingBody")));
                break;
            case ClaudeInstallation.StorePackage:
                notices.Children.Add(Notice(L.T("StoreTitle"), L.T("StoreBody")));
                break;
        }
        if (controller.LoadError != null)
            notices.Children.Add(Notice("profiles.json", controller.LoadError, withButtons: false));
    }

    Border Notice(string title, string body, bool withButtons = true)
    {
        var panel = new StackPanel();
        panel.Children.Add(Ui.Text(title, 14, FontWeights.SemiBold));
        panel.Children.Add(new Border { Height = 4 });
        panel.Children.Add(Ui.Text(body));
        if (withButtons)
        {
            var buttons = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(-6, 10, 0, 0) };
            buttons.Children.Add(Ui.Button(L.T("Download"), () => Process.Start(new ProcessStartInfo("https://claude.ai/download") { UseShellExecute = true })?.Dispose(), primary: true));
            buttons.Children.Add(Ui.Button(L.T("Recheck"), controller.RecheckInstallation));
            panel.Children.Add(buttons);
        }
        return new Border
        {
            Child = panel,
            Padding = new Thickness(14),
            Margin = new Thickness(0, 0, 0, 12),
            CornerRadius = new CornerRadius(8),
            Background = new SolidColorBrush(Color.FromRgb(0xFF, 0xF4, 0xE5)),
            BorderBrush = new SolidColorBrush(Color.FromRgb(0xF5, 0xC2, 0x7A)),
            BorderThickness = new Thickness(1),
        };
    }

    Border Row(Profile profile, int index, int count)
    {
        var running = controller.IsRunning(profile);
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        var badge = Ui.Badge(profile, 40);
        badge.Margin = new Thickness(0, 0, 14, 0);
        grid.Children.Add(badge);

        var texts = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        texts.Children.Add(Ui.Text(profile.Name, 15, FontWeights.SemiBold));
        var detail = profile.IsDefault ? L.T("MainAccountHint") : profile.Email ?? profile.Note ?? "";
        var status = running ? L.T("Running") : L.T("NotRunning");
        texts.Children.Add(Ui.Text(string.IsNullOrEmpty(detail) ? status : $"{status} · {detail}", 12, brush: running ? Ui.Brush(ProfileColor.Green) : (Brush)FindResource("Subtle")));
        Grid.SetColumn(texts, 1);
        grid.Children.Add(texts);

        var buttons = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        buttons.Children.Add(Ui.Button(running ? L.T("BringForward") : L.T("Open"), () => controller.Open(profile), primary: true));
        buttons.Children.Add(Ui.Button(L.T("ClaudeCode"), () => controller.OpenClaudeCode(profile)));
        var more = new Button { Content = "…", MinWidth = 34, Margin = new Thickness(6, 0, 0, 0) };
        more.Click += (_, _) => MoreMenu(profile, index, count, more);
        buttons.Children.Add(more);
        Grid.SetColumn(buttons, 2);
        grid.Children.Add(buttons);

        return new Border
        {
            Child = grid,
            Padding = new Thickness(14, 12, 14, 12),
            Margin = new Thickness(0, 0, 0, 10),
            CornerRadius = new CornerRadius(10),
            Background = (Brush)FindResource("CardBackground"),
            BorderBrush = running ? Ui.Brush(profile.Color) : (Brush)FindResource("CardBorder"),
            BorderThickness = new Thickness(running ? 2 : 1),
        };
    }

    void MoreMenu(Profile profile, int index, int count, Button anchor)
    {
        var menu = new ContextMenu { PlacementTarget = anchor };
        MenuItem Item(string title, Action action, bool enabled = true)
        {
            var item = new MenuItem { Header = title, IsEnabled = enabled };
            item.Click += (_, _) => action();
            menu.Items.Add(item);
            return item;
        }
        Item(L.T("Edit"), () => EditAccount(profile));
        Item(L.T("OpenFolder"), () => controller.ShowFolder(profile));
        menu.Items.Add(new Separator());
        Item(L.T("MoveUp"), () => controller.Move(profile, -1), index > 0);
        Item(L.T("MoveDown"), () => controller.Move(profile, 1), index < count - 1);
        if (!profile.IsDefault)
        {
            menu.Items.Add(new Separator());
            Item(L.T("Delete"), () => DeleteAccount(profile));
        }
        menu.IsOpen = true;
    }

    void AddAccount()
    {
        var profile = Profile.Create(L.T("NewAccountName"), ProfileColors.NextFree(controller.Library.Profiles.Select(p => p.Color)));
        var editor = new AccountEditor(profile, isNew: true) { Owner = this };
        if (editor.ShowDialog() == true)
        {
            controller.Add(editor.Result);
            controller.Open(editor.Result);
        }
    }

    void EditAccount(Profile profile)
    {
        var editor = new AccountEditor(profile.Clone(), isNew: false) { Owner = this };
        if (editor.ShowDialog() == true) controller.Update(editor.Result);
    }

    void DeleteAccount(Profile profile)
    {
        if (controller.IsRunning(profile))
        {
            MessageBox.Show(this, L.T("CloseFirst"), "Lanes", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        var answer = MessageBox.Show(this, L.T("DeleteBody"), L.F("DeleteTitle", profile.Name), MessageBoxButton.OKCancel, MessageBoxImage.Warning, MessageBoxResult.Cancel);
        if (answer == MessageBoxResult.OK) controller.Delete(profile);
    }
}
