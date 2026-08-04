using System.Runtime.CompilerServices;

namespace Replay.Harness;

/// <summary>
/// Resolves this run directory's own on-disk location using [CallerFilePath]
/// captured at compile time, so path resolution is stable regardless of the
/// working directory `dotnet test` actually runs from (typically the build
/// output folder, e.g. bin/Debug/net8.0, not this source directory) — same
/// trick as the baseline capture harness's own Paths.cs.
/// </summary>
public static class Paths
{
    private static string ThisFileDirectory([CallerFilePath] string path = "") => Path.GetDirectoryName(path)!;

    /// <summary>This run's own directory: .specclaw/replay/run-&lt;timestamp&gt;.</summary>
    public static readonly string RunDir = ThisFileDirectory();

    /// <summary>Where ResultWriter writes actual-&lt;scenario_id&gt;.json files.</summary>
    public static readonly string ActualDir = Path.Combine(RunDir, "actual");
}
