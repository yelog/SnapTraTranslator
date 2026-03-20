using System.Runtime.InteropServices;

namespace SnapTra.Windows.Shell;

internal static class NativeMethods
{
    internal delegate nint WndProc(nint hwnd, uint message, nint wParam, nint lParam);

    internal const int WindowClassAlreadyExists = 1410;

    internal const uint WmDestroy = 0x0002;
    internal const uint WmCommand = 0x0111;
    internal const uint WmClose = 0x0010;
    internal const uint WmUser = 0x0400;
    internal const uint WmApp = 0x8000;
    internal const uint WmHotkey = 0x0312;
    internal const uint WmLButtonUp = 0x0202;
    internal const uint WmLButtonDblClk = 0x0203;
    internal const uint WmRButtonUp = 0x0205;
    internal const uint WmContextMenu = 0x007B;

    internal const uint NimAdd = 0x00000000;
    internal const uint NimModify = 0x00000001;
    internal const uint NimDelete = 0x00000002;

    internal const uint NifMessage = 0x00000001;
    internal const uint NifIcon = 0x00000002;
    internal const uint NifTip = 0x00000004;
    internal const uint NifShowTip = 0x00000080;

    internal const uint MfString = 0x00000000;
    internal const uint MfSeparator = 0x00000800;

    internal const uint TpmLeftAlign = 0x0000;
    internal const uint TpmRightButton = 0x0002;
    internal const uint TpmBottomAlign = 0x0020;

    internal const uint ModAlt = 0x0001;
    internal const uint ModControl = 0x0002;
    internal const uint ModShift = 0x0004;
    internal const uint ModWin = 0x0008;
    internal const uint ModNoRepeat = 0x4000;

    internal static readonly nint IdiApplication = 32512;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    internal struct WndClassEx
    {
        internal uint cbSize;
        internal uint style;
        internal WndProc lpfnWndProc;
        internal int cbClsExtra;
        internal int cbWndExtra;
        internal nint hInstance;
        internal nint hIcon;
        internal nint hCursor;
        internal nint hbrBackground;
        [MarshalAs(UnmanagedType.LPWStr)]
        internal string? lpszMenuName;
        [MarshalAs(UnmanagedType.LPWStr)]
        internal string lpszClassName;
        internal nint hIconSm;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    internal struct NotifyIconData
    {
        internal uint cbSize;
        internal nint hWnd;
        internal uint uID;
        internal uint uFlags;
        internal uint uCallbackMessage;
        internal nint hIcon;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        internal string szTip;
        internal uint dwState;
        internal uint dwStateMask;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
        internal string szInfo;
        internal uint uVersion;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)]
        internal string szInfoTitle;
        internal uint dwInfoFlags;
        internal Guid guidItem;
        internal nint hBalloonIcon;
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    internal static extern ushort RegisterClassEx(ref WndClassEx windowClass);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    internal static extern nint CreateWindowEx(
        uint exStyle,
        string className,
        string windowName,
        uint style,
        int x,
        int y,
        int width,
        int height,
        nint parentHandle,
        nint menuHandle,
        nint instanceHandle,
        nint parameter
    );

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool DestroyWindow(nint hwnd);

    [DllImport("user32.dll")]
    internal static extern nint DefWindowProc(nint hwnd, uint message, nint wParam, nint lParam);

    [DllImport("user32.dll")]
    internal static extern void PostQuitMessage(int exitCode);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool RegisterHotKey(nint hwnd, int id, uint modifiers, uint virtualKey);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool UnregisterHotKey(nint hwnd, int id);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    internal static extern nint LoadIcon(nint instanceHandle, nint iconName);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool SetForegroundWindow(nint hwnd);

    [DllImport("user32.dll")]
    internal static extern nint CreatePopupMenu();

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool AppendMenu(nint menuHandle, uint flags, nint itemId, string? itemText);

    [DllImport("user32.dll", SetLastError = true)]
    internal static extern uint TrackPopupMenu(
        nint menuHandle,
        uint flags,
        int x,
        int y,
        int reserved,
        nint hwnd,
        nint rect
    );

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool DestroyMenu(nint menuHandle);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool GetCursorPos(out Point point);

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool Shell_NotifyIcon(uint message, ref NotifyIconData data);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    internal static extern nint GetModuleHandle(string? moduleName);

    [StructLayout(LayoutKind.Sequential)]
    internal struct Point
    {
        internal int X;
        internal int Y;
    }
}
