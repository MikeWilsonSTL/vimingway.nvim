if vim.g.loaded_vimingway then
  return
end
vim.g.loaded_vimingway = true

local actions = { on = "enable", off = "disable", toggle = "toggle" }

vim.api.nvim_create_user_command("Vimingway", function(args)
  local action = actions[args.args ~= "" and args.args or "toggle"]
  if not action then
    vim.notify("Vimingway: expected on, off or toggle", vim.log.levels.ERROR)
    return
  end
  require("vimingway")[action]()
end, {
  nargs = "?",
  complete = function()
    return { "on", "off", "toggle" }
  end,
  desc = "Turn Vimingway highlights on, off, or toggle them",
})
