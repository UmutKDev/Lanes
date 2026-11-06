namespace Lanes.Core;

/// <summary>
/// What Lanes writes on each Claude window so Windows shows every account as
/// its own taskbar button with its own icon. Windows groups buttons by
/// AppUserModelID; Claude leaves it unset, so each window takes the account's.
/// </summary>
public sealed record TaskbarIdentity(string AppUserModelId, string RelaunchCommand, string RelaunchDisplayName, string IconPath)
{
    public const string AppIdPrefix = "UmutKDev.Lanes.Account.";

    public static TaskbarIdentity For(Profile profile, string lanesExecutable, string iconPath) => new(
        AppIdPrefix + profile.Id.Replace("-", ""),
        $"{CommandLine.Quote(lanesExecutable)} {LanesArguments.OpenSwitch} {profile.Id}",
        profile.Name,
        iconPath);
}

/// <summary>Lanes' own command line.</summary>
public sealed record LanesArguments(string? OpenProfileId, string? SelfTestDirectory, bool StartHidden)
{
    public const string OpenSwitch = "--open";
    public const string SelfTestSwitch = "--self-test";
    public const string HiddenSwitch = "--hidden";

    public static LanesArguments Parse(IReadOnlyList<string> args)
    {
        string? open = null, selfTest = null;
        var hidden = false;
        for (var i = 0; i < args.Count; i++)
        {
            switch (args[i])
            {
                case OpenSwitch when i + 1 < args.Count: open = args[++i]; break;
                case SelfTestSwitch when i + 1 < args.Count: selfTest = args[++i]; break;
                case HiddenSwitch: hidden = true; break;
            }
        }
        return new LanesArguments(open, selfTest, hidden);
    }

    /// <summary>The line a second Lanes sends to the running one before it quits.</summary>
    public string ToMessage() => OpenProfileId != null ? $"open {OpenProfileId}" : "show";

    public static LanesArguments FromMessage(string message) =>
        message.StartsWith("open ", StringComparison.Ordinal)
            ? new LanesArguments(message[5..].Trim(), null, false)
            : new LanesArguments(null, null, false);
}
