using System.Text.Json;

namespace SnapTra.Windows.Settings;

public sealed class SettingsStore
{
    private static readonly JsonSerializerOptions SerializerOptions = new()
    {
        WriteIndented = true,
    };

    private readonly string _settingsDirectory;
    private readonly string _settingsPath;

    public SettingsStore()
    {
        _settingsDirectory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "SnapTraTranslator"
        );
        _settingsPath = Path.Combine(_settingsDirectory, "settings.json");
    }

    public SettingsModel Load()
    {
        try
        {
            if (!File.Exists(_settingsPath))
            {
                return new SettingsModel();
            }

            var json = File.ReadAllText(_settingsPath);
            return JsonSerializer.Deserialize<SettingsModel>(json, SerializerOptions) ?? new SettingsModel();
        }
        catch
        {
            return new SettingsModel();
        }
    }

    public bool TrySave(SettingsModel settings, out string statusMessage)
    {
        try
        {
            Directory.CreateDirectory(_settingsDirectory);
            var json = JsonSerializer.Serialize(settings, SerializerOptions);
            File.WriteAllText(_settingsPath, json);
            statusMessage = $"Settings saved to {_settingsPath}";
            return true;
        }
        catch (Exception exception)
        {
            statusMessage = $"Settings could not be saved: {exception.Message}";
            return false;
        }
    }
}
