using Microsoft.UI.Xaml;

namespace SnapTra.Windows.Settings;

public sealed partial class SettingsWindow : Window
{
    public SettingsWindow(SettingsViewModel viewModel)
    {
        ViewModel = viewModel;
        InitializeComponent();
        RootGrid.DataContext = ViewModel;
        Title = "SnapTra Translator Settings";
    }

    public SettingsViewModel ViewModel { get; }

    private void OnSaveClicked(object sender, RoutedEventArgs e)
    {
        ViewModel.Save();
    }

    private void OnCloseClicked(object sender, RoutedEventArgs e)
    {
        Close();
    }
}
