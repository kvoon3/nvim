-- Follow the markdown link under the cursor (inline, reference, wiki, and autolinks).
local M = {}

local EXTERNAL_EXTENSIONS = {
  png = true,
  jpg = true,
  jpeg = true,
  gif = true,
  webp = true,
  svg = true,
  avif = true,
  bmp = true,
  ico = true,
  pdf = true,
  mp3 = true,
  mp4 = true,
  mov = true,
  webm = true,
  wav = true,
}

local function is_escaped(line, index)
  local backslashes = 0
  local i = index - 1
  while i >= 1 and line:sub(i, i) == '\\' do
    backslashes = backslashes + 1
    i = i - 1
  end
  return backslashes % 2 == 1
end

local function matching_bracket(line, open)
  local depth = 0
  local i = open
  while i <= #line do
    local char = line:sub(i, i)
    if char == '\\' then
      i = i + 2
    else
      if char == '[' then
        depth = depth + 1
      elseif char == ']' then
        depth = depth - 1
        if depth == 0 then
          return i
        end
      end
      i = i + 1
    end
  end
end

---@param line string
---@param pos integer index just after `(`
---@return integer? finish index of the closing `)`
---@return string? target
local function parse_destination(line, pos)
  local i = pos
  while i <= #line and line:sub(i, i):match '%s' do
    i = i + 1
  end
  if i > #line then
    return nil
  end

  local target
  if line:sub(i, i) == '<' then
    local close = line:find('>', i + 1, true)
    if not close then
      return nil
    end
    target = line:sub(i + 1, close - 1)
    i = close + 1
  else
    local start = i
    local depth = 0
    while i <= #line do
      local char = line:sub(i, i)
      if char == '\\' then
        i = i + 2
      elseif char == '(' then
        depth = depth + 1
        i = i + 1
      elseif char == ')' then
        if depth == 0 then
          break
        end
        depth = depth - 1
        i = i + 1
      elseif char:match '%s' and depth == 0 then
        break
      else
        i = i + 1
      end
    end
    target = line:sub(start, i - 1)
  end

  target = vim.trim(target)
  if target == '' then
    return nil
  end

  --[[ Skip an optional title ("...", '...', or (...)) after the destination. ]]
  local depth = 0
  while i <= #line do
    local char = line:sub(i, i)
    if char == '\\' then
      i = i + 2
    elseif char == '(' then
      depth = depth + 1
      i = i + 1
    elseif char == ')' then
      if depth == 0 then
        return i, target
      end
      depth = depth - 1
      i = i + 1
    else
      i = i + 1
    end
  end
end

local function link_start(line, open)
  if line:sub(open - 1, open - 1) == '!' and not is_escaped(line, open - 1) then
    return open - 1
  end
  return open
end

local function parse_inline_links(line)
  local links = {}
  local i = 1
  while i <= #line do
    local open = line:find('[', i, true)
    if not open then
      break
    end
    if is_escaped(line, open) then
      i = open + 1
    else
      local close = matching_bracket(line, open)
      if close and line:sub(close + 1, close + 1) == '(' then
        local finish, target = parse_destination(line, close + 2)
        if finish and target then
          local start = link_start(line, open)
          links[#links + 1] = {
            start = start,
            finish = finish,
            target = target,
            kind = start < open and 'image' or 'link',
          }
          i = finish + 1
        else
          i = open + 1
        end
      else
        i = open + 1
      end
    end
  end
  return links
end

local function parse_wiki_links(line)
  local links = {}
  local i = 1
  while true do
    local open = line:find('[[', i, true)
    if not open then
      break
    end
    if is_escaped(line, open) then
      i = open + 2
    else
      local close = line:find(']]', open + 2, true)
      if not close then
        break
      end
      local inner = line:sub(open + 2, close - 1)
      local target = vim.trim((inner:match '^([^|]*)'))
      if target ~= '' then
        local start = link_start(line, open)
        links[#links + 1] = {
          start = start,
          finish = close + 1,
          target = target,
          kind = start < open and 'image' or 'wiki',
          wiki = true,
        }
      end
      i = close + 2
    end
  end
  return links
end

