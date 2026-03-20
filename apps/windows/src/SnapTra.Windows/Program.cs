using Microsoft.UI.Xaml;
using WinRT;

namespace SnapTra.Windows;

internal static class Program
{
    [STAThread]
    private static void Main(string[] args)
    {
        ComWrappersSupport.InitializeComWrappers();

        Application.Start(_ =>
        {
            _ = new App();
        });
    }
}
