using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Lanes.Core;

internal static class ProfileJson
{
    public static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = true,
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };
}

/// <summary>What <c>profiles.json</c> holds. The order of <see cref="Profiles"/> is the order the user sees.</summary>
public sealed class ProfileLibrary
{
    public const int CurrentVersion = 1;

    [JsonPropertyName("version")] public int Version { get; set; } = CurrentVersion;
    [JsonPropertyName("profiles")] public List<Profile> Profiles { get; set; } = new();

    /// <summary>Top-level fields this build does not know, such as the Mac app's scenes.</summary>
    [JsonExtensionData] public Dictionary<string, JsonElement>? KeptFields { get; set; }

    [JsonIgnore] public Profile? DefaultProfile => Profiles.FirstOrDefault(p => p.IsDefault);
    [JsonIgnore] public IEnumerable<Profile> ActiveProfiles => Profiles.Where(p => !p.IsArchived);

    public Profile? Find(string id) => Profiles.FirstOrDefault(p => p.Id == id);

    public void Add(Profile profile)
    {
        if (Find(profile.Id) != null) throw new ProfileStoreException($"Duplicate account id {profile.Id}");
        if (profile.IsDefault && DefaultProfile != null) throw new ProfileStoreException("More than one default account");
        Profiles.Add(profile);
    }

    public void Update(Profile profile)
    {
        var index = Profiles.FindIndex(p => p.Id == profile.Id);
        if (index < 0) throw new ProfileStoreException($"Unknown account {profile.Id}");
        if (profile.IsDefault && DefaultProfile is { } current && current.Id != profile.Id)
            throw new ProfileStoreException("More than one default account");
        Profiles[index] = profile;
    }

    public void Remove(string id)
    {
        if (Profiles.RemoveAll(p => p.Id == id) == 0) throw new ProfileStoreException($"Unknown account {id}");
    }

    public void Move(string id, int newIndex)
    {
        var index = Profiles.FindIndex(p => p.Id == id);
        if (index < 0) throw new ProfileStoreException($"Unknown account {id}");
        var profile = Profiles[index];
        Profiles.RemoveAt(index);
        Profiles.Insert(Math.Clamp(newIndex, 0, Profiles.Count), profile);
    }

    /// <summary>
    /// On first launch, the Claude app's own account becomes "Ana hesap", so
    /// the user sees it at once. Returns true when it added one.
    /// </summary>
    public bool EnsureDefaultProfile(string name)
    {
        if (DefaultProfile != null) return false;
        Profiles.Insert(0, Profile.Create(name, ProfileColors.NextFree(Profiles.Select(p => p.Color)), isDefault: true));
        return true;
    }

    internal void Validate()
    {
        var seen = new HashSet<string>();
        foreach (var profile in Profiles)
        {
            if (!seen.Add(profile.Id)) throw new ProfileStoreException($"Duplicate account id {profile.Id}");
        }
        if (Profiles.Count(p => p.IsDefault) > 1) throw new ProfileStoreException("More than one default account");
    }
}

public sealed class ProfileStoreException(string message) : Exception(message);

/// <summary>
/// Reads and writes <c>profiles.json</c>. Writes go to a temporary file first,
/// so a crash halfway never leaves a broken file. The last list that read is
/// kept as <c>profiles.backup.json</c>, and a file that does not read is set
/// aside instead of overwritten.
/// </summary>
public sealed class ProfileStore(string filePath)
{
    public string FilePath { get; } = filePath;
    public string BackupPath => Path.Combine(Path.GetDirectoryName(FilePath)!, "profiles.backup.json");

    public ProfileLibrary Load()
    {
        if (!File.Exists(FilePath)) return new ProfileLibrary();
        var library = JsonSerializer.Deserialize<ProfileLibrary>(File.ReadAllText(FilePath), ProfileJson.Options)
            ?? throw new ProfileStoreException("profiles.json is empty");
        if (library.Version > ProfileLibrary.CurrentVersion)
            throw new ProfileStoreException($"profiles.json version {library.Version} is newer than this Lanes");
        library.Validate();
        return library;
    }

    /// <summary>Saves the library. Returns where an unreadable old file was moved, or null.</summary>
    public string? Save(ProfileLibrary library, DateTime? now = null)
    {
        library.Validate();
        Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
        var json = JsonSerializer.Serialize(library, ProfileJson.Options);
        string? setAside = null;
        if (File.Exists(FilePath))
        {
            try
            {
                Load();
                File.Copy(FilePath, BackupPath, overwrite: true);
            }
            catch (Exception e) when (e is JsonException or ProfileStoreException)
            {
                setAside = SetAsideUnreadable(now ?? DateTime.Now);
            }
        }
        var temporary = FilePath + ".tmp";
        File.WriteAllText(temporary, json + "\n");
        File.Move(temporary, FilePath, overwrite: true);
        return setAside;
    }

    /// <summary>Renames the file to <c>profiles-unreadable-&lt;date&gt;-&lt;time&gt;.json</c>, adding a counter if taken.</summary>
    public string SetAsideUnreadable(DateTime now)
    {
        var directory = Path.GetDirectoryName(FilePath)!;
        var stem = $"profiles-unreadable-{now:yyyy-MM-dd-HHmmss}";
        var target = Path.Combine(directory, stem + ".json");
        for (var n = 2; File.Exists(target); n++) target = Path.Combine(directory, $"{stem}-{n}.json");
        File.Move(FilePath, target);
        return target;
    }
}
