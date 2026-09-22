# Development guidelines

- Keep the plugin focused on the write, run, inspect, and revise SQLite workflow.
- Do not introduce abstractions for other database engines.
- Validate external process and Neovim data at their boundaries; trust established
  internal contracts.
- Model active and inactive scratchpad lifecycle states explicitly.
- Fail visibly on invariant violations and guard genuine asynchronous races.
- Test observable workflows and lifecycle guarantees through real Neovim APIs and
  subprocesses.
- Format Lua with StyLua and run `just check` before committing.
