vim.api.nvim_create_user_command("Task", function(opts)
  require("taskwarrior").open(opts.fargs)
end, {
  desc = "Open the taskwarrior.nvim Taskwarrior buffer",
  nargs = "*",
})

vim.cmd([[cnoreabbrev <expr> task ((getcmdtype() == ':' && getcmdline() == 'task') ? 'Task' : 'task')]])
