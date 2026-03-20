using Microsoft.UI.Xaml;
using SnapTra.Windows.Settings;
using SnapTra.Windows.Shell;

namespace SnapTra.Windows;

public partial class App : Application
{
    private SettingsStore? _settingsStore;
    private SettingsViewModel? _settingsViewModel;
    private SettingsWindow? _settingsWindow;
    private ShellMessageWindow? _shellWindow;
    private TrayIconService? _trayIconService;
    private GlobalHotkeyService? _globalHotkeyService;

    public App()
    {
        InitializeComponent();
        UnhandledException += OnUnhandledException;
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        base.OnLaunched(args);

        _settingsStore = new SettingsStore();
        _settingsViewModel = new SettingsViewModel(_settingsStore.Load(), _settingsStore);
        _settingsViewModel.SettingsApplied += OnSettingsApplied;

        _shellWindow = new ShellMessageWindow(HandleShellMessage);
        _trayIconService = new TrayIconService(_shellWindow.Handle);
        _trayIconService.OpenSettingsRequested += (_, _) => ShowSettingsWindow();
        _trayIconService.ToggleHotkeyRequested += (_, _) => ToggleHotkey();
        _trayIconService.ExitRequested += (_, _) => Shutdown();
        _trayIconService.Initialize();

        _globalHotkeyService = new GlobalHotkeyService(_shellWindow.Handle);
        _globalHotkeyService.HotkeyPressed += (_, _) => OnHotkeyPressed();

        ApplyShellSettings();
        _settingsViewModel.SetShellStatus("Windows tray shell ready. OCR, capture, and dictionary are not connected yet.");
    }

    private nint HandleShellMessage(nint hwnd, uint message, nint wParam, nint lParam, out bool handled)
    {
        if (_trayIconService?.TryHandleWindowMessage(message, wParam, lParam) == true)
        {
            handled = true;
            return 0;
        }

        if (_globalHotkeyService?.TryHandleWindowMessage(message, wParam, lParam) == true)
        {
            handled = true;
            return 0;
        }

        handled = false;
        return 0;
    }

    private void OnSettingsApplied(object? sender, EventArgs e)
    {
        ApplyShellSettings();
    }

    private void ApplyShellSettings()
    {
        if (_settingsViewModel is null || _trayIconService is null || _globalHotkeyService is null)
        {
            return;
        }

        var success = _globalHotkeyService.Apply(
            _settingsViewModel.HotkeyModifiers,
            _settingsViewModel.HotkeyKey,
            _settingsViewModel.IsHotkeyEnabled,
            out var statusMessage
        );

        _trayIconService.SetHotkeyEnabled(_settingsViewModel.IsHotkeyEnabled);
        _settingsViewModel.SetHotkeyStatus(statusMessage);

        if (!success)
        {
            _settingsViewModel.SetShellStatus("Hotkey registration needs attention. See the status below.");
        }
    }

    private void ToggleHotkey()
    {
        if (_settingsViewModel is null)
        {
            return;
        }

        _settingsViewModel.IsHotkeyEnabled = !_settingsViewModel.IsHotkeyEnabled;
        _settingsViewModel.Save();
    }

    private void OnHotkeyPressed()
    {
        _settingsViewModel?.SetShellStatus(
            $"Hotkey triggered at {DateTime.Now:HH:mm:ss}. OCR and capture are not implemented in this shell bootstrap yet."
        );
    }

    private void ShowSettingsWindow()
    {
        if (_settingsViewModel is null)
        {
            return;
        }

        if (_settingsWindow is null)
        {
            _settingsWindow = new SettingsWindow(_settingsViewModel);
            _settingsWindow.Closed += (_, _) => _settingsWindow = null;
        }

        _settingsWindow.Activate();
    }

    private void Shutdown()
    {
        _globalHotkeyService?.Dispose();
        _trayIconService?.Dispose();
        _shellWindow?.Dispose();

        if (_settingsWindow is not null)
        {
            _settingsWindow.Close();
            _settingsWindow = null;
        }

        Exit();
    }

    private void OnUnhandledException(object sender, Microsoft.UI.Xaml.UnhandledExceptionEventArgs e)
    {
        if (_settingsViewModel is not null)
        {
            _settingsViewModel.SetShellStatus($"Unhandled shell error: {e.Exception.Message}");
        }

        e.Handled = true;
    }
}
