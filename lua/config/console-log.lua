local ls = require 'luasnip'

local M = {}
local methods = { 'log', 'warn', 'error', 'info', 'debug', 'table' }
local filetypes = { 'typescript', 'typescriptreact', 'javascript', 'javascriptreact', 'vue' }

function M.format(method, expression)
  --[[ Build a console call whose label mirrors the expression. ]]
  if method == 'table' then
    return 'console.table(' .. expression .. ')'
  end
  local quote, unquoted = expression:match '^([\'"])(.*)%1$'
  if quote and not unquoted:find '\\' then
    return 'console.' .. method .. "('" .. unquoted:gsub("'", "\\'") .. "')"
  end
  local label = expression:gsub('\\', '\\\\'):gsub("'", "\\'")
  return 'console.' .. method .. "('" .. label .. "', " .. expression .. ')'
end

for _, ft in ipairs(filetypes) do
  local snippets = {}
  for _, method in ipairs(methods) do
    local console_method = method
    snippets[#snippets + 1] = ls.s(
      { trig = '^([ \t]*)([%w_.$%[%]\'"`]+)%.' .. console_method, regTrig = true, wordTrig = false },
      ls.d(1, function(_, parent)
        local indent = parent.snippet.captures[1]
        local expression = parent.snippet.captures[2]
        return ls.sn(nil, { ls.t(indent .. M.format(console_method, expression)), ls.i(0) })
      end, {})
    )
  end
  ls.add_snippets(ft, snippets)
end

return M
