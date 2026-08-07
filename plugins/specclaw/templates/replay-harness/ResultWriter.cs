using System.Text.Json;

namespace Replay.Harness;

/// <summary>
/// Writes one actual-result JSON file per replayed scenario, under
/// &lt;run_dir&gt;/actual/&lt;scenario_id&gt;.json. `specclaw-bf-replay compare`
/// reads only this file's `output` field against the fixture's own `output`
/// — do not add capture-timestamp/anchor-date metadata here the way
/// FixtureWriter does for the legacy capture; that metadata belongs to the
/// golden master being replayed against, not to a throwaway replay result.
/// A missing or invalid-JSON file at this path after `dotnet test` runs is
/// itself the ERROR signal `specclaw-bf-replay compare` looks for — if a Fact
/// crashes before calling Write, say nothing and let that absence speak.
/// </summary>
public static class ResultWriter
{
    public static void Write(string scenarioId, object output)
    {
        Directory.CreateDirectory(Paths.ActualDir);

        var path = Path.Combine(Paths.ActualDir, $"{scenarioId}.json");
        File.WriteAllText(
            path,
            JsonSerializer.Serialize(new { scenario_id = scenarioId, output },
                new JsonSerializerOptions { WriteIndented = true }));
    }
}
