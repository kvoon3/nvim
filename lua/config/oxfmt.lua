--[[ Oxfmt integration: default config + format-on-save for the current buffer. ]]

local M = {}

local DEFAULT_CONFIG = vim.fn.stdpath('config') .. '/config/oxfmt/.oxfmtrc.jsonc'

local FILETYPES = {
  javascript = true,
  javascriptreact = true,
  typescript = true,
  typescriptreact = true,
  json = true,
  jsonc = true,
  json5 = true,
  yaml = true,
  html = true,
  vue = true,
  css = true,
  scss = true,
  less = true,
  markdown = true,
  graphql = true,
  toml = true,
  handlebars = true,
}

local PROJECT_CONFIG_NAMES = {
  '.oxfmtrc.json',
  '.oxfmtrc.jsonc',
  'oxfmt.config.ts',
}

--[[ Resolve project oxfmt config by walking up from the file, or nil. ]]
local function find_project_config(filepath)
  if filepath == nil or filepath == '' then
    return nil
  end
  local found = vim.fs.find(PROJECT_CONFIG_NAMES, {
    path = filepath,
    upward = true,
    type = 'file',
  })[1]
  return found
end

function M.supports_filetype(ft)
  return FILETYPES[ft] == true
end

function M.is_available()
  return vim.fn.executable('oxfmt') == 1
end

--[[ Format the given buffer with oxfmt (current file only). Uses project config when present, else the Neovim default config. ]]
function M.format_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end
  if vim.bo[bufnr].buftype ~= '' then
    return false
  end
  if not M.supports_filetype(vim.bo[bufnr].filetype) then
    return false
  end
  if not M.is_available() then
    return false
  end

  local filepath = vim.api.nvim_buf_get_name(bufnr)
  if filepath == '' then
    return false
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local input = table.concat(lines, '\n')
  if vim.bo[bufnr].eol then
    input = input .. '\n'
  end

  local cmd = { 'oxfmt', '--stdin-filepath', filepath }
  local project_config = find_project_config(filepath)
  if project_config then
    -- Explicit path keeps resolution stable when cwd differs from the file tree.
    vim.list_extend(cmd, { '-c', project_config })
  elseif vim.fn.filereadable(DEFAULT_CONFIG) == 1 then
    vim.list_extend(cmd, { '-c', DEFAULT_CONFIG })
  end

  local result = vim.system(cmd, { stdin = input, text = true }):wait()
  if result.code ~= 0 then
    local err = (result.stderr or result.stdout or 'unknown error'):gsub('%s+$', '')
    if err ~= '' then
      vim.notify('oxfmt: ' .. err, vim.log.levels.WARN)
    end
    return false
  end

  local formatted = result.stdout
  if formatted == nil or formatted == input then
    return true
  end

  local new_lines = vim.split(formatted, '\n', { plain = true })
  if new_lines[#new_lines] == '' then
    table.remove(new_lines)
  end

  local view = vim.fn.winsaveview()
  pcall(vim.cmd, 'undojoin')
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)
  vim.fn.winrestview(view)
  return true
end

function M.setup()
  vim.api.nvim_create_autocmd('BufWritePre', {
    group = vim.api.nvim_create_augroup('OxfmtFormatOnSave', { clear = true }),
    callback = function(ev)
      if not M.supports_filetype(vim.bo[ev.buf].filetype) then
        return
      end
      M.format_buffer(ev.buf)
    end,
    desc = 'Format current buffer with oxfmt on save',
  })
end

return M
