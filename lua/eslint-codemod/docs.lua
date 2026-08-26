local M = {}

local cache = {}

function M.clear()
  cache = {}
end

--[[ Fetch https://raw.githubusercontent.com/.../src/commands/<name>.md

  We use `curl` (or `vim.system` with `curl`) for parity with
  `ofetch` in the VSCode extension. The result is cached per `name`
  until `config.autocomplete.docs` changes (caller should clear).
]]
function M.get(name, callback)
  if cache[name] then
    callback(cache[name], nil)
    return
  end

  local url = string.format(
    'https://raw.githubusercontent.com/antfu/eslint-plugin-command/refs/heads/main/src/commands/%s.md',
    name
  )

  if vim.fn.executable 'curl' == 0 then
    callback(nil, 'curl not available')
    return
  end

  vim.system({ 'curl', '-fsSL', url }, { text = true }, function(res)
    vim.schedule(function()
      if res.code ~= 0 then
        callback(nil, res.stderr or 'fetch failed')
        return
      end

      cache[name] = res.stdout
      callback(res.stdout, nil)
    end)
  end)
end

function M.get_sync(name)
  return cache[name]
end

function M.format_fallback(name)
  return string.format('See <https://eslint-plugin-command.antfu.me/commands/%s>', name)
end

return M
