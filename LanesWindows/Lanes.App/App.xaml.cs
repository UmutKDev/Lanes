using System.IO.Pipes;
using System.Windows;
using Lanes.App.Platform;
using Lanes.Core;

namespace Lanes.App;

public partial class App : Application
{
    const string MutexName = "UmutKDev.Lanes.Instance";
    const string PipeName = "UmutKDev.Lanes.Pipe";

    Mutex? mutex;
    AppController? controller;
    TrayIcon? tray;
    MainWindow? window;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        var args = LanesArguments.Parse(e.Args);
        Native.SetCurrentProcessExplicitAppUserModelID("UmutKDev.Lanes");

        if (args.SelfTestDirectory != null)
        {
            _ = SelfTest.Run(args.SelfTestDirectory).ContinueWith(t => Dispatcher.Invoke(() => Shutdown(t.Result)));
            return;
        }

        mutex = new Mutex(true, MutexName, out var first);
        if (!first)
        {
            SendToRunning(args.ToMessage());
            Shutdown();
            return;
        }

        controller = new AppController(ProfilePaths.Standard());
        controller.Start();
        tray = new TrayIcon(controller, ShowWindow, Quit);
        _ = ListenAsync();

        if (args.OpenProfileId != null) Handle(args);
        else if (!args.StartHidden) ShowWindow();
    }

    void Handle(LanesArguments args)
    {
        if (args.OpenProfileId != null && controller!.Library.Find(args.OpenProfileId) is { } profile)
            controller.Open(profile);
        else
            ShowWindow();
    }

    void ShowWindow()
    {
        window ??= new MainWindow(controller!);
        window.Closed += (_, _) => window = null;
        window.Show();
        if (window.WindowState == WindowState.Minimized) window.WindowState = WindowState.Normal;
        window.Activate();
    }

    void Quit()
    {
        tray?.Dispose();
        Shutdown();
    }

    static void SendToRunning(string message)
    {
        try
        {
            // Lets the running Lanes bring a Claude window forward for us.
            Native.AllowSetForegroundWindow(Native.ASFW_ANY);
            using var pipe = new NamedPipeClientStream(".", PipeName, PipeDirection.Out);
            pipe.Connect(2000);
            using var writer = new StreamWriter(pipe);
            writer.WriteLine(message);
        }
        catch (Exception) { /* the running Lanes is busy quitting */ }
    }

    async Task ListenAsync()
    {
        while (true)
        {
            try
            {
                await using var pipe = new NamedPipeServerStream(PipeName, PipeDirection.In, 1, PipeTransmissionMode.Byte, PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
                await pipe.WaitForConnectionAsync();
                using var reader = new StreamReader(pipe);
                var line = await reader.ReadLineAsync();
                if (line != null) await Dispatcher.InvokeAsync(() => Handle(LanesArguments.FromMessage(line)));
            }
            catch (IOException) { await Task.Delay(500); }
        }
    }

    protected override void OnExit(ExitEventArgs e)
    {
        tray?.Dispose();
        mutex?.Dispose();
        base.OnExit(e);
    }
}
