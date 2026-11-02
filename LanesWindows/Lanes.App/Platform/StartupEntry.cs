using Microsoft.Win32;
using Lanes.Core;

namespace Lanes.App.Platform;

/// <summary>Starts Lanes in the notification area when the user signs in to Windows.</summary>
static class StartupEntry
{
    const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    const string Name = "Lanes";

    public static bool IsEnabled
    {
        get
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKey);
            return key?.GetValue(Name) is string;
        }
    }

    public static void Set(bool enabled)
    {
        using var key = Registry.CurrentUser.CreateSubKey(RunKey);
        if (enabled) key.SetValue(Name, $"{CommandLine.Quote(Environment.ProcessPath!)} {LanesArguments.HiddenSwitch}");
        else key.DeleteValue(Name, throwOnMissingValue: false);
    }
}
