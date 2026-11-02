using System.Diagnostics;
using Lanes.Core;

namespace Lanes.App.Platform;

/// <summary>Opens Claude Code with an account: in Windows Terminal when it is there, else in a PowerShell window.</summary>
static class Terminal
{
    public static void OpenClaudeCode(Profile profile, ProfilePaths paths, string? folder)
    {
        var script = ClaudeCodeCommand.PowerShellScript(profile, paths, folder);
        var powershell = FindOnPath("pwsh.exe") ?? "powershell.exe";
        var wt = FindOnPath("wt.exe")
            ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Microsoft", "WindowsApps", "wt.exe");
        ProcessStartInfo info;
        if (File.Exists(wt))
        {
            info = new ProcessStartInfo(wt) { UseShellExecute = false };
            foreach (var arg in ClaudeCodeCommand.WindowsTerminalArguments(profile, powershell, script)) info.ArgumentList.Add(arg);
        }
        else
        {
            info = new ProcessStartInfo(powershell) { UseShellExecute = true };
            info.Arguments = string.Join(' ', ClaudeCodeCommand.ConsoleArguments(script).Select(CommandLine.Quote));
        }
        info.WorkingDirectory = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        Process.Start(info)?.Dispose();
    }

    static string? FindOnPath(string exe)
    {
        foreach (var dir in (Environment.GetEnvironmentVariable("PATH") ?? "").Split(Path.PathSeparator))
        {
            try
            {
                var candidate = Path.Combine(dir.Trim(), exe);
                if (File.Exists(candidate)) return candidate;
            }
            catch (ArgumentException) { }
        }
        return null;
    }
}
