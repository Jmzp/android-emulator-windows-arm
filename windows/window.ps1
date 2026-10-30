# Gives the Android window its own icon and taskbar button.
#
# WSLg shows Linux windows through msrdc.exe, titled "<title> (<distro>)"
# and grouped with WSL's other windows under WSL's icon. start-android.sh
# already makes Weston's title "Android Emulator"; this drops the distro
# suffix, sets our icon and a taskbar identity of its own. Weston never
# changes its title afterwards, so the changes stick.
# Dot-source after common.ps1.

$WindowAppId = 'Jmzp.AndroidEmulatorWindowsArm'

if (-not ('AndroidWindow' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class AndroidWindow {
    delegate bool EnumProc(IntPtr hwnd, IntPtr param);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc proc, IntPtr param);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr hwnd, StringBuilder text, int max);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr hwnd, StringBuilder name, int max);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool SetWindowText(IntPtr hwnd, string text);
    [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr hwnd, uint msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] static extern int GetSystemMetrics(int index);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr LoadImage(IntPtr inst, string name, uint type, int cx, int cy, uint flags);
    [DllImport("shell32.dll")] static extern int SHGetPropertyStoreForWindow(IntPtr hwnd, ref Guid iid, out IPropertyStore store);

    [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IPropertyStore {
        int GetCount(out uint count);
        int GetAt(uint index, out PropertyKey key);
        int GetValue(ref PropertyKey key, out PropVariant value);
        int SetValue(ref PropertyKey key, ref PropVariant value);
        int Commit();
    }

    [StructLayout(LayoutKind.Sequential, Pack = 4)]
    struct PropertyKey {
        public Guid FormatId; public uint PropertyId;
        public PropertyKey(string formatId, uint propertyId) { FormatId = new Guid(formatId); PropertyId = propertyId; }
    }

    // A PROPVARIANT holding a VT_LPWSTR string.
    [StructLayout(LayoutKind.Explicit)]
    struct PropVariant {
        [FieldOffset(0)] public ushort Type;
        [FieldOffset(8)] public IntPtr Value;
        [FieldOffset(16)] IntPtr padding;
    }

    const string AppUserModel = "9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3";

    // Top-level msrdc windows whose title starts with the given text.
    public static IntPtr Find(string titlePrefix) {
        IntPtr found = IntPtr.Zero;
        EnumWindows((hwnd, param) => {
            var title = new StringBuilder(512);
            var cls = new StringBuilder(64);
            GetWindowText(hwnd, title, title.Capacity);
            GetClassName(hwnd, cls, cls.Capacity);
            if (cls.ToString() == "RAIL_WINDOW" && title.ToString().StartsWith(titlePrefix)) {
                found = hwnd;
                return false;
            }
            return true;
        }, IntPtr.Zero);
        return found;
    }

    public static void Apply(IntPtr hwnd, string title, string iconPath, string appId, string relaunchCommand) {
        SetWindowText(hwnd, title);

        const uint WM_SETICON = 0x80, IMAGE_ICON = 1, LR_LOADFROMFILE = 0x10;
        IntPtr big = LoadImage(IntPtr.Zero, iconPath, IMAGE_ICON, GetSystemMetrics(11), GetSystemMetrics(12), LR_LOADFROMFILE);
        IntPtr small = LoadImage(IntPtr.Zero, iconPath, IMAGE_ICON, GetSystemMetrics(49), GetSystemMetrics(50), LR_LOADFROMFILE);
        if (big != IntPtr.Zero) SendMessage(hwnd, WM_SETICON, (IntPtr)1, big);
        if (small != IntPtr.Zero) SendMessage(hwnd, WM_SETICON, (IntPtr)0, small);

        // Its own taskbar button, which can be pinned to start the emulator.
        Guid iid = typeof(IPropertyStore).GUID;
        IPropertyStore store;
        if (SHGetPropertyStoreForWindow(hwnd, ref iid, out store) != 0) return;
        try {
            // The relaunch values must be in place before the app id.
            Set(store, new PropertyKey(AppUserModel, 2), relaunchCommand);   // RelaunchCommand
            Set(store, new PropertyKey(AppUserModel, 4), title);             // RelaunchDisplayNameResource
            Set(store, new PropertyKey(AppUserModel, 3), iconPath);          // RelaunchIconResource
            Set(store, new PropertyKey(AppUserModel, 5), appId);             // ID
            store.Commit();
        } finally {
            Marshal.ReleaseComObject(store);
        }
    }

    static void Set(IPropertyStore store, PropertyKey key, string value) {
        var variant = new PropVariant { Type = 31 /* VT_LPWSTR */, Value = Marshal.StringToCoTaskMemUni(value) };
        try { store.SetValue(ref key, ref variant); }
        finally { Marshal.FreeCoTaskMem(variant.Value); }
    }
}
'@
}

# Renames the phone window once it shows up. Best effort: the emulator works
# the same with the default title.
function Set-AndroidWindow([string]$Title = 'Android Emulator', [int]$TimeoutSeconds = 15) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        # The second title is from a Weston whose title couldn't be patched.
        $hwnd = [AndroidWindow]::Find("$Title (")
        if ($hwnd -eq [IntPtr]::Zero) { $hwnd = [AndroidWindow]::Find('Weston Compositor') }
        if ($hwnd -ne [IntPtr]::Zero) { break }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    if ($hwnd -eq [IntPtr]::Zero) { return }

    $shell = (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source
    if (-not $shell) { $shell = (Get-Command powershell.exe).Source }
    $relaunch = "`"$shell`" -NoExit -ExecutionPolicy Bypass -File `"$(Join-Path $PSScriptRoot 'android.ps1')`" start"
    $icon = Join-Path $RepoRoot 'assets\android-emulator.ico'
    try { [AndroidWindow]::Apply($hwnd, $Title, $icon, $WindowAppId, $relaunch) }
    catch { Write-Verbose "Could not rename the Android window: $_" }
}
