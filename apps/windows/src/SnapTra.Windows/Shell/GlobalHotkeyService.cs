using System.Runtime.InteropServices;

namespace SnapTra.Windows.Shell;

internal sealed class GlobalHotkeyService : IDisposable
{
    private const int HotkeyId = 4096;

    private readonly nint _windowHandle;
    private bool _registered;

    public GlobalHotkeyService(nint windowHandle)
    {
        _windowHandle = windowHandle;
    }

    public event EventHandler? HotkeyPressed;

    public bool Apply(string modifiers, string key, bool enabled, out string statusMessage)
    {
        UnregisterCurrentHotkey();

        if (!enabled)
        {
            statusMessage = "Global hotkey disabled.";
            return true;
        }

        if (!TryParseModifiers(modifiers, out var modifierFlags))
        {
            statusMessage = $"Unsupported hotkey modifiers: {modifiers}";
            return false;
        }

        if (!TryParseVirtualKey(key, out var virtualKey))
        {
            statusMessage = $"Unsupported hotkey key: {key}";
            return false;
        }

        var success = NativeMethods.RegisterHotKey(
            _windowHandle,
            HotkeyId,
            modifierFlags | NativeMethods.ModNoRepeat,
            virtualKey
        );

        if (!success)
        {
            var error = Marshal.GetLastWin32Error();
            statusMessage = $"Failed to register global hotkey. Win32 error: {error}";
            return false;
        }

        _registered = true;
        statusMessage = $"Global hotkey registered: {modifiers}+{key.ToUpperInvariant()}";
        return true;
    }

    public bool TryHandleWindowMessage(uint message, nint wParam, nint lParam)
    {
        if (message != NativeMethods.WmHotkey || wParam.ToInt32() != HotkeyId)
        {
            return false;
        }

        HotkeyPressed?.Invoke(this, EventArgs.Empty);
        return true;
    }

    public void Dispose()
    {
        UnregisterCurrentHotkey();
    }

    private void UnregisterCurrentHotkey()
    {
        if (!_registered)
        {
            return;
        }

        NativeMethods.UnregisterHotKey(_windowHandle, HotkeyId);
        _registered = false;
    }

    private static bool TryParseModifiers(string modifiers, out uint flags)
    {
        flags = 0;
        if (string.IsNullOrWhiteSpace(modifiers))
        {
            return false;
        }

        foreach (var part in modifiers.Split('+', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries))
        {
            switch (part.ToLowerInvariant())
            {
            case "ctrl":
            case "control":
                flags |= NativeMethods.ModControl;
                break;
            case "shift":
                flags |= NativeMethods.ModShift;
                break;
            case "alt":
                flags |= NativeMethods.ModAlt;
                break;
            case "win":
            case "windows":
                flags |= NativeMethods.ModWin;
                break;
            default:
                return false;
            }
        }

        return flags != 0;
    }

    private static bool TryParseVirtualKey(string key, out uint virtualKey)
    {
        virtualKey = 0;
        if (string.IsNullOrWhiteSpace(key))
        {
            return false;
        }

        var normalized = key.Trim().ToUpperInvariant();
        if (normalized.Length == 1 && normalized[0] is >= 'A' and <= 'Z')
        {
            virtualKey = normalized[0];
            return true;
        }

        if (normalized.Length == 1 && normalized[0] is >= '0' and <= '9')
        {
            virtualKey = normalized[0];
            return true;
        }

        if (normalized.StartsWith("F", StringComparison.Ordinal) &&
            int.TryParse(normalized[1..], out var functionKey) &&
            functionKey is >= 1 and <= 24)
        {
            virtualKey = (uint)(0x6F + functionKey);
            return true;
        }

        return false;
    }
}
