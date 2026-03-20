namespace SnapTra.Windows.Shell;

internal sealed class TrayIconService : IDisposable
{
    private const uint TrayIconId = 1;
    private const uint TrayCallbackMessage = NativeMethods.WmApp + 1;
    private const int CommandOpenSettings = 1001;
    private const int CommandToggleHotkey = 1002;
    private const int CommandExit = 1003;

    private readonly nint _windowHandle;
    private readonly Guid _iconGuid = Guid.Parse("5A9AE369-D572-4E45-819E-3C7355BDE995");
    private bool _initialized;
    private bool _hotkeyEnabled = true;

    public TrayIconService(nint windowHandle)
    {
        _windowHandle = windowHandle;
    }

    public event EventHandler? OpenSettingsRequested;
    public event EventHandler? ToggleHotkeyRequested;
    public event EventHandler? ExitRequested;

    public void Initialize()
    {
        if (_initialized)
        {
            return;
        }

        var iconData = CreateNotifyIconData();
        if (!NativeMethods.Shell_NotifyIcon(NativeMethods.NimAdd, ref iconData))
        {
            throw new InvalidOperationException("Failed to add tray icon to the notification area.");
        }

        _initialized = true;
    }

    public void SetHotkeyEnabled(bool enabled)
    {
        _hotkeyEnabled = enabled;
    }

    public bool TryHandleWindowMessage(uint message, nint wParam, nint lParam)
    {
        if (message == TrayCallbackMessage)
        {
            var mouseMessage = unchecked((uint)lParam.ToInt64());
            if (mouseMessage == NativeMethods.WmLButtonUp || mouseMessage == NativeMethods.WmLButtonDblClk)
            {
                OpenSettingsRequested?.Invoke(this, EventArgs.Empty);
            }
            else if (mouseMessage == NativeMethods.WmRButtonUp || mouseMessage == NativeMethods.WmContextMenu)
            {
                ShowContextMenu();
            }

            return true;
        }

        if (message == NativeMethods.WmCommand)
        {
            var commandId = unchecked((ushort)(wParam.ToInt64() & 0xFFFF));
            switch (commandId)
            {
            case CommandOpenSettings:
                OpenSettingsRequested?.Invoke(this, EventArgs.Empty);
                return true;
            case CommandToggleHotkey:
                ToggleHotkeyRequested?.Invoke(this, EventArgs.Empty);
                return true;
            case CommandExit:
                ExitRequested?.Invoke(this, EventArgs.Empty);
                return true;
            default:
                return false;
            }
        }

        return false;
    }

    public void Dispose()
    {
        if (!_initialized)
        {
            return;
        }

        var iconData = CreateNotifyIconData();
        NativeMethods.Shell_NotifyIcon(NativeMethods.NimDelete, ref iconData);
        _initialized = false;
    }

    private NativeMethods.NotifyIconData CreateNotifyIconData()
    {
        return new NativeMethods.NotifyIconData
        {
            cbSize = (uint)System.Runtime.InteropServices.Marshal.SizeOf<NativeMethods.NotifyIconData>(),
            hWnd = _windowHandle,
            uID = TrayIconId,
            uFlags = NativeMethods.NifMessage | NativeMethods.NifIcon | NativeMethods.NifTip | NativeMethods.NifShowTip,
            uCallbackMessage = TrayCallbackMessage,
            hIcon = NativeMethods.LoadIcon(0, NativeMethods.IdiApplication),
            szTip = "SnapTra Translator",
            guidItem = _iconGuid,
        };
    }

    private void ShowContextMenu()
    {
        var menuHandle = NativeMethods.CreatePopupMenu();
        if (menuHandle == 0)
        {
            return;
        }

        try
        {
            NativeMethods.AppendMenu(menuHandle, NativeMethods.MfString, CommandOpenSettings, "Open Settings");
            NativeMethods.AppendMenu(
                menuHandle,
                NativeMethods.MfString,
                CommandToggleHotkey,
                _hotkeyEnabled ? "Disable Hotkey" : "Enable Hotkey"
            );
            NativeMethods.AppendMenu(menuHandle, NativeMethods.MfSeparator, 0, null);
            NativeMethods.AppendMenu(menuHandle, NativeMethods.MfString, CommandExit, "Exit");

            NativeMethods.GetCursorPos(out var cursorPosition);
            NativeMethods.SetForegroundWindow(_windowHandle);
            NativeMethods.TrackPopupMenu(
                menuHandle,
                NativeMethods.TpmLeftAlign | NativeMethods.TpmBottomAlign | NativeMethods.TpmRightButton,
                cursorPosition.X,
                cursorPosition.Y,
                0,
                _windowHandle,
                0
            );
        }
        finally
        {
            NativeMethods.DestroyMenu(menuHandle);
        }
    }
}
