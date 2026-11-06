using System.Diagnostics;
using System.Management;
using Lanes.Core;

namespace Lanes.App.Platform;

/// <summary>Finds, starts and brings forward Claude for each account.</summary>
static class ClaudeProcesses
{
    public static List<ClaudeProcess> List()
    {
        var result = new List<ClaudeProcess>();
        try
        {
            using var searcher = new ManagementObjectSearcher("SELECT ProcessId, CommandLine FROM Win32_Process WHERE Name = 'claude.exe'");
            foreach (var item in searcher.Get())
            {
                using (item)
                {
                    if (item["CommandLine"] is string line && item["ProcessId"] is uint pid)
                        result.Add(new ClaudeProcess((int)pid, line));
                }
            }
        }
        catch (ManagementException) { /* WMI unavailable: nothing is shown as running */ }
        return result;
    }

    public static ClaudeInstallation DetectInstallation()
    {
        var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        return ClaudeInstallation.Detect(local, File.Exists,
            dir => Directory.Exists(dir) ? Directory.EnumerateDirectories(dir) : []);
    }

    public static int Start(LaunchPlan plan)
    {
        foreach (var dir in plan.DirectoriesToCreate) Directory.CreateDirectory(dir);
        var info = new ProcessStartInfo(plan.Executable)
        {
            UseShellExecute = false,
            WorkingDirectory = Path.GetDirectoryName(plan.Executable)!,
        };
        foreach (var arg in plan.Arguments) info.ArgumentList.Add(arg);
        foreach (var name in plan.EnvironmentRemovals) info.Environment.Remove(name);
        foreach (var (name, value) in plan.EnvironmentAdditions) info.Environment[name] = value;
        using var process = Process.Start(info)!;
        return process.Id;
    }
}
