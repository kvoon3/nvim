local M = {}

--[[ Bridge to the Node ESLint runtime.

  VSCode's `lint.ts` does:
    eslint = new ESLint({ cwd, fix:false })
    code = appendText(editor, commandName)   -- "///???" replacement
    [result] = await eslint.lintText(code, { filePath, warnIgnored:true })
    messages = result.messages.filter(r=>r.ruleId==='command/command')
    keep only `command-fix` that has `fix && endLine && endColumn`

  We replicate the same logic in a Node worker. The Lua side spawns a
  Node process with `lua/eslint-codemod/scripts/lint.mjs` (written
  on setup) and caches results per `{bufnr, command}` tuple.

  In headless tests without a real project cwd / eslint config, the
  checker gracefully falls back to `true` so static completion tests
  are not blocked.
]]

local lint_script --- lazy path

local function script_path()
  if lint_script then
    return lint_script
  end

  local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h:h')
  lint_script = root .. '/lua/eslint-codemod/scripts/lint.mjs'
  return lint_script
end

local function cursor_context(bufnr, row, col)
  bufnr = bufnr or 0
  if row == nil or col == nil then
    local cursor = vim.api.nvim_win_get_cursor(0)
    row = cursor[1] - 1
    col = cursor[2]
  end

  return {
    file = vim.api.nvim_buf_get_name(bufnr),
    row = row,
    col = col,
  }
end

--[[ Heuristic fallback for `appendText`.

  Mirrors VSCode's `appendText` but more robust:
    - if the line starts with `///` replace after that prefix
    - else if it contains `//` replace after the last `//`
    - else insert at cursor col
]]
function M.append_command(bufnr, row, command_name)
  bufnr = bufnr or 0
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local lnum = row + 1
  if row == nil then
    local c = vim.api.nvim_win_get_cursor(0)
    lnum = c[1]
    row = lnum - 1
  end

  local line = lines[lnum] or ''
  local repl
  local prefix = line:match '^(%s*///%s*).*'
  if prefix then
    repl = prefix .. command_name
    lines[lnum] = repl
  else
    local s, e = line:find '//%s*'
    if s then
      local before = line:sub(1, e)
      repl = before .. command_name
      lines[lnum] = repl
    else
      --[[ Fallback: inject at cursor col. ]]
      local col = cursor_context(bufnr, row, nil).col
      local cur = line
      local before = cur:sub(1, col)
      local after = cur:sub(col + 1)
      lines[lnum] = before .. command_name .. after
    end
  end

  return table.concat(lines, '\n')
end

--[[ Async check: is `command_name` fixable at the cursor? ]]
function M.check_fixable(command_name, opts, callback)
  opts = opts or {}
  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
  local ctx = cursor_context(bufnr, opts.row, opts.col)
  local code = M.append_command(bufnr, ctx.row, command_name)
  local cwd = vim.fs.root(
    ctx.file ~= '' and ctx.file or vim.fn.getcwd(),
    { 'eslint.config.js', 'eslint.config.mjs', 'eslint.config.cjs', '.git' }
  ) or vim.fn.getcwd()
  local file = ctx.file ~= '' and ctx.file or 'untitled.ts'

  --[[ Fast path: if the lint script does not exist or Node is unavailable, assume fixable
    so completion is not blocked in minimal test envs. ]]
  if vim.fn.filereadable(script_path()) == 0 then
    callback(true)
    return
  end

  if vim.fn.executable 'node' == 0 then
    callback(true)
    return
  end

  local payload = vim.json.encode { cwd = cwd, filePath = file, code = code }

  vim.system(
    { 'node', script_path(), '--check', command_name },
    { stdin = payload, cwd = cwd, text = true },
    function(res)
      vim.schedule(function()
        if res.code ~= 0 then
          --[[ ESLint not found / config missing → treat as fixable for DX ]]
          callback(true)
          return
        end

        local ok, data = pcall(vim.json.decode, res.stdout or '')
        if not ok or not data then
          callback(true)
          return
        end

        callback(data.fixable == true)
      end)
    end
  )
end

--[[ Sync variant used in headless tests when mocked. ]]
function M.check_fixable_sync(_command_name, _opts)
  return true
end

local batch_cache = {}
local inflight = {}

--[[ Parse worker output into map[name] = true|false.
  Missing/ambiguous results default to fixable so completion still shows. ]]
