using System.Text;
using Lanes.Core;

public class LaunchTests
{
    static readonly ProfilePaths Paths = new(@"C:\Users\u\AppData\Local\Lanes", @"C:\Users\u\AppData\Roaming", @"C:\Users\u");

    static (ProfileLibrary, Profile main, Profile work) Library()
    {
        var library = new ProfileLibrary();
        var main = Profile.Create("Ana hesap", ProfileColor.Blue, isDefault: true);
        var work = Profile.Create("İş", ProfileColor.Red);
        work.Id = "11111111-2222-3333-4444-555555555555";
        library.Add(main);
        library.Add(work);
        return (library, main, work);
    }

    [Fact]
    public void DefaultAccountOpensPlainClaude()
    {
        var (_, main, _) = Library();
        var plan = LaunchPlanner.Plan(main, @"C:\x\claude.exe", Paths);
        Assert.Empty(plan.Arguments);
        Assert.Empty(plan.EnvironmentAdditions);
        Assert.Equal(["CLAUDE_CONFIG_DIR"], plan.EnvironmentRemovals);
        Assert.Empty(plan.DirectoriesToCreate);
    }

    [Fact]
    public void OtherAccountsGetTheirOwnFolders()
    {
        var (_, _, work) = Library();
        var plan = LaunchPlanner.Plan(work, @"C:\x\claude.exe", Paths);
        var data = @"C:\Users\u\AppData\Roaming\Claude-Lanes-11111111-2222-3333-4444-555555555555";
        var code = @"C:\Users\u\AppData\Local\Lanes\Profiles\11111111-2222-3333-4444-555555555555\ClaudeCode";
        Assert.Equal([$"--user-data-dir={data}"], plan.Arguments);
        Assert.Equal(code, plan.EnvironmentAdditions["CLAUDE_CONFIG_DIR"]);
        Assert.Empty(plan.EnvironmentRemovals);
        Assert.Equal([data, code], plan.DirectoriesToCreate);
    }

    [Fact]
    public void SharedClaudeCodeSetsNoVariable()
    {
        var (_, _, work) = Library();
        work.UsesSharedClaudeCode = true;
        var plan = LaunchPlanner.Plan(work, @"C:\x\claude.exe", Paths);
        Assert.Empty(plan.EnvironmentAdditions);
        Assert.Single(plan.DirectoriesToCreate);
    }

    [Fact]
    public void MatchesRunningProcessesToAccounts()
    {
        var (library, main, work) = Library();
        var exe = @"C:\Users\u\AppData\Local\AnthropicClaude\app-4.4212.0\claude.exe";
        var processes = new[]
        {
            new ClaudeProcess(10, $"\"{exe}\" "),
            new ClaudeProcess(11, $"\"{exe}\" --type=renderer --user-data-dir=\"C:\\Users\\u\\AppData\\Roaming\\Claude\""),
            new ClaudeProcess(12, $"\"{exe}\" --user-data-dir=\"C:\\Users\\U\\AppData\\Roaming\\Claude-Lanes-11111111-2222-3333-4444-555555555555\\\""),
            new ClaudeProcess(13, $"\"{exe}\" --user-data-dir=\"C:\\Someone\\Else\""),
        };
        var running = ClaudeInstances.Match(processes, library, Paths);
        Assert.Equal(2, running.Count);
        Assert.Equal((main.Id, 10), (running[0].ProfileId, running[0].Pid));
        Assert.Equal((work.Id, 12), (running[1].ProfileId, running[1].Pid));
    }

    [Fact]
    public void DetectsTheInstallation()
    {
        var local = @"C:\Users\u\AppData\Local";
        var standard = ClaudeInstallation.Detect(local, p => p == local + @"\AnthropicClaude\claude.exe", _ => []);
        Assert.Equal(new ClaudeInstallation.Standard(local + @"\AnthropicClaude\claude.exe"), standard);

        var store = ClaudeInstallation.Detect(local, _ => false, _ => [local + @"\Packages\Microsoft.Foo", local + @"\Packages\Claude_pzs8sxrjxfjjc"]);
        Assert.IsType<ClaudeInstallation.StorePackage>(store);

        Assert.IsType<ClaudeInstallation.Missing>(ClaudeInstallation.Detect(local, _ => false, _ => []));
    }

    [Theory]
    [InlineData("plain")]
    [InlineData("with space")]
    [InlineData("quote\"inside")]
    [InlineData(@"C:\trailing\")]
    [InlineData(@"C:\with space\")]
    [InlineData(@"back\\""slash")]
    [InlineData("")]
    public void QuoteSurvivesSplit(string value)
    {
        var line = $"\"C:\\a b\\x.exe\" {CommandLine.Quote(value)} next";
        Assert.Equal(["C:\\a b\\x.exe", value, "next"], CommandLine.Split(line));
    }

    [Fact]
    public void SplitReadsSwitches()
    {
        var args = CommandLine.Split("claude.exe --user-data-dir \"D:\\p q\" --flag");
        Assert.Equal(@"D:\p q", CommandLine.SwitchValue(args, "--user-data-dir"));
        Assert.True(CommandLine.HasSwitch(args, "--flag"));
        Assert.Null(CommandLine.SwitchValue(args, "--other"));
    }

    [Fact]
    public void ClaudeCodeScriptSetsTheFolderAndQuotes()
    {
        var (_, main, work) = Library();
        work.Name = "Ali'nin işi";
        var script = ClaudeCodeCommand.PowerShellScript(work, Paths, @"D:\Proje 1", ["--resume", "x'y"]);
        Assert.StartsWith("$env:CLAUDE_CONFIG_DIR = 'C:\\Users\\u\\AppData\\Local\\Lanes\\Profiles\\", script);
        Assert.Contains("'Claude Code · Ali''nin işi'", script);
        Assert.Contains("Set-Location -LiteralPath 'D:\\Proje 1'; claude '--resume' 'x''y'", script);

        var plain = ClaudeCodeCommand.PowerShellScript(main, Paths, null);
        Assert.StartsWith("Remove-Item Env:CLAUDE_CONFIG_DIR", plain);
        Assert.DoesNotContain("Set-Location", plain);
        Assert.EndsWith("claude", plain);

        var wt = ClaudeCodeCommand.WindowsTerminalArguments(work, "powershell.exe", script);
        Assert.Equal("#FF3B30", wt[wt.IndexOf("--tabColor") + 1]);
        Assert.Equal(script, Encoding.Unicode.GetString(Convert.FromBase64String(wt[^1])));
    }

    [Fact]
    public void TaskbarIdentityIsStablePerAccount()
    {
        var (_, _, work) = Library();
        var id = TaskbarIdentity.For(work, @"C:\Program Files\Lanes\Lanes.exe", @"C:\i.ico");
        Assert.Equal("UmutKDev.Lanes.Account.11111111222233334444555555555555", id.AppUserModelId);
        Assert.True(id.AppUserModelId.Length <= 128);
        Assert.Equal("\"C:\\Program Files\\Lanes\\Lanes.exe\" --open 11111111-2222-3333-4444-555555555555", id.RelaunchCommand);
    }

    [Fact]
    public void LanesArgumentsRoundTrip()
    {
        var args = LanesArguments.Parse(["--open", "abc", "--hidden"]);
        Assert.Equal("abc", args.OpenProfileId);
        Assert.True(args.StartHidden);
        Assert.Equal("abc", LanesArguments.FromMessage(args.ToMessage()).OpenProfileId);
        Assert.Null(LanesArguments.FromMessage("show").OpenProfileId);
    }
}
