local M = {}

local defaults = {
  enable = true,
  languageIds = { '*' },
  autocomplete = {
    autoFix = true,
    docs = false,
    diff = true,
    onlyFixable = true,
  },
  alias = {
    ['hoist-regexp'] = { 'hreg' },
    ['inline-arrow'] = { 'ia' },
    ['no-shorthand'] = { 'nsh' },
    ['no-type'] = { 'nt' },
    ['reverse-if-else'] = { 'rife', 'rif' },
    ['to-arrow'] = { '2a' },
    ['to-destructuring'] = { '2dest' },
    ['to-function'] = { '2f' },
    ['to-one-line'] = { '21l' },
    ['to-promise-all'] = { '2pa' },
    ['to-string-literal'] = { '2string-literal', '2sl' },
    ['to-template-literal'] = { '2template-literal', '2tl' },
    ['to-ternary'] = { '23' },
  },
}

local config = vim.deepcopy(defaults)

function M.get()
  return config
end

function M.defaults()
  return vim.deepcopy(defaults)
end

--[[ Merge user options into the current config. ]]
function M.setup(opts)
  if not opts then
    return
  end

  if opts.enable ~= nil then
    config.enable = opts.enable
  end

  if opts.languageIds ~= nil then
    config.languageIds = opts.languageIds
  end

  if opts.autocomplete ~= nil then
    config.autocomplete = vim.tbl_deep_extend('force', config.autocomplete, opts.autocomplete)
  end

  if opts.alias ~= nil then
    config.alias = vim.tbl_deep_extend('force', {}, config.alias, opts.alias)

    --[[ Allow per-command alias override as string or array. ]]
    for k, v in pairs(config.alias) do
      if type(v) == 'string' then
        config.alias[k] = { v }
      end
    end
  end
end

function M.reset()
  config = vim.deepcopy(defaults)
end

function M.is_language_enabled(filetype)
  local ids = config.languageIds
  if not ids or #ids == 0 then
    return true
  end

  for _, id in ipairs(ids) do
    if id == '*' or id == filetype then
      return true
    end
  end

  return false
end

return M
