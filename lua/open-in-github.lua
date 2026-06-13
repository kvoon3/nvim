local M = {}

local function get_git_root()
  local result = vim.fn.systemlist("git rev-parse --show-toplevel")
  if vim.v.shell_error ~= 0 or #result == 0 then
    return nil
  end
  return vim.fn.trim(result[1])
end

local function get_remote_url(root)
  local result = vim.fn.systemlist("git -C " .. vim.fn.shellescape(root) .. " remote get-url origin")
  if vim.v.shell_error ~= 0 or #result == 0 then
    return nil
  end
  return vim.fn.trim(result[1])
end

local function parse_github_url(remote)
  local user, repo = remote:match("^git@github%.com:(.+)/(.+)%.git$")
  if not user then
    user, repo = remote:match("^git@github%.com:(.+)/(.+)$")
  end
  if not user then
    user, repo = remote:match("^https?://github%.com/(.+)/(.+)%.git$")
  end
  if not user then
    user, repo = remote:match("^https?://github%.com/(.+)/(.+)$")
  end
  if user and repo then
    return string.format("https://github.com/%s/%s", user, repo)
  end
  return nil
end

local function get_branch(root)
  local result = vim.fn.systemlist("git -C " .. vim.fn.shellescape(root) .. " branch --show-current")
  if vim.v.shell_error ~= 0 or #result == 0 or result[1] == "" then
    result = vim.fn.systemlist("git -C " .. vim.fn.shellescape(root) .. " rev-parse HEAD")
    if vim.v.shell_error ~= 0 or #result == 0 then
      return nil
    end
  end
  return vim.fn.trim(result[1])
end

local function get_relative_path(root, filepath)
  if not filepath or filepath == "" then
    return nil
  end
  if filepath:sub(1, #root) ~= root then
    return nil
  end
  local rel = filepath:sub(#root + 2)
  if rel == "" then
    return nil
  end
  return rel
end

local function encode_url_part(part)
  return part:gsub(" ", "%%20")
end

local function get_line_anchor()
  local mode = vim.fn.mode()
  if mode == "v" or mode == "V" or mode == "\22" then
    local start_pos = vim.fn.getpos("v")
    local end_pos = vim.fn.getpos(".")
    local start_line = start_pos[2]
    local end_line = end_pos[2]
    if start_line > end_line then
      start_line, end_line = end_line, start_line
    end
    if start_line == end_line then
      return "#L" .. start_line
    end
    return "#L" .. start_line .. "-L" .. end_line
  end
  return "#L" .. vim.fn.line(".")
end

local function open_url(url)
  local open_cmd
  if vim.fn.has("mac") == 1 then
    open_cmd = "open"
  elseif vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1 then
    open_cmd = "start"
  else
    open_cmd = "xdg-open"
  end
  vim.fn.jobstart({ open_cmd, url }, { detach = true })
end

function M.open_in_github()
  local root = get_git_root()
  if not root then
    vim.notify("Not in a git repository", vim.log.levels.WARN)
    return
  end

  local remote = get_remote_url(root)
  if not remote then
    vim.notify("No 'origin' remote found", vim.log.levels.WARN)
    return
  end

  local base_url = parse_github_url(remote)
  if not base_url then
    vim.notify("Remote is not a GitHub repository: " .. remote, vim.log.levels.WARN)
    return
  end

  local branch = get_branch(root)
  if not branch then
    vim.notify("Could not determine branch or commit", vim.log.levels.WARN)
    return
  end

  local filepath = vim.fn.expand("%:p")
  local rel = get_relative_path(root, filepath)

  local url
  if rel then
    url = base_url .. "/blob/" .. encode_url_part(branch) .. "/" .. encode_url_part(rel) .. get_line_anchor()
  else
    url = base_url
  end

  open_url(url)
end

vim.api.nvim_create_user_command("OpenInGitHub", M.open_in_github, {
  desc = "Open current file or repository in GitHub",
})

return M
