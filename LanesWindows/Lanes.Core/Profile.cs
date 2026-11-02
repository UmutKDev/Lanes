using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Lanes.Core;

/// <summary>The colours an account can take. Same names as the Mac app.</summary>
[JsonConverter(typeof(JsonStringEnumConverter<ProfileColor>))]
public enum ProfileColor
{
    [JsonStringEnumMemberName("blue")] Blue,
    [JsonStringEnumMemberName("purple")] Purple,
    [JsonStringEnumMemberName("pink")] Pink,
    [JsonStringEnumMemberName("red")] Red,
    [JsonStringEnumMemberName("orange")] Orange,
    [JsonStringEnumMemberName("yellow")] Yellow,
    [JsonStringEnumMemberName("green")] Green,
    [JsonStringEnumMemberName("mint")] Mint,
    [JsonStringEnumMemberName("teal")] Teal,
    [JsonStringEnumMemberName("cyan")] Cyan,
    [JsonStringEnumMemberName("indigo")] Indigo,
    [JsonStringEnumMemberName("brown")] Brown,
    [JsonStringEnumMemberName("gray")] Gray,
}

public static class ProfileColors
{
    /// <summary>The sRGB value of each colour, matching Apple's system colours on the Mac.</summary>
    public static (byte R, byte G, byte B) Rgb(ProfileColor color) => color switch
    {
        ProfileColor.Blue => (0x00, 0x7A, 0xFF),
        ProfileColor.Purple => (0xAF, 0x52, 0xDE),
        ProfileColor.Pink => (0xFF, 0x2D, 0x55),
        ProfileColor.Red => (0xFF, 0x3B, 0x30),
        ProfileColor.Orange => (0xFF, 0x95, 0x00),
        ProfileColor.Yellow => (0xFF, 0xCC, 0x00),
        ProfileColor.Green => (0x34, 0xC7, 0x59),
        ProfileColor.Mint => (0x00, 0xC7, 0xBE),
        ProfileColor.Teal => (0x30, 0xB0, 0xC7),
        ProfileColor.Cyan => (0x32, 0xAD, 0xE6),
        ProfileColor.Indigo => (0x58, 0x56, 0xD6),
        ProfileColor.Brown => (0xA2, 0x84, 0x5E),
        _ => (0x8E, 0x8E, 0x93),
    };

    /// <summary>
    /// Whether text on this colour reads better in black than in white.
    /// Yellow, mint and cyan are too light for white letters.
    /// </summary>
    public static bool PrefersDarkText(ProfileColor color)
    {
        var (r, g, b) = Rgb(color);
        var luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
        return luminance > 0.62;
    }

    /// <summary>The colour a new account gets: the first one no other account uses.</summary>
    public static ProfileColor NextFree(IEnumerable<ProfileColor> used)
    {
        var taken = used.ToHashSet();
        foreach (var color in Enum.GetValues<ProfileColor>())
        {
            if (!taken.Contains(color)) return color;
        }
        return ProfileColor.Blue;
    }
}

/// <summary>
/// One Claude account. The JSON matches the Mac app's <c>profiles.json</c>, and
/// fields this build does not know are kept and written back unchanged.
/// </summary>
public sealed class Profile
{
    public const string DefaultMode = "standard";
    public const string DefaultAccountClass = "personal";

    [JsonPropertyName("id")] public string Id { get; set; } = NewId();
    [JsonPropertyName("name")] public string Name { get; set; } = "";
    [JsonPropertyName("monogram")] public string Monogram { get; set; } = "?";
    [JsonPropertyName("color")] public ProfileColor Color { get; set; } = ProfileColor.Blue;

    /// <summary>Kept for the Mac app. Windows has only one way to open an account.</summary>
    [JsonPropertyName("mode")] public string Mode { get; set; } = DefaultMode;
    [JsonPropertyName("accountClass")] public string AccountClass { get; set; } = DefaultAccountClass;

    /// <summary>
    /// The default account uses Claude's own data folder and <c>~/.claude</c>,
    /// so the account the user already signed in to keeps working untouched.
    /// </summary>
    [JsonPropertyName("isDefault")] public bool IsDefault { get; set; }

    [JsonPropertyName("createdAt"), JsonConverter(typeof(Iso8601DateConverter))]
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;

    [JsonPropertyName("email"), JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? Email { get; set; }

    [JsonPropertyName("note"), JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? Note { get; set; }

    [JsonPropertyName("isArchived")] public bool IsArchived { get; set; }

    /// <summary>The folder "Claude Code" starts in when no other is chosen. Null means the home folder.</summary>
    [JsonPropertyName("defaultProjectFolder"), JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? DefaultProjectFolder { get; set; }

    /// <summary>Whether the account's Claude Code uses <c>~/.claude</c> instead of a folder of its own.</summary>
    [JsonPropertyName("usesSharedClaudeCode")] public bool UsesSharedClaudeCode { get; set; }

    /// <summary>Fields this build could not read, as they were written.</summary>
    [JsonExtensionData] public Dictionary<string, JsonElement>? KeptFields { get; set; }

    public static string NewId() => Guid.NewGuid().ToString().ToLowerInvariant();

    /// <summary>First letter of the name, upper-cased with Turkish rules ("işler" becomes "İ").</summary>
    public static string DefaultMonogram(string name)
    {
        var trimmed = name.Trim();
        if (trimmed.Length == 0) return "?";
        var first = StringInfo.GetNextTextElement(trimmed);
        return first.ToUpper(new CultureInfo("tr-TR"));
    }

    public static Profile Create(string name, ProfileColor color, bool isDefault = false) => new()
    {
        Name = name,
        Monogram = DefaultMonogram(name),
        Color = color,
        IsDefault = isDefault,
        CreatedAt = TruncatedNow(),
    };

    /// <summary>Renames the account. A monogram that only followed the old name follows the new one.</summary>
    public void Rename(string newName)
    {
        var followsName = Monogram == DefaultMonogram(Name);
        Name = newName;
        if (followsName) Monogram = DefaultMonogram(newName);
    }

    public Profile Clone()
    {
        var json = JsonSerializer.Serialize(this, ProfileJson.Options);
        return JsonSerializer.Deserialize<Profile>(json, ProfileJson.Options)!;
    }

    /// <summary>The Mac app writes whole seconds; a fraction would not read there.</summary>
    internal static DateTimeOffset TruncatedNow()
    {
        var now = DateTimeOffset.UtcNow;
        return new DateTimeOffset(now.Ticks - now.Ticks % TimeSpan.TicksPerSecond, TimeSpan.Zero);
    }
}

/// <summary>Reads and writes ISO 8601 dates the way Swift's <c>.iso8601</c> strategy does.</summary>
public sealed class Iso8601DateConverter : JsonConverter<DateTimeOffset>
{
    public override DateTimeOffset Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        var text = reader.GetString() ?? throw new JsonException("Date is null");
        return DateTimeOffset.Parse(text, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal);
    }

    public override void Write(Utf8JsonWriter writer, DateTimeOffset value, JsonSerializerOptions options) =>
        writer.WriteStringValue(value.UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture));
}
