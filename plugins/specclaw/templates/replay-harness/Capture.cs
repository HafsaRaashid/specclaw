namespace Replay.Harness;

/// <summary>
/// Records whether a call threw, and what it threw, in exactly the shape
/// .specclaw/baseline/fixtures/GM-*.json's own `output` records it — so a
/// fixture captured from the legacy app and an actual result captured here
/// from the new app are structurally comparable field-for-field. Do not
/// rename these fields; `specclaw-replay compare` reads `ExceptionType`/
/// `InnerExceptionType` by name (and compares them by short type name only,
/// tolerating a legacy->new namespace rename such as ADR-0002's
/// `ExecutivePlanning.Core` -> the new repo's own Core namespace).
/// </summary>
public sealed record CaptureResult(
    bool Threw,
    string? ExceptionType,
    string? Message,
    string? InnerExceptionType,
    string? InnerExceptionMessage);

public static class Capture
{
    public static CaptureResult Run(Action action)
    {
        try
        {
            action();
            return new CaptureResult(false, null, null, null, null);
        }
        catch (Exception ex)
        {
            return new CaptureResult(
                true, ex.GetType().FullName, ex.Message,
                ex.InnerException?.GetType().FullName, ex.InnerException?.Message);
        }
    }

    public static async Task<CaptureResult> RunAsync(Func<Task> action)
    {
        try
        {
            await action();
            return new CaptureResult(false, null, null, null, null);
        }
        catch (Exception ex)
        {
            return new CaptureResult(
                true, ex.GetType().FullName, ex.Message,
                ex.InnerException?.GetType().FullName, ex.InnerException?.Message);
        }
    }

    /// <summary>
    /// Same shape, for a call that produces a value on success rather than
    /// only side effects — the value is captured separately by the caller
    /// (via ResultWriter.Write's own `output` parameter) since its shape
    /// varies per scenario; this only reports the throw/no-throw half.
    /// </summary>
    public static async Task<(CaptureResult Capture, T? Value)> RunAsync<T>(Func<Task<T>> action)
    {
        try
        {
            var value = await action();
            return (new CaptureResult(false, null, null, null, null), value);
        }
        catch (Exception ex)
        {
            return (new CaptureResult(
                true, ex.GetType().FullName, ex.Message,
                ex.InnerException?.GetType().FullName, ex.InnerException?.Message), default);
        }
    }
}
