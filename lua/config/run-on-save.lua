--[[ Project run-on-save: BufWritePost → `.nvim/settings.json` → match → run. ]]

local M = {}

-- root → { mtime, rules }
local cache = {}

local function load_rules(filepath)
  local nvim_dir = vim.fs.find('.nvim', { upward = true, path = vim.fs.dirname(filepath), type = 'directory' })[1]
  if not nvim_dir then
    return
  end
  local root = vim.fs.dirname(nvim_dir)
  local conf = vim.fs.joinpath(nvim_dir, 'settings.json')
  local mtime = vim.fn.getftime(conf)
  if mtime < 0 then
    return
  end

  local hit = cache[root]
  if hit and hit.mtime == mtime then
    return hit.rules, root
  end

  local ok, data = pcall(function()
    return vim.json.decode(table.concat(vim.fn.readfile(conf), '\n'))
  end)
  local map = ok and type(data) == 'table' and data.runOnSave
  if type(map) ~= 'table' then
    return
  end

  local rules = {}
  for pattern, cmds in pairs(map) do
    if type(pattern) == 'string' and type(cmds) == 'table' then
      local list = {}
      for _, c in ipairs(cmds) do
        if type(c) == 'string' and c ~= '' then
          list[#list + 1] = c
        end
      end
      if #list > 0 then
        rules[#rules + 1] = { reg = vim.fn.glob2regpat(pattern), cmds = list }
      end
    end
  end
  cache[root] = { mtime = mtime, rules = rules }
  return rules, root
end

local function reload(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) or vim.bo[bufnr].modified then
    return
  end
  local view = vim.api.nvim_get_current_buf() == bufnr and vim.fn.winsaveview() or nil
  vim.api.nvim_buf_call(bufnr, function()
    vim.cmd 'silent! edit!'
  end)
  if view then
    vim.fn.winrestview(view)
  end
end

local function run_cmds(cmds, filepath, root, bufnr)
  local opts = { cwd = root, text = true }
  local function step(i)
    local cmd = cmds[i]
    if not cmd then
      reload(bufnr)
      return
    end
    cmd = cmd:gsub('%${{filepath}}', filepath)
    vim.system({ vim.o.shell, vim.o.shellcmdflag, cmd }, opts, function(obj)
      vim.schedule(function()
        if obj.code == 0 then
          step(i + 1)
        else
          reload(bufnr)
        end
      end)
    end)
  end
  step(1)
end

function M.setup()
  vim.api.nvim_create_autocmd('BufWritePost', {
    group = vim.api.nvim_create_augroup('RunOnSave', { clear = true }),
    callback = function(ev)
      local path = vim.api.nvim_buf_get_name(ev.buf)
      if path == '' or vim.fn.filereadable(path) == 0 then
        return
      end
      local rules, root = load_rules(path)
      if not rules then
        return
      end
      local rel = path:sub(#root + 2)
      for _, r in ipairs(rules) do
        if vim.fn.match(rel, r.reg) >= 0 or vim.fn.match(vim.fs.basename(path), r.reg) >= 0 then
          run_cmds(r.cmds, path, root, ev.buf)
        end
      end
    end,
  })
end

return M
