# Product notes

## Why this exists

The SQLite scratchpad provides the shortest path from a question about a local
SQLite database to an answer without leaving Neovim. It should feel like an
editor-native feedback loop: write SQL with database-aware assistance, execute
it asynchronously, inspect the result, revise, and repeat while focus remains
on the query.

This is not intended to become a general database administration client. Its
value is a focused, keyboard-driven query workflow with fewer dependencies and
less UI than a full database plugin.

## North-star workflow

1. Open a database target.
2. Write or select the SQL that answers the current question.
3. Execute it without changing focus.
4. Immediately understand whether it succeeded, how long it took, how many
   rows it returned or changed, and whether output was truncated.
5. Inspect or copy values without losing the query draft.
6. Move through prior executions and recover the exact SQL behind each result.
7. Close the scratchpad without affecting unrelated tabs or editor UI.

## Product principles

- **Query-first:** optimize the write/run/inspect/revise loop, not database
  administration.
- **Context stays visible:** always make the database target, execution scope,
  progress, and result-history position clear.
- **No focus theft:** execution and result updates must not move the cursor away
  from the query.
- **Bounded by default, explicit about limits:** limits are a presentation and
  resource boundary, not a SQL rewrite. Execute SQL unchanged, retain bounded
  output, and always disclose truncation.
- **Safe without becoming obstructive:** reads should be frictionless; writes
  should provide enough target and affected-row feedback to prevent mistakes.
- **History is evidence:** an execution keeps its SQL, outcome, timing, and
  timestamp together. Navigating history must not silently destroy a draft.
- **Ephemeral UI, recoverable work:** windows are disposable; useful SQL should
  be easy to recover or intentionally discard.
- **Failures are actionable:** missing tools, locked databases, malformed SQL,
  and cancelled execution should have distinct, useful messages.

## Language

**Scratchpad**:
The temporary editor workspace containing a Query Buffer and Result View for
one Database Target.
_Avoid_: Database client, console

**Database Target**:
The SQLite database file against which a Scratchpad executes SQL.
_Avoid_: Connection (unless a live connection is actually introduced)

**Query Draft**:
The editable SQL in the Query Buffer. It may contain more SQL than the next
Execution Scope.
_Avoid_: Current query

**Execution Scope**:
The exact SQL submitted by one execution, such as a visual selection, the
statement under the cursor, or the complete Query Draft.
_Avoid_: Query when the distinction matters

**Execution Record**:
An immutable history entry joining submitted SQL, returned rows or error,
execution time, timestamp, and truncation or mutation metadata.
_Avoid_: Result (an execution may fail or return no rows)

**Result View**:
The read-only presentation of the selected Execution Record.
_Avoid_: Output buffer

## Current behavior

- `:SQLiteOpen {path}` opens one scratchpad in a dedicated tab. Replacing an
  active scratchpad containing non-whitespace SQL requires an explicit choice
  to cancel or discard the Query Draft.
- `sqls` provides database-aware SQL language support. `:checkhealth sqlite-scratch`
  verifies that `sqlite3` and `sqls` are available directly from `$PATH`.
- Normal-mode `<leader>rr` asynchronously executes the complete Query Buffer;
  visual-mode `<leader>rr` executes the exact selection, including partial
  lines. `<leader>rl` executes the current line.
- Empty or whitespace-only Execution Scopes are rejected before invoking the
  `sqlite3` CLI.
- Results render in a fixed bottom split while query focus is retained. Existing
  SQL files can be opened in the Query Buffer with `:edit` and retain the
  scratchpad mappings and database-aware language support. Successful executions
  without tabular output are reported as completed with no result set; this does
  not imply that zero rows were changed.
- `[r` and `]r` navigate an in-memory history of up to 50 Execution Records.
  Repeating the same SQL with the same retained outcome promotes the latest
  execution instead of adding a duplicate record.
- `<leader>rs` toggles an upper-right SQL preview for the selected Execution
  Record. The preview follows history navigation without changing the Query
  Draft.
- `<leader>rd` deletes the selected Execution Record.
- SQL executes unchanged. Stdout is streamed and drained while at most 30 rows
  and 64 KiB per cell are retained; limited output is identified in the result.
- `:SQLiteExport[!] {path}` reruns the selected Execution Record and streams its
  complete CSV output to a file. Existing files require `!` to overwrite. The
  rerun is explicit because arbitrary SQL may mutate the Database Target.
- `:SQLiteClose` stops the active execution and disposes of the scratchpad.
  Closing its tab, losing either owned window, or replacing the Result View
  buffer performs the same cleanup so no hidden session remains active.

## UX priorities

### Essential

1. **Truthful result status** — show database target, duration, returned or
   affected row count, and whether more rows existed than were displayed.
2. **Value inspection** — allow display-truncated or multiline cells to expose
   their retained value without widening the table. Byte-limited values must
   remain visibly limited and can require a narrower follow-up query.
3. **Write feedback and safety** — report affected rows and make write intent
   clear. Consider a read-only opening mode and an optional confirmation policy
   for destructive statements; do not rely on fragile SQL string matching as a
   safety boundary.
4. **Execution control** — support cancellation and configure a useful SQLite
   busy timeout so a locked database does not look like a hung editor.
5. **Runtime diagnostics** — the health check covers static dependencies;
   opening and execution should still distinguish LSP startup failure, an
   invalid path, and a database that cannot be opened.

### High value

- Add result-local mappings for next/previous record, full-cell inspection,
  and copying a cell or row.
- Offer recent Database Targets and schema discovery for tables, views,
  columns, indexes, and foreign keys. Prefer building on `sqls` where it is
  reliable rather than duplicating it.
- Surface SQLite errors with the relevant statement and location when the CLI
  provides enough information.
- Support `EXPLAIN QUERY PLAN` as a first-class action on the current Execution
  Scope.

### Later, only if real use demands it

- Multiple simultaneous Scratchpads.
- Named parameters and reusable query snippets.
- Persistent execution history.
- Editable result grids or schema migration tooling.

## Future configuration boundary

The row and cell-byte limits are internal policy constants while this remains
personal configuration. If extracted as a plugin, expose resolved limits such
as `result.max_rows` and `result.max_cell_bytes` from `setup()`, then pass them
into the adapter as required execution policy. Keep SQL unchanged regardless of
configuration.

## Non-goals

- Supporting database engines other than SQLite.
- Replacing a migration system or full database administration application.
- Rendering unbounded result sets inside Neovim.
- Parsing all SQLite syntax merely to infer whether arbitrary SQL is safe.

## Open product questions

- Is the primary use case read-only investigation, or frequent data mutation?
- Should opening a nonexistent path intentionally create a database, or require
  an explicit create action?
- Is history valuable across Neovim restarts, or only during one Scratchpad?

Resolve these from actual usage before expanding the implementation. Keep this
file until the workflow stabilizes; then move enduring user documentation to
`docs/` and retain only domain language that remains useful.
