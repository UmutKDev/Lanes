using Lanes.App.Platform;
using Lanes.Core;
using Forms = System.Windows.Forms;

namespace Lanes.App;

/// <summary>Lanes' icon in the notification area, with every account one click away.</summary>
sealed class TrayIcon : IDisposable
{
    readonly AppController controller;
    readonly Forms.NotifyIcon icon;
    readonly Action showWindow;
    readonly Action quit;

    public TrayIcon(AppController controller, Action showWindow, Action quit)
    {
        this.controller = controller;
        this.showWindow = showWindow;
        this.quit = quit;
        var stream = System.Windows.Application.GetResourceStream(new Uri("pack://application:,,,/Assets/Lanes.ico"))!.Stream;
        icon = new Forms.NotifyIcon
        {
            Icon = new System.Drawing.Icon(stream, Forms.SystemInformation.SmallIconSize),
            Text = "Lanes",
            Visible = true,
            ContextMenuStrip = new Forms.ContextMenuStrip(),
        };
        icon.MouseClick += (_, e) => { if (e.Button == Forms.MouseButtons.Left) showWindow(); };
        icon.ContextMenuStrip.Opening += (_, _) => Rebuild();
        controller.Changed += UpdateTip;
        Rebuild();
        UpdateTip();
    }

    void UpdateTip()
    {
        var text = L.F("TrayTip", controller.Running.Select(r => r.ProfileId).Distinct().Count());
        icon.Text = text.Length > 63 ? text[..63] : text;
    }

    void Rebuild()
    {
        var menu = icon.ContextMenuStrip!;
        foreach (var item in menu.Items.OfType<Forms.ToolStripItem>().ToList()) { menu.Items.Remove(item); item.Dispose(); }
        foreach (var profile in controller.Library.ActiveProfiles)
        {
            var running = controller.IsRunning(profile);
            var item = new Forms.ToolStripMenuItem(profile.Name, IconFactory.Draw(profile.Color, profile.Monogram, 16), (_, _) => controller.Open(profile))
            {
                Font = running ? new System.Drawing.Font(menu.Font, System.Drawing.FontStyle.Bold) : menu.Font,
                ShortcutKeyDisplayString = running ? L.T("Running") : "",
                ToolTipText = profile.Email,
            };
            menu.Items.Add(item);
        }
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add(L.T("ShowLanes"), null, (_, _) => showWindow());
        var startup = new Forms.ToolStripMenuItem(L.T("StartWithWindows")) { Checked = StartupEntry.IsEnabled };
        startup.Click += (_, _) => StartupEntry.Set(!StartupEntry.IsEnabled);
        menu.Items.Add(startup);
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add(L.T("Quit"), null, (_, _) => quit());
    }

    public void Dispose()
    {
        controller.Changed -= UpdateTip;
        icon.Visible = false;
        icon.Dispose();
    }
}
