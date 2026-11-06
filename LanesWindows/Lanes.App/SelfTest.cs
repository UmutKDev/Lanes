using System.Text.Json;
using Lanes.App.Platform;
using Lanes.Core;

namespace Lanes.App;

/// <summary>
/// <c>Lanes.exe --self-test &lt;folder&gt;</c>: opens three accounts with the
/// real code paths, checks each Claude window got its own taskbar identity,
/// and writes a report and a screenshot to the folder. CI runs it on Windows
/// with the real Claude app.
/// </summary>
static class SelfTest
{
    public static async Task<int> Run(string outDir)
    {
        Directory.CreateDirectory(outDir);
        var log = new List<string>();
        void Log(string line) { log.Add($"{DateTime.Now:HH:mm:ss} {line}"); File.WriteAllLines(Path.Combine(outDir, "selftest.log"), log); }
        try
        {
            var standard = ProfilePaths.Standard();
            var paths = standard with { Root = Path.Combine(outDir, "LanesRoot") };
            var controller = new AppController(paths);
            controller.Start();
            Log($"Installation: {controller.Installation}");
            if (controller.Installation is not ClaudeInstallation.Standard) return 2;

            var work = Profile.Create("İş", ProfileColor.Red);
            var client = Profile.Create("Müşteri", ProfileColor.Green);
            controller.Add(work);
            controller.Add(client);
            var main = controller.Library.DefaultProfile!;
            Log($"Accounts: {string.Join(", ", controller.Library.Profiles.Select(p => $"{p.Name}={p.Id}"))}");

            foreach (var profile in controller.Library.Profiles)
            {
                controller.Open(profile);
                Log($"Opened {profile.Name}");
                await Task.Delay(TimeSpan.FromSeconds(12));
            }
            await WaitFor(() => controller.Library.Profiles.All(p => WindowsOf(controller, p).Count > 0), TimeSpan.FromSeconds(60));
            controller.Refresh();
            await Task.Delay(TimeSpan.FromSeconds(3));

            var pidsBefore = controller.Running.Select(r => r.Pid).ToHashSet();
            controller.Open(work);
            await Task.Delay(TimeSpan.FromSeconds(8));
            controller.Refresh();
            var reopenedMakesNoNewCopy = controller.Running.Count(r => r.ProfileId == work.Id) == 1
                && controller.Running.Select(r => r.Pid).ToHashSet().SetEquals(pidsBefore);
            Log($"Reopen keeps one copy: {reopenedMakesNoNewCopy}");

            var accounts = new List<object>();
            var ok = reopenedMakesNoNewCopy;
            var seenIds = new HashSet<string>();
            foreach (var profile in controller.Library.Profiles)
            {
                var expected = TaskbarIdentity.For(profile, Environment.ProcessPath!, paths.IconFile(profile)).AppUserModelId;
                var windows = WindowsOf(controller, profile).Select(h => new
                {
                    Title = Native.WindowText(h),
                    Class = Native.ClassName(h),
                    AppId = TaskbarStamp.ReadAppId(h),
                    HasIcon = Native.SendMessage(h, Native.WM_GETICON, Native.ICON_BIG, IntPtr.Zero) != IntPtr.Zero,
                }).ToList();
                var dataDir = paths.EffectiveDesktopDataDirectory(profile);
                var entries = Directory.Exists(dataDir) ? Directory.GetFileSystemEntries(dataDir).Length : 0;
                var good = windows.Count > 0 && windows.All(w => w.AppId == expected && w.HasIcon) && File.Exists(paths.IconFile(profile)) && entries > 0;
                ok &= good && seenIds.Add(expected);
                accounts.Add(new { profile.Name, profile.Id, Expected = expected, Windows = windows, DataDirectory = dataDir, DataEntries = entries, IconFile = File.Exists(paths.IconFile(profile)), Good = good });
                Log($"{profile.Name}: windows={windows.Count} good={good}");
            }

            Screenshot(outDir);
            File.WriteAllText(Path.Combine(outDir, "report.json"), JsonSerializer.Serialize(new
            {
                Ok = ok,
                ReopenKeepsOneCopy = reopenedMakesNoNewCopy,
                Running = controller.Running,
                Accounts = accounts,
                ClaudeCodeScript = ClaudeCodeCommand.PowerShellScript(work, paths, null),
            }, new JsonSerializerOptions { WriteIndented = true }));
            Log(ok ? "PASS" : "FAIL");
            return ok ? 0 : 1;
        }
        catch (Exception e)
        {
            Log("ERROR " + e);
            return 3;
        }
    }

    static List<IntPtr> WindowsOf(AppController controller, Profile profile) =>
        controller.Running.Where(r => r.ProfileId == profile.Id).SelectMany(r => Native.TopLevelWindows(r.Pid)).ToList();

    static async Task WaitFor(Func<bool> condition, TimeSpan timeout)
    {
        var end = DateTime.Now + timeout;
        while (!condition() && DateTime.Now < end) await Task.Delay(1000);
    }

    static void Screenshot(string outDir)
    {
        var bounds = System.Windows.Forms.Screen.PrimaryScreen!.Bounds;
        using var bitmap = new System.Drawing.Bitmap(bounds.Width, bounds.Height);
        using (var g = System.Drawing.Graphics.FromImage(bitmap)) g.CopyFromScreen(bounds.Location, System.Drawing.Point.Empty, bounds.Size);
        bitmap.Save(Path.Combine(outDir, "screen.png"), System.Drawing.Imaging.ImageFormat.Png);
        var bar = new System.Drawing.Rectangle(0, Math.Max(0, bounds.Height - 64), bounds.Width, Math.Min(64, bounds.Height));
        using var taskbar = bitmap.Clone(bar, bitmap.PixelFormat);
        taskbar.Save(Path.Combine(outDir, "taskbar.png"), System.Drawing.Imaging.ImageFormat.Png);
    }
}
