using System.Runtime.InteropServices;
using Lanes.Core;

namespace Lanes.App.Platform;

/// <summary>
/// Gives a Claude window its account's taskbar identity: its own
/// AppUserModelID, so Windows shows it as a separate taskbar button, the
/// account's coloured icon, and a relaunch command that opens the account
/// through Lanes when the button is pinned.
/// </summary>
sealed class TaskbarStamp
{
    readonly Dictionary<string, (IntPtr Big, IntPtr Small)> icons = new();

    /// <summary>Applies the identity unless the window already has it. Returns true when it changed something.</summary>
    public bool Apply(IntPtr hwnd, TaskbarIdentity identity)
    {
        var changed = false;
        var store = Native.WindowStore(hwnd);
        if (store != null)
        {
            try
            {
                if (Native.GetString(store, Native.AppIdKey) != identity.AppUserModelId)
                {
                    // Relaunch properties are read when the ID is set, so they go first.
                    Native.SetString(store, Native.RelaunchCommandKey, identity.RelaunchCommand);
                    Native.SetString(store, Native.RelaunchDisplayNameKey, identity.RelaunchDisplayName);
                    Native.SetString(store, Native.RelaunchIconResourceKey, identity.IconPath + ",0");
                    Native.SetString(store, Native.AppIdKey, identity.AppUserModelId);
                    store.Commit();
                    changed = true;
                }
            }
            finally { Marshal.ReleaseComObject(store); }
        }

        var (big, small) = Icons(identity.IconPath);
        if (big != IntPtr.Zero && Native.SendMessage(hwnd, Native.WM_GETICON, Native.ICON_BIG, IntPtr.Zero) != big)
        {
            Native.SendMessage(hwnd, Native.WM_SETICON, Native.ICON_BIG, big);
            Native.SendMessage(hwnd, Native.WM_SETICON, Native.ICON_SMALL, small);
            changed = true;
        }
        return changed;
    }

    public static string? ReadAppId(IntPtr hwnd)
    {
        var store = Native.WindowStore(hwnd);
        if (store == null) return null;
        try { return Native.GetString(store, Native.AppIdKey); }
        finally { Marshal.ReleaseComObject(store); }
    }

    (IntPtr, IntPtr) Icons(string path)
    {
        if (icons.TryGetValue(path, out var cached)) return cached;
        var big = Native.LoadImage(IntPtr.Zero, path, Native.IMAGE_ICON, Native.GetSystemMetrics(Native.SM_CXICON), Native.GetSystemMetrics(Native.SM_CXICON), Native.LR_LOADFROMFILE);
        var small = Native.LoadImage(IntPtr.Zero, path, Native.IMAGE_ICON, Native.GetSystemMetrics(Native.SM_CXSMICON), Native.GetSystemMetrics(Native.SM_CXSMICON), Native.LR_LOADFROMFILE);
        icons[path] = (big, small);
        return (big, small);
    }
}
