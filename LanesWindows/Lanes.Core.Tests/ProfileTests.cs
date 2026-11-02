using System.Text.Json;
using Lanes.Core;

public class ProfileTests
{
    const string MacFile = """
    {
      "profiles" : [
        {
          "accountClass" : "personal",
          "color" : "orange",
          "createdAt" : "2026-10-30T12:00:00Z",
          "id" : "a1",
          "isDefault" : true,
          "mode" : "signedClone",
          "monogram" : "A",
          "name" : "Ana hesap",
          "linkedFolders" : ["/Users/umut/x"],
          "limitedUntil" : "2026-11-01T00:00:00Z"
        },
        {
          "accountClass" : "client",
          "color" : "teal",
          "createdAt" : "2026-10-31T08:30:15Z",
          "id" : "b2",
          "isDefault" : false,
          "mode" : "standard",
          "monogram" : "İ",
          "name" : "işler",
          "email" : "a@b.com"
        }
      ],
      "scenes" : [ { "id" : "s1", "name" : "Sabah", "profileIDs" : ["a1"] } ],
      "version" : 1
    }
    """;

    [Fact]
    public void ReadsTheMacFileAndKeepsWhatItDoesNotKnow()
    {
        var dir = Directory.CreateTempSubdirectory().FullName;
        var store = new ProfileStore(Path.Combine(dir, "profiles.json"));
        File.WriteAllText(store.FilePath, MacFile);

        var library = store.Load();
        Assert.Equal(2, library.Profiles.Count);
        Assert.Equal("a1", library.DefaultProfile!.Id);
        Assert.Equal(ProfileColor.Teal, library.Profiles[1].Color);
        Assert.Equal("signedClone", library.Profiles[0].Mode);
        Assert.Equal(new DateTimeOffset(2026, 10, 31, 8, 30, 15, TimeSpan.Zero), library.Profiles[1].CreatedAt);

        library.Profiles[1].Rename("Müşteri");
        store.Save(library);

        using var saved = JsonDocument.Parse(File.ReadAllText(store.FilePath));
        var root = saved.RootElement;
        Assert.Equal("Sabah", root.GetProperty("scenes")[0].GetProperty("name").GetString());
        var first = root.GetProperty("profiles")[0];
        Assert.Equal("/Users/umut/x", first.GetProperty("linkedFolders")[0].GetString());
        Assert.Equal("2026-11-01T00:00:00Z", first.GetProperty("limitedUntil").GetString());
        Assert.Equal("2026-10-30T12:00:00Z", first.GetProperty("createdAt").GetString());
        var second = root.GetProperty("profiles")[1];
        Assert.Equal("Müşteri", second.GetProperty("name").GetString());
        Assert.Equal("M", second.GetProperty("monogram").GetString());
        Assert.True(File.Exists(store.BackupPath));
    }

    [Fact]
    public void SetsAsideAFileItCannotReadInsteadOfOverwritingIt()
    {
        var dir = Directory.CreateTempSubdirectory().FullName;
        var store = new ProfileStore(Path.Combine(dir, "profiles.json"));
        File.WriteAllText(store.FilePath, "{ not json");
        Assert.ThrowsAny<JsonException>(() => store.Load());

        var library = new ProfileLibrary();
        library.EnsureDefaultProfile("Ana hesap");
        var aside = store.Save(library, new DateTime(2026, 11, 2, 17, 5, 9));

        Assert.EndsWith("profiles-unreadable-2026-11-02-170509.json", aside);
        Assert.Equal("{ not json", File.ReadAllText(aside!));
        Assert.Single(store.Load().Profiles);
    }

    [Fact]
    public void RefusesANewerFileAndTwoDefaults()
    {
        var dir = Directory.CreateTempSubdirectory().FullName;
        var store = new ProfileStore(Path.Combine(dir, "profiles.json"));
        File.WriteAllText(store.FilePath, """{ "version": 2, "profiles": [] }""");
        Assert.Throws<ProfileStoreException>(() => store.Load());

        var library = new ProfileLibrary();
        library.Add(Profile.Create("A", ProfileColor.Blue, isDefault: true));
        Assert.Throws<ProfileStoreException>(() => library.Add(Profile.Create("B", ProfileColor.Red, isDefault: true)));
    }

    [Fact]
    public void MonogramUsesTurkishCase()
    {
        Assert.Equal("İ", Profile.DefaultMonogram("  işler"));
        Assert.Equal("I", Profile.DefaultMonogram("ılık"));
        Assert.Equal("?", Profile.DefaultMonogram("  "));
    }

    [Fact]
    public void RenameKeepsAHandPickedMonogram()
    {
        var p = Profile.Create("Okul", ProfileColor.Blue);
        p.Monogram = "★";
        p.Rename("İş");
        Assert.Equal("★", p.Monogram);
    }

    [Fact]
    public void FirstLaunchAddsTheMainAccountOnce()
    {
        var library = new ProfileLibrary();
        Assert.True(library.EnsureDefaultProfile("Ana hesap"));
        Assert.False(library.EnsureDefaultProfile("Ana hesap"));
        Assert.Equal("Ana hesap", library.Profiles.Single().Name);
        Assert.Equal(ProfileColor.Blue, library.Profiles.Single().Color);
    }

    [Fact]
    public void NewAccountsTakeTheFirstFreeColor()
    {
        Assert.Equal(ProfileColor.Pink, ProfileColors.NextFree([ProfileColor.Blue, ProfileColor.Purple]));
        Assert.True(ProfileColors.PrefersDarkText(ProfileColor.Yellow));
        Assert.False(ProfileColors.PrefersDarkText(ProfileColor.Indigo));
    }

    [Fact]
    public void NewDatesHaveWholeSecondsForTheMacApp()
    {
        var p = Profile.Create("A", ProfileColor.Blue);
        Assert.Equal(0, p.CreatedAt.Ticks % TimeSpan.TicksPerSecond);
    }
}
