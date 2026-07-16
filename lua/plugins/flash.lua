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
  config = function(_, opts)
    require('flash').setup(opts)

    require('cmdr').add {
      {
        desc = 'Toggle Flash Search',
        cmd = function()
          require('flash').toggle()
        end,
        cat = 'flash',
      },
    }
  end,
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
}
