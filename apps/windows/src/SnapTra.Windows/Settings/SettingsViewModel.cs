using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace SnapTra.Windows.Settings;

public sealed class SettingsViewModel : INotifyPropertyChanged
{
    private readonly SettingsStore _store;

    private string _sourceLanguage;
    private string _targetLanguage;
    private string _hotkeyModifiers;
    private string _hotkeyKey;
    private bool _isHotkeyEnabled;
    private bool _launchAtLoginRequested;
    private string _shellStatus = "Shell not initialized yet.";
    private string _hotkeyStatus = "Hotkey registration not attempted yet.";
    private string _ocrStatus = "OCR service placeholder.";
    private string _translationStatus = "Translation service placeholder.";
    private string _dictionaryStatus = "Dictionary service placeholder.";
    private string _persistenceStatus = "No settings changes saved yet.";

    public SettingsViewModel(SettingsModel settings, SettingsStore store)
    {
        _store = store;
        _sourceLanguage = settings.SourceLanguage;
        _targetLanguage = settings.TargetLanguage;
        _hotkeyModifiers = settings.HotkeyModifiers;
        _hotkeyKey = settings.HotkeyKey;
        _isHotkeyEnabled = settings.IsHotkeyEnabled;
        _launchAtLoginRequested = settings.LaunchAtLoginRequested;
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    public event EventHandler? SettingsApplied;

    public string SourceLanguage
    {
        get => _sourceLanguage;
        set => SetField(ref _sourceLanguage, value);
    }

    public string TargetLanguage
    {
        get => _targetLanguage;
        set => SetField(ref _targetLanguage, value);
    }

    public string HotkeyModifiers
    {
        get => _hotkeyModifiers;
        set => SetField(ref _hotkeyModifiers, value);
    }

    public string HotkeyKey
    {
        get => _hotkeyKey;
        set => SetField(ref _hotkeyKey, value);
    }

    public bool IsHotkeyEnabled
    {
        get => _isHotkeyEnabled;
        set => SetField(ref _isHotkeyEnabled, value);
    }

    public bool LaunchAtLoginRequested
    {
        get => _launchAtLoginRequested;
        set => SetField(ref _launchAtLoginRequested, value);
    }

    public string ShellStatus
    {
        get => _shellStatus;
        private set => SetField(ref _shellStatus, value);
    }

    public string HotkeyStatus
    {
        get => _hotkeyStatus;
        private set => SetField(ref _hotkeyStatus, value);
    }

    public string OcrStatus
    {
        get => _ocrStatus;
        private set => SetField(ref _ocrStatus, value);
    }

    public string TranslationStatus
    {
        get => _translationStatus;
        private set => SetField(ref _translationStatus, value);
    }

    public string DictionaryStatus
    {
        get => _dictionaryStatus;
        private set => SetField(ref _dictionaryStatus, value);
    }

    public string PersistenceStatus
    {
        get => _persistenceStatus;
        private set => SetField(ref _persistenceStatus, value);
    }

    public void Save()
    {
        var saved = _store.TrySave(ToModel(), out var statusMessage);
        PersistenceStatus = statusMessage;
        if (saved)
        {
            ShellStatus = "Settings applied to the shell bootstrap.";
        }

        SettingsApplied?.Invoke(this, EventArgs.Empty);
    }

    public void SetShellStatus(string status)
    {
        ShellStatus = status;
    }

    public void SetHotkeyStatus(string status)
    {
        HotkeyStatus = status;
    }

    public SettingsModel ToModel()
    {
        return new SettingsModel
        {
            SourceLanguage = SourceLanguage,
            TargetLanguage = TargetLanguage,
            HotkeyModifiers = HotkeyModifiers,
            HotkeyKey = HotkeyKey,
            IsHotkeyEnabled = IsHotkeyEnabled,
            LaunchAtLoginRequested = LaunchAtLoginRequested,
        };
    }

    private void SetField<T>(ref T field, T value, [CallerMemberName] string? propertyName = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value))
        {
            return;
        }

        field = value;
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}
