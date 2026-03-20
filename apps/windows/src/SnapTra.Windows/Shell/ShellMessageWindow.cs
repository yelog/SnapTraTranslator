using System.Collections.Concurrent;
using System.Runtime.InteropServices;

namespace SnapTra.Windows.Shell;

internal sealed class ShellMessageWindow : IDisposable
{
    private static readonly ConcurrentDictionary<nint, ShellMessageWindow> Instances = new();
    private static readonly NativeMethods.WndProc WindowProcedure = DispatchWindowMessage;

    private readonly string _className;
    private readonly MessageHandler _handler;
    private bool _disposed;

    internal delegate nint MessageHandler(nint hwnd, uint message, nint wParam, nint lParam, out bool handled);

    public ShellMessageWindow(MessageHandler handler)
    {
        _handler = handler;
        _className = $"SnapTraShellWindow.{Guid.NewGuid():N}";

        var moduleHandle = NativeMethods.GetModuleHandle(null);
        var windowClass = new NativeMethods.WndClassEx
        {
            cbSize = (uint)Marshal.SizeOf<NativeMethods.WndClassEx>(),
            lpfnWndProc = WindowProcedure,
            hInstance = moduleHandle,
            lpszClassName = _className,
        };

        var atom = NativeMethods.RegisterClassEx(ref windowClass);
        if (atom == 0)
        {
            var error = Marshal.GetLastWin32Error();
            if (error != NativeMethods.WindowClassAlreadyExists)
            {
                throw new InvalidOperationException($"Failed to register shell window class. Win32 error: {error}");
            }
        }

        Handle = NativeMethods.CreateWindowEx(
            0,
            _className,
            _className,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            moduleHandle,
            0
        );

        if (Handle == 0)
        {
            throw new InvalidOperationException($"Failed to create hidden shell window. Win32 error: {Marshal.GetLastWin32Error()}");
        }

        Instances[Handle] = this;
    }

    public nint Handle { get; }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        Instances.TryRemove(Handle, out _);

        if (Handle != 0)
        {
            NativeMethods.DestroyWindow(Handle);
        }
    }

    private static nint DispatchWindowMessage(nint hwnd, uint message, nint wParam, nint lParam)
    {
        if (Instances.TryGetValue(hwnd, out var window))
        {
            var result = window._handler(hwnd, message, wParam, lParam, out var handled);
            if (handled)
            {
                return result;
            }
        }

        if (message == NativeMethods.WmDestroy)
        {
            NativeMethods.PostQuitMessage(0);
            return 0;
        }

        return NativeMethods.DefWindowProc(hwnd, message, wParam, lParam);
    }
}