local function parse_definition_target(rest)
  rest = vim.trim(rest)
  if rest == '' then
    return nil
  end
  if rest:sub(1, 1) == '<' then
    local close = rest:find('>', 2, true)
    return close and rest:sub(2, close - 1) or nil
  end
  return rest:match '^(%S+)'
end

local function parse_reference_definition(line)
  local indent, label, rest = line:match '^(%s*)%[([^%]]+)%]:%s*(.*)$'
  if not indent or label:sub(1, 1) == '^' then
    return nil
  end
  local target = parse_definition_target(rest)
  if not target then
    return nil
  end
  return { start = #indent + 1, finish = #line, target = target, kind = 'reference' }
end

local function normalize_label(label)
  return (vim.trim(label):lower():gsub('%s+', ' '))
end

local function normalize_space(text)
  return (vim.trim((text:gsub('%s+', ' '))))
end

---@param line string
---@param close integer index of the closing `]`
---@param text string link text
---@param start integer link start index
---@param kind string
---@param refs table<string, string>
local function reference_link_at(line, close, text, start, kind, refs)
  local next_char = line:sub(close + 1, close + 1)
  if next_char == '(' then
    return nil, close + 1 -- inline link, handled by parse_inline_links
  end
  if next_char == '[' then
    local close2 = line:find(']', close + 2, true)
    if not close2 then
      return nil, close + 1
    end
    local label = line:sub(close + 2, close2 - 1)
    if label == '' then
      label = text
    end
    local target = refs[normalize_label(label)]
    return target and { start = start, finish = close2, target = target, kind = kind } or nil, close2 + 1
  end
  if next_char == ':' or text == '' or text:sub(1, 1) == '^' then
    return nil, close + 1
  end
  local target = refs[normalize_label(text)]
  return target and { start = start, finish = close, target = target, kind = kind } or nil, close + 1
end

local function parse_reference_links(line, refs)
  local links = {}
  local i = 1
  while i <= #line do
    local open = line:find('[', i, true)
    if not open then
      break
    end
    local previous = line:sub(open - 1, open - 1)
    if is_escaped(line, open) or previous == '[' or line:sub(open + 1, open + 1) == '[' then
      i = open + 1
    else
      local close = matching_bracket(line, open)
      if not close then
        i = open + 1
      else
        local start = link_start(line, open)
        local kind = start < open and 'image' or 'reference'
        local link, next_index = reference_link_at(line, close, line:sub(open + 1, close - 1), start, kind, refs)
        if link then
          links[#links + 1] = link
        end
        i = next_index
      end
    end
  end
  return links
end

local function parse_autolinks(line)
  local links = {}
  local i = 1
  while i <= #line do
    local start, finish = line:find('<([%w+.-]+:[^%s<>]+)>', i)
    if not start then
      break
    end
    links[#links + 1] = {
      start = start,
      finish = finish,
      target = line:sub(start + 1, finish - 1),
      kind = 'url',
    }
    i = finish + 1
  end
  return links
end

---Find the link containing `col` (0-based byte column) on `line`.
---@param line string
---@param col integer
---@param refs? table<string, string> normalized reference label -> target
---@return table? link
function M.link_at(line, col, refs)
  local candidates = {}
  local definition = parse_reference_definition(line)
  if definition then
    candidates[#candidates + 1] = definition
  end
  vim.list_extend(candidates, parse_wiki_links(line))
  vim.list_extend(candidates, parse_inline_links(line))
  vim.list_extend(candidates, parse_autolinks(line))
  if refs then
    vim.list_extend(candidates, parse_reference_links(line, refs))
  end

  local cursor = col + 1
  local best
  for _, link in ipairs(candidates) do
    if cursor >= link.start and cursor <= link.finish then
      if not best or (link.finish - link.start) < (best.finish - best.start) then
        best = link
      end
    end
  end
  return best
end

---@param bufnr? integer
---@return table<string, string>
function M.reference_targets(bufnr)
  local refs = {}
  for _, line in ipairs(vim.api.nvim_buf_get_lines(bufnr or 0, 0, -1, false)) do
    local label, rest = line:match '^%s*%[([^%]]+)%]:%s*(.*)$'
    if label and label:sub(1, 1) ~= '^' then
      local target = parse_definition_target(rest)
      if target then
        refs[normalize_label(label)] = target
      end
    end
  end
  return refs
end

local function decode(text)
  local ok, decoded = pcall(vim.uri_decode, text)
  return ok and decoded or text
end

---Split a link target into a decoded path and anchor.
---@param target string
---@return string? path
---@return string? anchor
function M.parse_target(target)
  target = vim.trim(target)
  if target == '' then
    return nil
  end
  target = target:gsub('^<(.*)>$', '%1')
  target = target:gsub('\\([%p ])', '%1')

  local path, anchor = target:match '^(.-)#(.*)$'
  if not path then
    path, anchor = target, nil
  end
  return decode(path), anchor and decode(anchor) or nil
end

local function is_url(target)
  return target:match '^%a[%w+.-]*:' ~= nil and target:match '^%a:[/\\]' == nil
end

---@param bufnr? integer
---@return string
function M.buffer_dir(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr or 0)
  if name == '' then
    return vim.fn.getcwd()
  end
  return vim.fs.dirname(name)
end

---@param bufnr? integer
---@return string?
function M.vault_root(bufnr)
  bufnr = bufnr or 0
  if vim.api.nvim_buf_get_name(bufnr) == '' then
    return nil
  end
  return vim.fs.root(bufnr, '.obsidian')
end

local function add_candidate(candidates, path)
  if not path or path == '' then
    return
  end
  if path:sub(1, 1) == '~' then
    path = vim.fn.expand(path)
  end
  candidates[#candidates + 1] = path
end

local function add_with_markdown_extension(candidates, path)
  add_candidate(candidates, path)
  if not path:match '%.%w+$' then
    add_candidate(candidates, path .. '.md')
  end
end

local function first_existing(candidates)
  for _, candidate in ipairs(candidates) do
    if vim.fn.filereadable(candidate) == 1 or vim.fn.isdirectory(candidate) == 1 then
      return vim.fs.normalize(candidate)
    end
  end
end

local function find_in_vault(vault, target)
  local name = target:gsub('^.*/', '')
  if name == '' then
    return nil
  end
  local matches = vim.fs.find(function(candidate)
    return candidate == name or candidate == name .. '.md'
  end, { path = vault, type = 'file' })
  if #matches == 0 then
    return nil
  end
  table.sort(matches, function(a, b)
    return #a < #b
  end)
  return vim.fs.normalize(matches[1])
end

---Resolve a link path relative to the buffer, or the vault for wiki links.
---@param path string
---@param bufnr? integer
---@param is_wiki? boolean
---@return string?
function M.resolve_path(path, bufnr, is_wiki)
  local dir = M.buffer_dir(bufnr)
  local vault = M.vault_root(bufnr)
  local candidates = {}
  local absolute = path:sub(1, 1) == '/'

  if absolute then
    if vault then
      add_with_markdown_extension(candidates, vim.fs.joinpath(vault, path:sub(2)))
    end
    add_with_markdown_extension(candidates, path)
  elseif is_wiki then
    if vault then
      add_with_markdown_extension(candidates, vim.fs.joinpath(vault, path))
    end
    add_with_markdown_extension(candidates, vim.fs.joinpath(dir, path))
  else
    add_with_markdown_extension(candidates, vim.fs.joinpath(dir, path))
    if vault then
      add_with_markdown_extension(candidates, vim.fs.joinpath(vault, path))
    end
  end

  local found = first_existing(candidates)
  if found then
    return found
  end
  if is_wiki and vault then
    return find_in_vault(vault, path)
  end
end

---Normalize a heading into a GitHub-style anchor.
---@param text string
---@return string
function M.slug(text)
  local slug = (normalize_space(text:lower()):gsub('<[^>]*>', ''))
  slug = slug:gsub('%s', '-')
  local out = {}
  for i = 1, #slug do
    local char = slug:sub(i, i)
    if char:match '[%w%-_]' or char:byte() >= 128 then
      out[#out + 1] = char
    end
  end
  return table.concat(out)
end

local function find_line(lines, predicate)
  for index, line in ipairs(lines) do
    if predicate(line) then
      return index
    end
  end
end

---Jump to a heading (or `^block-id`) in the current buffer.
---@param anchor string
---@return boolean
function M.jump_to_anchor(anchor)
  anchor = vim.trim((anchor:gsub('^#', '')))
  if anchor == '' then
    return true
  end

  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local row
  if anchor:sub(1, 1) == '^' then
    local id = vim.pesc(anchor:sub(2))
    row = find_line(lines, function(line)
      return line:match('%s%^' .. id .. '%s*$') ~= nil
    end)
  else
    local wanted_slug = M.slug(anchor)
    local wanted_text = normalize_space(anchor:lower())
    row = find_line(lines, function(line)
      local heading = line:match '^%s*#+%s+(.-)%s*$'
      if not heading then
        return false
      end
      heading = heading:gsub('%s+#+$', '')
      return M.slug(heading) == wanted_slug or normalize_space(heading:lower()) == wanted_text
    end)
  end

  if not row then
    vim.notify('Markdown anchor not found: ' .. anchor, vim.log.levels.WARN)
    return false
  end
  vim.api.nvim_win_set_cursor(0, { row, 0 })
  vim.cmd 'normal! zv'
  return true
end

local function open_external(target)
  local ok, opener, err = pcall(vim.ui.open, target)
  if not ok then
    vim.notify('Failed to open link: ' .. tostring(opener), vim.log.levels.ERROR)
  elseif not opener then
    vim.notify('Failed to open link: ' .. tostring(err), vim.log.levels.ERROR)
  end
end

local function is_external_file(path)
  local extension = path:match '%.([%w]+)$'
  return extension ~= nil and EXTERNAL_EXTENSIONS[extension:lower()] == true
end

local function jump_to_lsp_definition(bufnr)
  local clients = vim.lsp.get_clients { bufnr = bufnr, method = 'textDocument/definition' }
  if #clients > 0 then
    return vim.lsp.buf.definition()
  end
  vim.notify('No markdown link under cursor', vim.log.levels.WARN)
end

local function jump_to_anchor_if(anchor)
  if anchor and anchor ~= '' then
    M.jump_to_anchor(anchor)
  end
end

local function follow_file_link(link, bufnr)
  local path, anchor = M.parse_target(link.target)
  if not path or path == '' then
    jump_to_anchor_if(anchor)
    return
  end

  local resolved = M.resolve_path(path, bufnr, link.wiki)
  if not resolved then
    vim.notify('Markdown link not found: ' .. path, vim.log.levels.WARN)
    return
  end
  if link.kind == 'image' or vim.fn.isdirectory(resolved) == 1 or is_external_file(resolved) then
    return open_external(resolved)
  end

  local current = vim.api.nvim_buf_get_name(bufnr)
  if current ~= '' and vim.fs.normalize(current) == resolved then
    jump_to_anchor_if(anchor)
    return
  end

  local ok, err = pcall(vim.cmd, 'edit ' .. vim.fn.fnameescape(resolved))
  if not ok then
    vim.notify('Failed to open markdown link: ' .. tostring(err), vim.log.levels.ERROR)
    return
  end
  jump_to_anchor_if(anchor)
end

---Follow the link under the cursor, falling back to the LSP definition.
---@param bufnr? integer
function M.follow(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = vim.api.nvim_buf_get_lines(bufnr, cursor[1] - 1, cursor[1], false)[1] or ''
  local link = M.link_at(line, cursor[2], M.reference_targets(bufnr))
  if not link then
    return jump_to_lsp_definition(bufnr)
  end
  if link.kind == 'url' or is_url(link.target) then
    return open_external(link.target)
  end
  follow_file_link(link, bufnr)
end

function M.setup()
  vim.api.nvim_create_autocmd('FileType', {
    group = vim.api.nvim_create_augroup('MarkdownLinks', { clear = true }),
    pattern = 'markdown*',
    callback = function(args)
      vim.keymap.set('n', 'gd', function()
        M.follow(args.buf)
      end, { buffer = args.buf, desc = 'Follow markdown link' })
    end,
  })

  require('cmdr').add {
    {
      desc = 'Markdown: follow link under cursor',
      cmd = function()
        M.follow()
      end,
      cat = 'markdown',
    },
  }
end

return M