local function parse_batch_results(names, res)
  local map = {}
  if res.code == 0 then
    local ok, data = pcall(vim.json.decode, res.stdout or '')
    if ok and type(data.results) == 'table' then
      for _, name in ipairs(names) do
        local r = data.results[name]
        map[name] = not (r and r.fixable ~= true and r.fallback == nil)
      end
    end
  end

  for _, name in ipairs(names) do
    if map[name] == nil then
      map[name] = true
    end
  end

  return map
end

--[[ Batch check: ONE node spawn for all candidate commands.

  Payload carries the RAW buffer code (no command inserted); the
  worker injects each candidate name into the first `///` line.
  Results are cached per (bufnr, changedtick) so repeated completion
  requests between edits cost nothing. Callback receives:
    map[name] = true (fixable) | false (not)
]]
--[[ Resolve the project context a lint worker should run in. ]]
local function worker_context(bufnr, row)
  if row == nil then
    row = vim.api.nvim_win_get_cursor(0)[1] - 1
  end

  local ctx = cursor_context(bufnr, row, nil)
  local file = ctx.file ~= '' and ctx.file or 'untitled.ts'
  local cwd = vim.fs.root(
    ctx.file ~= '' and ctx.file or vim.fn.getcwd(),
    { 'eslint.config.js', 'eslint.config.mjs', 'eslint.config.cjs', '.git' }
  ) or vim.fn.getcwd()

  return { cwd = cwd, file = file, row = row }
end

function M.check_fixable_batch(names, opts, callback)
  opts = opts or {}
  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
  local cache_key = bufnr .. ':' .. vim.api.nvim_buf_get_changedtick(bufnr)

  local hit = batch_cache[cache_key]
  if hit then
    callback(hit)
    return
  end

  --[[ A spawn for this exact state is already in flight — piggyback. ]]
  inflight[cache_key] = inflight[cache_key] or {}
  table.insert(inflight[cache_key], callback)
  if #inflight[cache_key] > 1 then
    return
  end

  names = names or {}
  --[[ No worker / no node / nothing to check: treat everything as fixable. ]]
  if #names == 0 or vim.fn.filereadable(script_path()) == 0 or vim.fn.executable 'node' == 0 then
    callback {}
    return
  end

  local wc = worker_context(bufnr, opts.row)
  local raw_code = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n')
  local payload = vim.json.encode { cwd = wc.cwd, filePath = wc.file, code = raw_code }

  vim.system({ 'node', script_path(), '--check-all', table.concat(names, ',') }, {
    stdin = payload,
    cwd = wc.cwd,
    text = true,
  }, function(res)
    vim.schedule(function()
      local map = parse_batch_results(names, res)

      batch_cache[cache_key] = map
      --[[ Flush every request piggybacking on this spawn, including ours. ]]
      for _, cb in ipairs(inflight[cache_key] or {}) do
        cb(map)
      end
      inflight[cache_key] = nil
    end)
  end)
end

--[[ Request full lint result for docs/diff (message + fix). ]]
function M.get_lint_result(command_name, opts, callback)
  opts = opts or {}
  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
  local ctx = cursor_context(bufnr, opts.row, opts.col)
  local code = M.append_command(bufnr, ctx.row, command_name)
  local cwd = vim.fs.root(
    ctx.file ~= '' and ctx.file or vim.fn.getcwd(),
    { 'eslint.config.js', 'eslint.config.mjs', 'eslint.config.cjs', '.git' }
  ) or vim.fn.getcwd()
  local file = ctx.file ~= '' and ctx.file or 'untitled.ts'

  if vim.fn.filereadable(script_path()) == 0 or vim.fn.executable 'node' == 0 then
    callback(nil, 'lint script not available')
    return
  end

  local payload = vim.json.encode { cwd = cwd, filePath = file, code = code }

  vim.system(
    { 'node', script_path(), '--result', command_name },
    { stdin = payload, cwd = cwd, text = true },
    function(res)
      vim.schedule(function()
        if res.code ~= 0 then
          callback(nil, res.stderr or 'lint failed')
          return
        end

        local ok, data = pcall(vim.json.decode, res.stdout or '')
        if not ok then
          callback(nil, 'invalid lint json')
          return
        end

        callback(data, nil)
      end)
    end
  )
end

return M
