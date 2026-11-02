namespace Lanes.Core;

/// <summary>
/// Where Lanes keeps each account's data on Windows. Folders are named after
/// the account's id, so renaming never moves anything. The default account
/// has no folders of its own: it uses Claude's standard locations.
/// </summary>
public sealed record ProfilePaths(string Root, string RoamingAppData, string Home)
{
    /// <summary>
    /// Claude's Cowork looks for its VM files in <c>%APPDATA%\&lt;folder name&gt;</c>
    /// whatever <c>--user-data-dir</c> says, so each account's Claude folder
    /// sits directly in <c>%APPDATA%</c> under this prefix.
    /// </summary>
    public const string DesktopFolderPrefix = "Claude-Lanes-";

    public static ProfilePaths Standard() => new(
        WindowsPath.Join(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Lanes"),
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile));

    public string ProfilesFile => WindowsPath.Join(Root, "profiles.json");
    public string IconsDirectory => WindowsPath.Join(Root, "Icons");
    public string LogsDirectory => WindowsPath.Join(Root, "Logs");

    public string ProfileDirectory(string id) => WindowsPath.Join(Root, "Profiles", id);

    /// <summary>The folder passed to Claude as <c>--user-data-dir</c>. Null for the default account.</summary>
    public string? DesktopDataDirectory(Profile profile) =>
        profile.IsDefault ? null : WindowsPath.Join(RoamingAppData, DesktopFolderPrefix + profile.Id);

    /// <summary>The folder passed to Claude Code as <c>CLAUDE_CONFIG_DIR</c>. Null when it uses <c>~/.claude</c>.</summary>
    public string? ClaudeCodeConfigDirectory(Profile profile) =>
        profile.IsDefault || profile.UsesSharedClaudeCode ? null : WindowsPath.Join(ProfileDirectory(profile.Id), "ClaudeCode");

    public string ClaudeDesktopDefaultDataDirectory => WindowsPath.Join(RoamingAppData, "Claude");
    public string ClaudeCodeDefaultConfigDirectory => WindowsPath.Join(Home, ".claude");

    public string EffectiveDesktopDataDirectory(Profile profile) =>
        DesktopDataDirectory(profile) ?? ClaudeDesktopDefaultDataDirectory;

    public string EffectiveClaudeCodeConfigDirectory(Profile profile) =>
        ClaudeCodeConfigDirectory(profile) ?? ClaudeCodeDefaultConfigDirectory;

    public string IconFile(Profile profile) => WindowsPath.Join(IconsDirectory, $"{profile.Id}-{profile.Color.ToString().ToLowerInvariant()}-{IconNameSafe(profile.Monogram)}.ico");

    static string IconNameSafe(string monogram) =>
        string.Concat(monogram.Select(c => char.IsLetterOrDigit(c) ? c.ToString() : ((int)c).ToString("x")));
}

/// <summary>Compares Windows paths: case-insensitive, either slash, no trailing separator.</summary>
public static class WindowsPath
{
    public static string Normalize(string path)
    {
        var p = path.Trim().Trim('"').Replace('/', '\\');
        while (p.Length > 3 && p.EndsWith('\\')) p = p[..^1];
        return p.ToLowerInvariant();
    }

    public static bool Same(string a, string b) => Normalize(a) == Normalize(b);

    /// <summary>Joins with a backslash on every OS, so the logic tests the same on Linux.</summary>
    public static string Join(params string[] parts)
    {
        var result = parts[0];
        foreach (var part in parts.Skip(1))
        {
            result = result.EndsWith('\\') || result.EndsWith('/') ? result + part : result + "\\" + part;
        }
        return result;
    }

    public static string FileName(string path)
    {
        var p = path.TrimEnd('\\', '/');
        var i = p.LastIndexOfAny(['\\', '/']);
        return i < 0 ? p : p[(i + 1)..];
    }
}
