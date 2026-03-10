# taskwarrior.nvim

taskwarrior.nvim is a Neovim plugin for editing Taskwarrior tasks in a buffer.

## Current behavior

Running `:Task` opens a table-style buffer backed by Taskwarrior:

```text
ID  Status    Project       Description
12  pending   taskwarrior   Build initial buffer UI
↳                          that wraps under the description column
18  waiting   personal      Call dentist
+   pending   ·             ·
```

You can also pass Taskwarrior filters directly to the command:

```vim
:Task project:other
:Task +work
```

The buffer stays scoped to those filters on later refreshes and writes.

In v1, only these columns are editable:
- `Status`
- `Project`
- `Description`

Then use `:write` inside the buffer to sync changes back to Taskwarrior.

Supported status edits:
- `pending`
- `waiting`
- `done`

`done` is treated as a completion action and maps to `task <uuid> done`.

Creation and deletion:
- Delete an existing row to delete that task from Taskwarrior.
- Edit the `+` row and replace the `·` placeholders to create a new task.
- Empty fields use `·` so word motions like `w` and `b` have something concrete to land on.

Color coding:
- pending rows use a simple informational color
- waiting rows use a secondary accent color
- the new task row and placeholders are dimmed
- wrapped description continuation rows are dimmed and aligned under `Description`

## Requirements

- Neovim with `vim.system` support
- [Taskwarrior](https://taskwarrior.org/) installed
- `task` available in your `PATH`

If `task` is not installed or not in `PATH`, the `:Task` command fails with a clear error.

## Installation with lazy.nvim

```lua
{
  "armmahajan/taskwarrior.nvim",
  version = "*",
}
```

If you prefer to pin the initial release explicitly:

```lua
{
  "armmahajan/taskwarrior.nvim",
  tag = "v0.0.1",
}
```

## Usage

- Run `:Task` to open the Taskwarrior buffer.
- Pass Taskwarrior filters directly to the command, for example `:Task project:other` or `:Task +work`.
- Use `:write` inside the buffer to sync edits back to Taskwarrior.

## Project layout

- `plugin/taskwarrior.lua`: command registration
- `lua/taskwarrior/init.lua`: public entrypoint
- `lua/taskwarrior/buffer.lua`: buffer lifecycle and save flow
- `lua/taskwarrior/render.lua`: table rendering and parsing
- `lua/taskwarrior/backend.lua`: Taskwarrior CLI integration

## Notes

- Task identity is tracked internally by `uuid`, not the displayed ID column.
- New tasks currently start as `pending`.
