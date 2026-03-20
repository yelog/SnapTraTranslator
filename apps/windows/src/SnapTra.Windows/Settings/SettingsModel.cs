namespace SnapTra.Windows.Settings;

public sealed class SettingsModel
{
    public string SourceLanguage { get; set; } = "en";
    public string TargetLanguage { get; set; } = "zh-Hans";
    public string HotkeyModifiers { get; set; } = "Ctrl+Shift";
    public string HotkeyKey { get; set; } = "T";
    public bool IsHotkeyEnabled { get; set; } = true;
    public bool LaunchAtLoginRequested { get; set; }
}
