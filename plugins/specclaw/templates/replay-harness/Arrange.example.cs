using Microsoft.EntityFrameworkCore;
using ManagerPlanner.Core.Data;      // rename to the new repo's own actual namespace —
using ManagerPlanner.Core.Domain;    // this file is a WORKED, VERIFIED example from one real
using ManagerPlanner.Core.Services;  // project (manager-planner-mod), not a literal include.

namespace Replay.Harness;

/// <summary>
/// WORKED EXAMPLE for the replay-mapper agent to imitate, not a file to copy verbatim into
/// every run — it demonstrates the required shape for one real fixture (GM-019: "ChangeStatusAsync
/// same-status transition is a no-op") against one real repo's actual current source, and has
/// been confirmed to actually build and pass against that repo. Before generating real Facts from
/// this pattern:
///   1. Confirm the new repo's actual namespace, DbContext type name, EF Core provider, and —
///      important, and easy to get wrong by analogy with the legacy harness — whether its service
///      layer takes a DbContext directly or an IDbContextFactory&lt;T&gt; (this repo's own
///      PlanningService takes the factory, per ADR-0002's DbContext-lifetime consequence for
///      Blazor Server; the legacy app's equivalent took a DbContext directly — read the actual
///      constructor, don't assume either shape). Confirm by reading the DbContext factory /
///      Program.cs directly (e.g. `Data/PlanningDbContextFactory.cs`, `Program.cs`'s
///      `UseSqlite(...)`/`Database.Migrate()` call) — do not assume this example's
///      `ManagerPlanner.Core`/`UseSqlite`/factory-based construction still matches by the time you
///      read this; ADR-0003/decisions.md's SQ-002 already flag persistence as a point of active
///      change (SQLite today, a decided-but-maybe-not-yet-built move to Postgres).
///   2. Confirm entities with no service method (e.g. User creation here — the new repo has no
///      `AddUserAsync`, per outstanding CQ-004/no auth model yet) are seeded via direct
///      `DbContext` manipulation, matching seams.md's "Data/persistence boundary" pattern, not
///      invented against a method that doesn't exist.
///   3. Replace every hardcoded value below with the SELECTED FIXTURE's own `input` fields —
///      never hand-pick different values than what was actually captured.
///   4. Where the seam has an injectable "now" override (e.g. a validator's `nowUtc` parameter),
///      pin it to the fixture's own `anchor_date`. Where it does not (e.g. `ChangeStatusAsync`'s
///      internal `DateTime.UtcNow` write), this fixture is NOT REPLAYABLE — do not attempt to
///      work around a missing clock by guessing at what "now" would produce.
/// </summary>
public class GM019Tests
{
    private static PlanningService NewService(out PlanningDbContext seedDb)
    {
        // Migrations, per ADR-0003 — never EnsureCreated. The arrange path itself is under
        // test: if a migration is missing or wrong, this Fact should fail loudly, not silently
        // fall back to a schema built ad hoc. One connection stays open for the whole test so
        // the in-memory database survives across the several short-lived DbContexts the real
        // service opens per call (see TestDbContextFactory.cs).
        var connection = new Microsoft.Data.Sqlite.SqliteConnection("DataSource=:memory:");
        connection.Open();
        var options = new DbContextOptionsBuilder<PlanningDbContext>()
            .UseSqlite(connection)
            .Options;

        seedDb = new PlanningDbContext(options);
        seedDb.Database.Migrate();

        var factory = new TestDbContextFactory<PlanningDbContext>(options);
        return new PlanningService(factory);
    }

    [Fact]
    public async Task GM_019_ChangeStatus_to_same_status_is_noop()
    {
        var svc = NewService(out var seedDb);

        // Arrange: a manager (no AddUserAsync exists — seed directly, per seams.md's
        // Data/persistence boundary pattern), a project, and one task.
        var manager = new User { FullName = "Manager", Email = "mgr@test", Role = UserRole.Manager };
        seedDb.Users.Add(manager);
        await seedDb.SaveChangesAsync();

        var project = await svc.AddProjectAsync("Proj", "desc", manager.Id);
        var task = await svc.AddTaskAsync(project.Id, "Task", null, null, null, false, null);

        // Act: input.fromStatus == input.toStatus == "NotStarted" for this fixture — the task
        // is already NotStarted by default, so this really is a same-status call.
        var capture = await Capture.RunAsync(async () =>
            await svc.ChangeStatusAsync(task.Id, WorkItemStatus.NotStarted, manager.Id));

        // Capture the fixture's own declared output shape — here, just the StatusChange count
        // (the no-op guard means it must stay zero).
        var statusHistoryCount = await seedDb.StatusChanges.CountAsync(s => s.WorkItemId == task.Id);

        ResultWriter.Write("GM-019", new { statusHistoryCount });

        // A basic sanity assertion is fine (the legacy behavior is already known from
        // scenarios.md) — but MATCH/DIVERGES itself is never decided here or by this assertion;
        // `specclaw-bf-replay compare` does that mechanically against the fixture afterward.
        // ChangeStatusAsync returns plain Task (no value), so Capture.RunAsync resolves to the
        // non-generic overload here — `capture` is a CaptureResult directly, not a tuple.
        Assert.False(capture.Threw);
    }
}
