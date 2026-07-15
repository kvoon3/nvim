return {
  'folke/flash.nvim',
  event = 'VeryLazy',
  ---@type Flash.Config
  opts = {
    modes = {
      -- f is Flash jump; keep native f/t behavior
      char = { enabled = false },
    },
  },
  -- stylua: ignore
  keys = {
    {
      "f",
      mode = { "n", "x", "o" },
      function()
        require("flash").jump()
      end,
      desc = "Flash",
    },
    {
      "r",
      mode = "o",
      function()
        require("flash").remote()
      end,
      desc = "Remote Flash",
    },
  },
  commander = {
    {
      desc = 'Toggle Flash Search',
      cmd = function()
        require('flash').toggle()
      end,
      cat = 'Flash',
    },
  },
}
