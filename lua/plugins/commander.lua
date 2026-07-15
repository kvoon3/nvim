return {
  'FeiyouG/commander.nvim',
  dependencies = { 'nvim-telescope/telescope.nvim' },
  config = function()
    require('commander').setup {
      components = {
        'DESC',
        'KEYS',
        'CAT',
      },
      sort_by = {
        'DESC',
        'KEYS',
        'CAT',
        'CMD',
      },
      integration = {
        telescope = {
          enable = true,
        },
        lazy = {
          enable = true,
          set_plugin_name_as_cat = true,
        },
      },
    }

    require('commander').add {
      {
        desc = ' CodeDiff: open git status explorer',
        cmd = '<CMD>CodeDiff<CR>',
        keys = { 'n', '<leader>gd' },
        cat = 'codediff',
      },
      {
        desc = 'CodeDiff: diff current file against HEAD',
        cmd = '<CMD>CodeDiff file HEAD<CR>',
        keys = { 'n', '<leader>gD' },
        cat = 'codediff',
      },
      {
        desc = 'CodeDiff: diff current file against HEAD~1',
        cmd = '<CMD>CodeDiff file HEAD~1<CR>',
        cat = 'codediff',
      },
      {
        desc = 'CodeDiff: diff current file against revision...',
        cmd = function()
          vim.ui.input({ prompt = 'Revision: ' }, function(revision)
            if revision and revision ~= '' then
              vim.cmd('CodeDiff file ' .. revision)
            end
          end)
        end,
        cat = 'codediff',
      },
      {
        desc = 'CodeDiff: explorer compare two revisions...',
        cmd = function()
          vim.ui.input({ prompt = 'Base revision: ' }, function(base)
            if not base or base == '' then
              return
            end
            vim.ui.input({ prompt = 'Target revision: ' }, function(target)
              if target and target ~= '' then
                vim.cmd('CodeDiff ' .. base .. ' ' .. target)
              end
            end)
          end)
        end,
        cat = 'codediff',
      },
      {
        desc = 'CodeDiff: show current file history',
        cmd = '<CMD>CodeDiff history %<CR>',
        keys = { 'n', '<leader>gh' },
        cat = 'codediff',
      },
      {
        desc = 'CodeDiff: show repository history',
        cmd = '<CMD>CodeDiff history<CR>',
        cat = 'codediff',
      },
      {
        desc = 'CodeDiff: open merge tool for current file',
        cmd = function()
          local file = vim.fn.expand '%'
          if file == '' then
            vim.notify('Current buffer is not a file', vim.log.levels.ERROR)
            return
          end
          vim.cmd('CodeDiff merge ' .. file)
        end,
        cat = 'codediff',
      },
      {
        desc = 'CodeDiff: diff two directories...',
        cmd = function()
          vim.ui.input({ prompt = 'Directory 1: ', completion = 'dir' }, function(dir1)
            if not dir1 or dir1 == '' then
              return
            end
            vim.ui.input({ prompt = 'Directory 2: ', completion = 'dir' }, function(dir2)
              if dir2 and dir2 ~= '' then
                vim.cmd('CodeDiff dir ' .. dir1 .. ' ' .. dir2)
              end
            end)
          end)
        end,
        cat = 'codediff',
      },
      {
        desc = 'CodeDiff: install native diff library',
        cmd = '<CMD>CodeDiff install<CR>',
        cat = 'codediff',
      },
      {
        desc = 'CodeDiff: force reinstall native diff library',
        cmd = '<CMD>CodeDiff install!<CR>',
        cat = 'codediff',
      },
      {
        desc = 'CodeDiff: open explorer (inline layout)',
        cmd = '<CMD>CodeDiff --inline<CR>',
        cat = 'codediff',
      },
      {
        desc = 'CodeDiff: open explorer (side-by-side layout)',
        cmd = '<CMD>CodeDiff --side-by-side<CR>',
        cat = 'codediff',
      },
    }

    require('commander').add {
      {
        desc = 'LSP: reload all language servers',
        cmd = '<CMD>ReloadLsp<CR>',
        cat = 'lsp',
      },
    }
  end,
}
