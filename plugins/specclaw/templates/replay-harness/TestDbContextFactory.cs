using Microsoft.EntityFrameworkCore;

namespace Replay.Harness;

/// <summary>
/// Generic <see cref="IDbContextFactory{TContext}"/> wrapping one already-open connection, for
/// services (like a Blazor Server app's own) that take a factory and open/dispose a short-lived
/// DbContext per call rather than holding one for their own lifetime — confirmed necessary here
/// because the new repo's service layer follows exactly that pattern (see its own constructor);
/// the legacy app's equivalent service took a `DbContext` directly and needs no such wrapper.
/// Fully generic and repo-agnostic — do not add repo-specific logic here; that belongs in the
/// generated Arrange code, not this fixed helper.
/// </summary>
public sealed class TestDbContextFactory<TContext> : IDbContextFactory<TContext>
    where TContext : DbContext
{
    private readonly DbContextOptions<TContext> _options;

    public TestDbContextFactory(DbContextOptions<TContext> options) => _options = options;

    public TContext CreateDbContext() =>
        (TContext)Activator.CreateInstance(typeof(TContext), _options)!;
}
