using System.Text.Json;

namespace {{harness_namespace}};

/// <summary>
/// Writes one golden-master fixture JSON file per scenario, in the exact
/// shape `specclaw-bf-baseline record` expects: flat top-level scalar metadata
/// fields (captured_at, anchor_date, legacy_commit_sha, runtime_version)
/// plus a flat `normalized_fields` string array, so they can be extracted
/// with a simple grep/sed pass on the bash side — no JSON parser needed
/// there. Do not rename these fields or nest them differently; doing so
/// breaks `specclaw-bf-baseline record`'s field extraction and the resulting
/// manifest.json will silently show them as empty/unknown, not error.
/// </summary>
public static class FixtureWriter
{
    /// <summary>
    /// The anchor date every scenario's relative dates (e.g. "deadline =
    /// anchor + 3 days") should be computed from, so a replay on a
    /// different calendar day reproduces the same absolute dates. Read
    /// once per capture run — do not call DateTime.UtcNow per scenario.
    /// </summary>
    public static readonly DateTime AnchorDate = DateTime.UtcNow.Date;

    public static void Write(
        string scenarioId,
        string fixturesDir,
        object input,
        object output,
        IEnumerable<string>? normalizedFields = null)
    {
        Directory.CreateDirectory(fixturesDir);

        var fixture = new
        {
            scenario_id = scenarioId,
            captured_at = DateTime.UtcNow.ToString("o"),
            anchor_date = AnchorDate.ToString("yyyy-MM-dd"),
            legacy_commit_sha = GetLegacyCommitSha(),
            runtime_version = Environment.Version.ToString(),
            normalized_fields = (normalizedFields ?? Array.Empty<string>()).ToArray(),
            input,
            output
        };

        var path = Path.Combine(fixturesDir, $"{scenarioId}.json");
        File.WriteAllText(
            path,
            JsonSerializer.Serialize(fixture, new JsonSerializerOptions { WriteIndented = true }));
    }

    private static string GetLegacyCommitSha()
    {
        try
        {
            var psi = new System.Diagnostics.ProcessStartInfo("git", "rev-parse --short HEAD")
            {
                RedirectStandardOutput = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };
            using var proc = System.Diagnostics.Process.Start(psi);
            if (proc is null) return "unknown";
            var sha = proc.StandardOutput.ReadToEnd().Trim();
            proc.WaitForExit();
            return string.IsNullOrEmpty(sha) ? "unknown" : sha;
        }
        catch
        {
            return "unknown";
        }
    }
}
