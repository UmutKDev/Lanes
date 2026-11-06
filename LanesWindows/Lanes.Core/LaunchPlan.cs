using System.Text;

namespace Lanes.Core;

/// <summary>Everything needed to start Claude for one account.</summary>
public sealed record LaunchPlan(
    string Executable,
    IReadOnlyList<string> Arguments,
    IReadOnlyDictionary<string, string> EnvironmentAdditions,
    IReadOnlyList<string> EnvironmentRemovals,
    IReadOnlyList<string> DirectoriesToCreate);

public static class LaunchPlanner
{
    public const string ClaudeConfigDirVariable = "CLAUDE_CONFIG_DIR";

    public static LaunchPlan Plan(Profile profile, string claudeLauncher, ProfilePaths paths)
    {
        var dataDir = paths.DesktopDataDirectory(profile);
        var configDir = paths.ClaudeCodeConfigDirectory(profile);
        var args = new List<string>();
        if (dataDir != null) args.Add($"{ClaudeInstances.UserDataDirSwitch}={dataDir}");
        var additions = new Dictionary<string, string>();
        if (configDir != null) additions[ClaudeConfigDirVariable] = configDir;
        // A Lanes started from a Claude Code terminal must not pass that account's folder on.
        var removals = configDir == null ? new List<string> { ClaudeConfigDirVariable } : new List<string>();
        var create = new[] { dataDir, configDir }.OfType<string>().ToList();
        return new LaunchPlan(claudeLauncher, args, additions, removals, create);
    }
}

/// <summary>Builds the command that runs Claude Code with an account in a terminal.</summary>
public static class ClaudeCodeCommand
{
    /// <summary>A PowerShell script that sets the account's folder, goes to the project and runs <c>claude</c>.</summary>
    public static string PowerShellScript(Profile profile, ProfilePaths paths, string? folder, IReadOnlyList<string>? claudeArguments = null)
    {
        var sb = new StringBuilder();
        var configDir = paths.ClaudeCodeConfigDirectory(profile);
        if (configDir != null)
            sb.Append($"$env:{LaunchPlanner.ClaudeConfigDirVariable} = {PowerShellQuote(configDir)}; ");
        else
            sb.Append($"Remove-Item Env:{LaunchPlanner.ClaudeConfigDirVariable} -ErrorAction SilentlyContinue; ");
        sb.Append($"$Host.UI.RawUI.WindowTitle = {PowerShellQuote("Claude Code · " + profile.Name)}; ");
        var start = folder ?? profile.DefaultProjectFolder;
        if (!string.IsNullOrWhiteSpace(start)) sb.Append($"Set-Location -LiteralPath {PowerShellQuote(start)}; ");
        sb.Append("claude");
        foreach (var arg in claudeArguments ?? []) sb.Append(' ').Append(PowerShellQuote(arg));
        return sb.ToString();
    }

    /// <summary>The script as <c>-EncodedCommand</c> wants it, so no quoting layer can break it.</summary>
    public static string Encoded(string script) => Convert.ToBase64String(Encoding.Unicode.GetBytes(script));

    public static string PowerShellQuote(string value) => "'" + value.Replace("'", "''") + "'";

    /// <summary>
    /// Arguments for <c>wt.exe</c>: a new tab with the account's colour and
    /// name. The script goes encoded, because Windows Terminal reads <c>;</c>
    /// as its own command separator.
    /// </summary>
    public static List<string> WindowsTerminalArguments(Profile profile, string powershell, string script)
    {
        var (r, g, b) = ProfileColors.Rgb(profile.Color);
        return
        [
            "-w", "0", "new-tab",
            "--title", "Claude Code · " + profile.Name,
            "--tabColor", $"#{r:X2}{g:X2}{b:X2}",
            "--suppressApplicationTitle",
            powershell, "-NoExit", "-NoLogo", "-EncodedCommand", Encoded(script),
        ];
    }

    public static List<string> ConsoleArguments(string script) => ["-NoExit", "-NoLogo", "-EncodedCommand", Encoded(script)];
}
