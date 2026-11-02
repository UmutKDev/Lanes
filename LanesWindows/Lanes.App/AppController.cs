using System.Diagnostics;
using System.Windows.Threading;
using Lanes.App.Platform;
using Lanes.Core;

namespace Lanes.App;

/// <summary>
/// Lanes' state: the account list, which accounts are running, and the
/// actions on them. Every few seconds it looks for Claude windows and gives
/// each its account's taskbar identity.
/// </summary>
sealed class AppController
{
    public ProfilePaths Paths { get; }
    public ProfileStore Store { get; }
    public ProfileLibrary Library { get; private set; } = new();
    public ClaudeInstallation Installation { get; private set; } = new ClaudeInstallation.Missing();
    public IReadOnlyList<RunningInstance> Running { get; private set; } = [];
    public string? LoadError { get; private set; }

    public event Action? Changed;

    readonly TaskbarStamp stamp = new();
    readonly DispatcherTimer timer;
    readonly string lanesExecutable = Environment.ProcessPath!;

    public AppController(ProfilePaths paths)
    {
        Paths = paths;
        Store = new ProfileStore(paths.ProfilesFile);
        timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(2) };
        timer.Tick += (_, _) => Refresh();
    }

    public void Start()
    {
        Load();
        Installation = ClaudeProcesses.DetectInstallation();
        Refresh();
        timer.Start();
    }

    void Load()
    {
        try
        {
            Library = Store.Load();
        }
        catch (Exception e) when (e is System.Text.Json.JsonException or ProfileStoreException)
        {
            LoadError = e.Message;
            Library = new ProfileLibrary();
        }
        if (Library.EnsureDefaultProfile(L.T("MainAccount"))) Save();
    }

    public void Save()
    {
        Store.Save(Library);
        Changed?.Invoke();
    }

    public void RecheckInstallation()
    {
        Installation = ClaudeProcesses.DetectInstallation();
        Changed?.Invoke();
    }

    public bool IsRunning(Profile profile) => Running.Any(r => r.ProfileId == profile.Id);

    /// <summary>Looks for running Claude copies and stamps their windows.</summary>
    public void Refresh()
    {
        var running = ClaudeInstances.Match(ClaudeProcesses.List(), Library, Paths);
        foreach (var instance in running)
        {
            if (Library.Find(instance.ProfileId) is not { } profile) continue;
            var identity = TaskbarIdentity.For(profile, lanesExecutable, IconFactory.Ensure(profile, Paths));
            foreach (var hwnd in Native.TopLevelWindows(instance.Pid))
            {
                try { stamp.Apply(hwnd, identity); }
                catch (Exception e) { Trace.WriteLine($"Taskbar stamp failed for {instance.Pid}: {e.Message}"); }
            }
        }
        var changed = !running.SequenceEqual(Running);
        Running = running;
        if (changed) Changed?.Invoke();
    }

    /// <summary>Brings the account's Claude forward, or starts it.</summary>
    public void Open(Profile profile)
    {
        if (Installation is not ClaudeInstallation.Standard standard)
        {
            RecheckInstallation();
            if (Installation is not ClaudeInstallation.Standard again) return;
            standard = again;
        }
        var instance = Running.FirstOrDefault(r => r.ProfileId == profile.Id);
        if (instance != null)
        {
            var window = Native.TopLevelWindows(instance.Pid).FirstOrDefault();
            if (window != IntPtr.Zero)
            {
                Native.BringForward(window);
                return;
            }
            // Closed to the notification area: starting it again with the
            // same folder makes the running copy show its window.
        }
        Native.AllowSetForegroundWindow(Native.ASFW_ANY);
        ClaudeProcesses.Start(LaunchPlanner.Plan(profile, standard.LauncherPath, Paths));
        // The window shows up a moment later; stamp it soon instead of waiting a full tick.
        var soon = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(700) };
        var tries = 0;
        soon.Tick += (_, _) => { Refresh(); if (++tries >= 10) soon.Stop(); };
        soon.Start();
    }

    public void OpenClaudeCode(Profile profile) => Terminal.OpenClaudeCode(profile, Paths, null);

    public void Add(Profile profile)
    {
        Library.Add(profile);
        Save();
    }

    public void Update(Profile profile)
    {
        Library.Update(profile);
        Save();
        Refresh();
    }

    /// <summary>Removes the account and moves its folders to the Recycle Bin.</summary>
    public void Delete(Profile profile)
    {
        if (profile.IsDefault || IsRunning(profile)) return;
        Library.Remove(profile.Id);
        Save();
        foreach (var dir in new[] { Paths.DesktopDataDirectory(profile), Paths.ProfileDirectory(profile.Id) }.OfType<string>())
        {
            if (!Directory.Exists(dir)) continue;
            try
            {
                Microsoft.VisualBasic.FileIO.FileSystem.DeleteDirectory(dir,
                    Microsoft.VisualBasic.FileIO.UIOption.OnlyErrorDialogs,
                    Microsoft.VisualBasic.FileIO.RecycleOption.SendToRecycleBin);
            }
            catch (Exception e) { Trace.WriteLine($"Could not recycle {dir}: {e.Message}"); }
        }
    }

    public void Move(Profile profile, int delta)
    {
        var index = Library.Profiles.IndexOf(profile);
        Library.Move(profile.Id, index + delta);
        Save();
    }

    public void ShowFolder(Profile profile)
    {
        var dir = Paths.EffectiveDesktopDataDirectory(profile);
        Directory.CreateDirectory(dir);
        Process.Start(new ProcessStartInfo("explorer.exe", CommandLine.Quote(dir)) { UseShellExecute = true })?.Dispose();
    }
}
