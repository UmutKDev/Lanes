using System.Text;

namespace Lanes.Core;

/// <summary>Splits and builds Windows command lines with the rules of <c>CommandLineToArgvW</c>.</summary>
public static class CommandLine
{
    public static List<string> Split(string commandLine)
    {
        var args = new List<string>();
        var current = new StringBuilder();
        var inQuotes = false;
        var hasToken = false;
        var i = 0;
        // The program name ends at the next space, or at the closing quote; backslashes are literal there.
        if (commandLine.Length > 0)
        {
            if (commandLine[0] == '"')
            {
                var end = commandLine.IndexOf('"', 1);
                args.Add(end < 0 ? commandLine[1..] : commandLine[1..end]);
                i = end < 0 ? commandLine.Length : end + 1;
            }
            else
            {
                var end = commandLine.IndexOfAny([' ', '\t']);
                args.Add(end < 0 ? commandLine : commandLine[..end]);
                i = end < 0 ? commandLine.Length : end;
            }
        }
        while (i < commandLine.Length)
        {
            var c = commandLine[i];
            if (c == '\\')
            {
                var slashes = 0;
                while (i < commandLine.Length && commandLine[i] == '\\') { slashes++; i++; }
                if (i < commandLine.Length && commandLine[i] == '"')
                {
                    current.Append('\\', slashes / 2);
                    if (slashes % 2 == 1) { current.Append('"'); i++; }
                }
                else
                {
                    current.Append('\\', slashes);
                }
                hasToken = true;
                continue;
            }
            if (c == '"')
            {
                if (inQuotes && i + 1 < commandLine.Length && commandLine[i + 1] == '"')
                {
                    current.Append('"');
                    i += 2;
                    continue;
                }
                inQuotes = !inQuotes;
                hasToken = true;
                i++;
                continue;
            }
            if ((c == ' ' || c == '\t') && !inQuotes)
            {
                if (hasToken) { args.Add(current.ToString()); current.Clear(); hasToken = false; }
                i++;
                continue;
            }
            current.Append(c);
            hasToken = true;
            i++;
        }
        if (hasToken) args.Add(current.ToString());
        return args;
    }

    /// <summary>The value of a <c>--name=value</c> or <c>--name value</c> switch, or null.</summary>
    public static string? SwitchValue(IReadOnlyList<string> args, string name)
    {
        for (var i = 1; i < args.Count; i++)
        {
            if (args[i].StartsWith(name + "=", StringComparison.OrdinalIgnoreCase)) return args[i][(name.Length + 1)..];
            if (string.Equals(args[i], name, StringComparison.OrdinalIgnoreCase) && i + 1 < args.Count) return args[i + 1];
        }
        return null;
    }

    public static bool HasSwitch(IReadOnlyList<string> args, string name) =>
        args.Skip(1).Any(a => string.Equals(a, name, StringComparison.OrdinalIgnoreCase) || a.StartsWith(name + "=", StringComparison.OrdinalIgnoreCase));

    /// <summary>Quotes one argument so <see cref="Split"/> gives it back unchanged.</summary>
    public static string Quote(string arg)
    {
        if (arg.Length > 0 && arg.IndexOfAny([' ', '\t', '"']) < 0) return arg;
        var sb = new StringBuilder("\"");
        var slashes = 0;
        foreach (var c in arg)
        {
            if (c == '\\') { slashes++; continue; }
            if (c == '"') { sb.Append('\\', slashes * 2 + 1).Append('"'); slashes = 0; continue; }
            sb.Append('\\', slashes).Append(c);
            slashes = 0;
        }
        sb.Append('\\', slashes * 2).Append('"');
        return sb.ToString();
    }
}
