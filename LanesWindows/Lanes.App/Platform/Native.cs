using System.Runtime.InteropServices;
using System.Text;

namespace Lanes.App.Platform;

static partial class Native
{
    public delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr lParam);

    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out int pid);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr hwnd, uint cmd);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr hwnd, StringBuilder text, int max);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr hwnd, StringBuilder text, int max);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hwnd, int cmd);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern bool AllowSetForegroundWindow(int pid);
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hwnd, uint msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr LoadImage(IntPtr hinst, string name, uint type, int cx, int cy, uint flags);
    [DllImport("user32.dll")] public static extern int GetSystemMetrics(int index);
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)] public static extern int SetCurrentProcessExplicitAppUserModelID(string appId);

    public const uint GW_OWNER = 4;
    public const int SW_RESTORE = 9;
    public const int SW_SHOW = 5;
    public const uint WM_SETICON = 0x0080;
    public const uint WM_GETICON = 0x007F;
    public const int ICON_SMALL = 0;
    public const int ICON_BIG = 1;
    public const uint IMAGE_ICON = 1;
    public const uint LR_LOADFROMFILE = 0x10;
    public const int SM_CXICON = 11, SM_CXSMICON = 49;
    public const int ASFW_ANY = -1;

    public static string WindowText(IntPtr hwnd)
    {
        var sb = new StringBuilder(256);
        GetWindowText(hwnd, sb, sb.Capacity);
        return sb.ToString();
    }

    public static string ClassName(IntPtr hwnd)
    {
        var sb = new StringBuilder(256);
        GetClassName(hwnd, sb, sb.Capacity);
        return sb.ToString();
    }

    /// <summary>Visible, unowned top-level windows of a process: the ones the taskbar shows.</summary>
    public static List<IntPtr> TopLevelWindows(int pid)
    {
        var result = new List<IntPtr>();
        EnumWindows((hwnd, _) =>
        {
            GetWindowThreadProcessId(hwnd, out var owner);
            if (owner == pid && IsWindowVisible(hwnd) && GetWindow(hwnd, GW_OWNER) == IntPtr.Zero)
                result.Add(hwnd);
            return true;
        }, IntPtr.Zero);
        return result;
    }

    public static void BringForward(IntPtr hwnd)
    {
        if (IsIconic(hwnd)) ShowWindow(hwnd, SW_RESTORE);
        else ShowWindow(hwnd, SW_SHOW);
        SetForegroundWindow(hwnd);
    }

    // ---- Window property store (taskbar identity) ----

    [StructLayout(LayoutKind.Sequential, Pack = 4)]
    public struct PropertyKey(Guid fmtid, uint pid)
    {
        public Guid Fmtid = fmtid;
        public uint Pid = pid;
    }

    [StructLayout(LayoutKind.Explicit, Size = 24)]
    public struct PropVariant
    {
        [FieldOffset(0)] public ushort Vt;
        [FieldOffset(8)] public IntPtr Pointer;
    }

    public const ushort VT_EMPTY = 0, VT_LPWSTR = 31;

    [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IPropertyStore
    {
        [PreserveSig] int GetCount(out uint count);
        [PreserveSig] int GetAt(uint index, out PropertyKey key);
        [PreserveSig] int GetValue(ref PropertyKey key, out PropVariant value);
        [PreserveSig] int SetValue(ref PropertyKey key, ref PropVariant value);
        [PreserveSig] int Commit();
    }

    [DllImport("shell32.dll")]
    public static extern int SHGetPropertyStoreForWindow(IntPtr hwnd, ref Guid iid, [MarshalAs(UnmanagedType.Interface)] out IPropertyStore store);

    [DllImport("ole32.dll")] public static extern int PropVariantClear(ref PropVariant value);

    static readonly Guid AppUserModelFmtid = new("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3");
    public static readonly PropertyKey RelaunchCommandKey = new(AppUserModelFmtid, 2);
    public static readonly PropertyKey RelaunchIconResourceKey = new(AppUserModelFmtid, 3);
    public static readonly PropertyKey RelaunchDisplayNameKey = new(AppUserModelFmtid, 4);
    public static readonly PropertyKey AppIdKey = new(AppUserModelFmtid, 5);

    public static IPropertyStore? WindowStore(IntPtr hwnd)
    {
        var iid = typeof(IPropertyStore).GUID;
        return SHGetPropertyStoreForWindow(hwnd, ref iid, out var store) == 0 ? store : null;
    }

    public static void SetString(IPropertyStore store, PropertyKey key, string? value)
    {
        var variant = new PropVariant { Vt = value == null ? VT_EMPTY : VT_LPWSTR, Pointer = value == null ? IntPtr.Zero : Marshal.StringToCoTaskMemUni(value) };
        try { Marshal.ThrowExceptionForHR(store.SetValue(ref key, ref variant)); }
        finally { PropVariantClear(ref variant); }
    }

    public static string? GetString(IPropertyStore store, PropertyKey key)
    {
        if (store.GetValue(ref key, out var variant) != 0) return null;
        try { return variant.Vt == VT_LPWSTR ? Marshal.PtrToStringUni(variant.Pointer) : null; }
        finally { PropVariantClear(ref variant); }
    }
}
