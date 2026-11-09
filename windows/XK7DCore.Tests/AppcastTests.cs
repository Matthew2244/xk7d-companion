namespace XK7D.Core.Tests;

/// <summary>The Windows app's quiet update check reads the same appcast WinSparkle installs from.</summary>
public class AppcastTests
{
    const string Feed = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
          <channel>
            <title>XK-7D Companion</title>
            <item>
              <title>Version 1.10.0</title>
              <sparkle:version>1.10.0</sparkle:version>
              <enclosure url="https://example.invalid/a.exe" sparkle:os="windows" sparkle:edSignature="x" length="1" type="application/octet-stream"/>
            </item>
            <item>
              <title>Version 1.9.2</title>
              <sparkle:version>1.9.2</sparkle:version>
              <enclosure url="https://example.invalid/b.exe" sparkle:os="windows" sparkle:edSignature="x" length="1" type="application/octet-stream"/>
            </item>
            <item>
              <title>Version 9.0.0 for the Mac</title>
              <sparkle:version>9.0.0</sparkle:version>
              <enclosure url="https://example.invalid/c.zip" sparkle:os="macos" sparkle:edSignature="x" length="1" type="application/octet-stream"/>
            </item>
          </channel>
        </rss>
        """;

    [Fact]
    public void NewestWindowsVersionWins() => Assert.Equal("1.10.0", Appcast.NewestIn(Feed));

    [Fact]
    public void NoVersionsMeansNull() =>
        Assert.Null(Appcast.NewestIn("<rss xmlns:sparkle=\"http://www.andymatuschak.org/xml-namespaces/sparkle\"><channel/></rss>"));

    [Theory]
    [InlineData("1.10.0", "1.9.2", 1)]
    [InlineData("1.1", "1.1.0", 0)]
    [InlineData("v1.1.0", "1.1.0", 0)]
    [InlineData("1.0.4", "1.1.0", -1)]
    [InlineData("2.0.0", "10.0.0", -1)]
    public void VersionsCompareNumerically(string a, string b, int expected) => Assert.Equal(expected, Math.Sign(Appcast.Compare(a, b)));
}
