using System.Drawing;
using System.IO;
using System.Reflection;
using System.Text.Json;
using System.Windows;
using Unbroken.LaunchBox.Plugins;

namespace TeknoParrotManager.LaunchBoxPlugin;

public sealed class TpmSystemMenuItem : ISystemMenuItemPlugin
{
    public string Caption => "TeknoParrot Manager";

    // LaunchBox 14 declares a non-nullable Image property. Keep this tiny
    // icon owned for the plugin process lifetime; LaunchBox never receives a
    // disposable temporary or an arbitrary filesystem path.
    private static readonly Image TpmIcon = CreateIcon();

    public Image IconImage => TpmIcon;

    private static Image CreateIcon()
    {
        var bitmap = new Bitmap(16, 16);
        using var graphics = Graphics.FromImage(bitmap);
        graphics.Clear(Color.FromArgb(26, 32, 44));
        graphics.FillRectangle(Brushes.DeepSkyBlue, 3, 3, 10, 10);
        graphics.FillRectangle(Brushes.White, 6, 6, 4, 4);
        graphics.DrawRectangle(Pens.White, 2, 2, 11, 11);
        return bitmap;
    }

    public bool ShowInBigBox => true;

    public bool ShowInLaunchBox => true;

    public bool AllowInBigBoxWhenLocked => false;

    public void OnSelected()
    {
        try
        {
            var pluginDirectory = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location) ?? AppContext.BaseDirectory;
            var launchBoxRoot = TpmDiscovery.FindLaunchBoxRoot(new[] { AppContext.BaseDirectory, pluginDirectory });
            var settings = ReadSettings(pluginDirectory);
            var discovery = TpmDiscovery.Resolve(
                launchBoxRoot,
                pluginDirectory,
                settings.ScriptPath,
                settings.TeknoParrotRoot);

            if (!discovery.IsSuccess)
            {
                MessageBox.Show(
                    discovery.Summary,
                    "TeknoParrot Manager",
                    MessageBoxButton.OK,
                    MessageBoxImage.Warning);
                return;
            }

            var window = new TpmHealthCheckWindow(
                discovery,
                TpmProcessRunner.FindPowerShell(),
                TimeSpan.FromSeconds(60));
            window.ShowDialog();
        }
        catch (Exception)
        {
            MessageBox.Show(
                "TeknoParrot Manager could not determine a safe read-only integration path.",
                "TeknoParrot Manager",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
        }
    }

    private static PluginSettings ReadSettings(string pluginDirectory)
    {
        var settingsPath = Path.Combine(pluginDirectory, "TeknoParrotManager.LaunchBoxPlugin.json");
        if (!File.Exists(settingsPath))
        {
            return new PluginSettings();
        }

        try
        {
            using var document = JsonDocument.Parse(File.ReadAllText(settingsPath));
            var root = document.RootElement;
            return new PluginSettings
            {
                ScriptPath = ReadOptionalString(root, "tpmScriptPath"),
                TeknoParrotRoot = ReadOptionalString(root, "teknoParrotRoot")
            };
        }
        catch (JsonException)
        {
            return new PluginSettings();
        }
        catch (IOException)
        {
            return new PluginSettings();
        }
        catch (UnauthorizedAccessException)
        {
            return new PluginSettings();
        }
    }

    private static string? ReadOptionalString(JsonElement root, string propertyName)
    {
        return root.TryGetProperty(propertyName, out var property) && property.ValueKind == JsonValueKind.String
            ? property.GetString()
            : null;
    }

    private sealed class PluginSettings
    {
        public string? ScriptPath { get; init; }
        public string? TeknoParrotRoot { get; init; }
    }
}
