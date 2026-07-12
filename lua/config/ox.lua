--[[ Toggle oxfmt + oxlint together; persist choice across restarts. ]]

local M = {}

local STATE = vim.fs.joinpath(vim.fn.stdpath('state'), 'ox.json')

M.enabled = true

--[[ Apply enabled to both tools; optionally start/stop oxlint LSP. ]]
local function apply(enabled, opts)
  opts = opts or {}
  M.enabled = enabled
  require('config.oxfmt').enabled = enabled

  local oxlint = require('config.oxlint')
  oxlint.enabled = enabled
  if opts.lsp and oxlint.is_available() then
    vim.lsp.enable('oxlint', enabled)
    if not enabled then
      for _, client in ipairs(vim.lsp.get_clients({ name = 'oxlint' })) do
        client:stop(true)
      end
    end
  end
end

local function save()
  vim.fn.mkdir(vim.fn.stdpath('state'), 'p')
  vim.fn.writefile({ vim.json.encode({ enabled = M.enabled }) }, STATE)
end

--[[ Restore flags before oxfmt/oxlint setup (no LSP side effects). ]]
function M.load()
  if vim.fn.filereadable(STATE) ~= 1 then
    return
  end
  local ok, data = pcall(vim.json.decode, table.concat(vim.fn.readfile(STATE), '\n'))
  if ok and type(data) == 'table' and type(data.enabled) == 'boolean' then
    apply(data.enabled)
  end
end

function M.enable()
  apply(true, { lsp = true })
  save()
  vim.notify('Ox: on', vim.log.levels.INFO)
end

function M.disable()
  apply(false, { lsp = true })
  save()
  vim.notify('Ox: off', vim.log.levels.INFO)
end

function M.toggle()
  if M.enabled then
    M.disable()
  else
    M.enable()
  end
end

return M
