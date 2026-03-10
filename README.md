# TWOil

TWOil is a local Neovim plugin for editing Taskwarrior tasks in a buffer.

## Current behavior

Running `:Task` opens a table-style buffer backed by Taskwarrior:

```text
ID  Status    Project       Description
12  pending   twoil         Build initial buffer UI
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

## Plugin layout

- `plugin/twoil.lua`: command registration
- `lua/twoil/init.lua`: public entrypoint
- `lua/twoil/buffer.lua`: buffer lifecycle and save flow
- `lua/twoil/render.lua`: table rendering and parsing
- `lua/twoil/backend.lua`: Taskwarrior CLI integration

## Local setup with lazy.nvim

```lua
{
  dir = "/Users/armaanmahajan/Projects/TWOil",
  name = "twoil",
  lazy = false,
}
```

## Notes

- Task identity is tracked internally by `uuid`, not the displayed ID column.
- New tasks currently start as `pending`.
- If `task` is not installed or not in `PATH`, the command fails with a clear error.
