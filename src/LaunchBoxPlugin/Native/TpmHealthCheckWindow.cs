using System.ComponentModel;
using System.Text;
using System.Windows;
using System.Windows.Controls;

namespace TeknoParrotManager.LaunchBoxPlugin;

public sealed class TpmHealthCheckWindow : Window
{
    private readonly TpmDiscoveryResult _discovery;
    private readonly string _powershellPath;
    private readonly TimeSpan _timeout;
    private readonly TextBlock _status;
    private readonly Button _cancelButton;
    private readonly CancellationTokenSource _cancellation = new();
    private bool _isRunning = true;
    private bool _closeRequested;

    public TpmHealthCheckWindow(TpmDiscoveryResult discovery, string powershellPath, TimeSpan timeout)
    {
        _discovery = discovery;
        _powershellPath = powershellPath;
        _timeout = timeout;
        Title = "TeknoParrot Manager - Read-only Health Check";
        Width = 560;
        Height = 360;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        ResizeMode = ResizeMode.NoResize;

        var layout = new StackPanel { Margin = new Thickness(18) };
        layout.Children.Add(new TextBlock
        {
            Text = "Phase 0 native integration (read-only)",
            FontSize = 17,
            FontWeight = FontWeights.SemiBold,
            Margin = new Thickness(0, 0, 0, 12)
        });
        _status = new TextBlock
        {
            Text = "Starting bounded TPM health check...",
            TextWrapping = TextWrapping.Wrap,
            MinHeight = 210
        };
        layout.Children.Add(_status);
        _cancelButton = new Button
        {
            Content = "Cancel",
            Width = 100,
            HorizontalAlignment = HorizontalAlignment.Right,
            Margin = new Thickness(0, 14, 0, 0)
        };
        _cancelButton.Click += CancelButtonOnClick;
        layout.Children.Add(_cancelButton);
        Content = layout;
        Loaded += OnLoaded;
        Closing += OnClosing;
        Closed += OnClosed;
    }

    private async void OnLoaded(object sender, RoutedEventArgs e)
    {
        TpmFrontendResult result;
        try
        {
            result = await TpmProcessRunner.RunHealthCheckAsync(
                _powershellPath,
                _discovery.ScriptPath!,
                _discovery.TeknoParrotRoot!,
                _discovery.UserProfilesDirectory!,
                _timeout,
                _cancellation.Token);
        }
        catch (Exception)
        {
            result = TpmFrontendResultFactory.Failure(
                null,
                "PLUGIN_FAILED",
                "The LaunchBox integration failed closed before the TPM operation could complete.");
        }

        _isRunning = false;
        if (_closeRequested)
        {
            Close();
            return;
        }

        _cancelButton.Content = "Close";
        _status.Text = FormatResult(result);
    }

    private void OnClosing(object? sender, CancelEventArgs e)
    {
        if (!_isRunning)
        {
            return;
        }

        e.Cancel = true;
        _closeRequested = true;
        _status.Text = "Cancelling the TPM process...";
        _cancelButton.IsEnabled = false;
        _cancellation.Cancel();
    }

    private void OnClosed(object? sender, EventArgs e)
    {
        _cancellation.Dispose();
    }

    private void CancelButtonOnClick(object sender, RoutedEventArgs e)
    {
        if (_isRunning)
        {
            _status.Text = "Cancelling the TPM process...";
            _cancelButton.IsEnabled = false;
            _cancellation.Cancel();
            return;
        }
        Close();
    }

    private static string FormatResult(TpmFrontendResult result)
    {
        var text = new StringBuilder();
        text.AppendLine(result.Summary);
        text.AppendLine();
        text.Append("Status: ").AppendLine(result.Status);
        text.Append("Error code: ").AppendLine(result.ErrorCode);
        foreach (var evidence in result.Evidence)
        {
            text.Append(evidence.Name).Append(": ").AppendLine(evidence.Value.ToString());
        }
        if (result.Warnings.Count > 0)
        {
            text.AppendLine();
            text.AppendLine("Warnings:");
            foreach (var warning in result.Warnings.Distinct(StringComparer.Ordinal))
            {
                text.Append("- ").AppendLine(warning);
            }
        }
        return text.ToString();
    }
}
