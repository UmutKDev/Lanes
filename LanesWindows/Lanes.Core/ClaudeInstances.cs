namespace Lanes.Core;

/// <summary>A running <c>claude.exe</c> as Windows reports it.</summary>
public sealed record ClaudeProcess(int Pid, string CommandLine);

/// <summary>A running Claude main process and the account it belongs to.</summary>
public sealed record RunningInstance(string ProfileId, int Pid, string? DataDirectory);

public static class ClaudeInstances
{
    public const string UserDataDirSwitch = "--user-data-dir";

    /// <summary>
    /// Matches Claude's main processes to accounts. Helper processes carry
    /// <c>--type=</c> and are skipped. A main process with no
    /// <c>--user-data-dir</c> belongs to the default account; one whose
    /// folder no account owns is left out, so Lanes never touches a copy it
    /// did not start.
    /// </summary>
    public static List<RunningInstance> Match(IEnumerable<ClaudeProcess> processes, ProfileLibrary library, ProfilePaths paths)
    {
        var result = new List<RunningInstance>();
        foreach (var process in processes)
        {
            var args = CommandLine.Split(process.CommandLine);
            if (args.Skip(1).Any(a => a.StartsWith("--type=", StringComparison.OrdinalIgnoreCase))) continue;
            var dataDir = CommandLine.SwitchValue(args, UserDataDirSwitch);
            Profile? owner;
            if (string.IsNullOrWhiteSpace(dataDir))
            {
                owner = library.DefaultProfile;
            }
            else
            {
                owner = library.Profiles.FirstOrDefault(p => WindowsPath.Same(paths.EffectiveDesktopDataDirectory(p), dataDir));
            }
            if (owner != null) result.Add(new RunningInstance(owner.Id, process.Pid, dataDir));
        }
        return result;
    }
}

/// <summary>Which Claude for Windows is installed, and how Lanes can start it.</summary>
public abstract record ClaudeInstallation
{
    /// <summary>The installer from claude.ai or winget. <c>claude.exe</c> in this folder starts the newest version and passes arguments on.</summary>
    public sealed record Standard(string LauncherPath) : ClaudeInstallation;

    /// <summary>The Microsoft Store package. It ignores <c>--user-data-dir</c> since 2.42304, so Lanes can't keep accounts apart with it.</summary>
    public sealed record StorePackage(string PackageDataDirectory) : ClaudeInstallation;

    public sealed record Missing : ClaudeInstallation;

    public const string StorePackagePrefix = "Claude_";

    public static ClaudeInstallation Detect(string localAppData, Func<string, bool> fileExists, Func<string, IEnumerable<string>> directoriesIn)
    {
        var launcher = WindowsPath.Join(localAppData, "AnthropicClaude", "claude.exe");
        if (fileExists(launcher)) return new Standard(launcher);
        var packages = WindowsPath.Join(localAppData, "Packages");
        var store = directoriesIn(packages).FirstOrDefault(d => WindowsPath.FileName(d).StartsWith(StorePackagePrefix, StringComparison.OrdinalIgnoreCase));
        return store != null ? new StorePackage(store) : new Missing();
    }
}
