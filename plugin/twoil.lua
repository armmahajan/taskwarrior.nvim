vim.api.nvim_create_user_command("Task", function(opts)
  require("twoil").open(opts.fargs)
end, {
  desc = "Open the TWOil Taskwarrior buffer",
  nargs = "*",
})

vim.cmd([[cnoreabbrev <expr> task ((getcmdtype() == ':' && getcmdline() == 'task') ? 'Task' : 'task')]])
