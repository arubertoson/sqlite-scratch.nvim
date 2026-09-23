# sqlite-scratch.nvim

Write SQL, run it, inspect the answer, and keep your hands in Neovim.

`sqlite-scratch.nvim` is a focused SQLite query workspace. It opens a database in a
dedicated tab with an editable query buffer and a stable result view. Executions are
asynchronous, history keeps the SQL beside its outcome, and useful results can be
exported without turning the editor into a database administration suite.

## Status

This is personal software published in the open because inspectable tools are better
tools. It is built around how I use Neovim and SQLite. It has no compatibility
promise, public roadmap, support commitment, or contribution process.

The repository is source-available, not open source. No license to copy, modify, or
redistribute the code is granted. See [LICENSE](LICENSE).

## Why it exists

The useful SQLite loop is small:

1. open a database;
2. write or select the SQL that answers the current question;
3. run it without moving focus away from the query;
4. inspect the result, timing, limits, and exact submitted SQL;
5. revise and run again.

Full database clients optimize for administration. This plugin optimizes for that
loop.

## Requirements

- Neovim 0.11 or newer;
- [`sqlite3`](https://sqlite.org/cli.html) on `$PATH`;
- [`sqls`](https://github.com/sqls-server/sqls) on `$PATH` for database-aware SQL
  language support.

Run `:checkhealth sqlite-scratch` to verify the external tools.

## Installation

Using Neovim's built-in package manager:

```lua
vim.pack.add({
    { src = "https://github.com/arubertoson/sqlite-scratch.nvim" },
})

require("sqlite-scratch").setup()
```

`setup()` registers the commands and enables the scratchpad's buffer-local
mappings by default. Set `keymaps = false` to use your own bindings:

```lua
require("sqlite-scratch").setup({ keymaps = false })
```

## Usage

Open a database:

```vim
:SQLiteOpen path/to/database.db
```

The scratchpad installs these buffer-local mappings (execution navigation works in
both the query and result buffers; the remaining actions are query-buffer-only):

| Mapping | Action |
| --- | --- |
| `<leader>rr` | Run the complete query buffer, or the visual selection in Visual mode |
| `<leader>rl` | Run the current line |
| `[r` / `]r` | Previous / next execution record (query and result buffers) |
| `<leader>rs` | Toggle the exact SQL for the selected execution |
| `<leader>rd` | Delete the selected execution record |

Commands:

| Command | Action |
| --- | --- |
| `:SQLiteOpen {path}` | Open or replace the active scratchpad |
| `:SQLiteExport[!] {path}` | Rerun the selected SQL and stream complete CSV output to a file |
| `:SQLiteClose` | Stop active work and close the scratchpad |

The plugin installs no global mappings. For navigation while another buffer is
focused, map `require("sqlite-scratch").navigate(delta)` explicitly; use
`require("sqlite-scratch").is_visible()` to check whether the scratchpad tab is current.

Opening another target asks before discarding a non-empty draft. Closing the owned
tab or either owned window performs the same cleanup as `:SQLiteClose`.

## Execution model

- SQL is passed to `sqlite3` unchanged.
- Output is streamed so the process cannot block on a full pipe.
- The result view retains at most 30 rows and 64 KiB per cell and reports when data
  was limited.
- History retains 50 execution records in memory, including SQL, outcome, duration,
  timestamp, and truncation state.
- Export reruns the selected SQL because display output is deliberately bounded.
  This matters when the SQL mutates data.
- Each scratchpad starts a dedicated `sqls` client configured for its database.

## Non-goals

- database engines other than SQLite;
- schema administration or migration management;
- editable result grids;
- persistent query history;
- parsing SQL to guess whether it is safe;
- rendering unbounded result sets in Neovim.

## Development

With Neovim, Mise, and Just installed:

```sh
just setup
just check
```

`just check` verifies formatting and runs the test suite in headless Neovim.

Detailed product notes: [`docs/product.md`](docs/product.md).
