return {
    "folke/flash.nvim",
    event = "VeryLazy",
    ---@type Flash.Config
    opts = {},
    -- stylua: ignore
    keys = {{
        "s",
        mode = {"n", "x", "o"},
        function()
            require("flash").jump()
        end,
        desc = "Flash"
    }, {
        "r",
        mode = "o",
        function()
            require("flash").remote()
        end,
        desc = "Remote Flash"
    }, {
        "<c-s>",
        mode = {"c"},
        function()
            require("flash").toggle()
        end,
        desc = "Toggle Flash Search"
    }}
}

-- -- https://github.com/folke/flash.nvim
-- return {
--     "folke/flash.nvim",
--     event = "VeryLazy",
--     ---@type Flash.Config
--     opts = {
--         mode = "exact",
--         autojump = false,
--         label = {
--             -- style = "",
--         },
--         highlight = {
--             matches = true,
--             backdrop = true
--         },
--         modes = {
--             -- 取消默认 flash find 功能
--             char = {
--                 enabled = false,
--                 jump_labels = true
--             }
--         }
--     },
--     -- stylua: ignore
--     keys = { -- 取消默认 s 键功能
--     {
--         "s",
--         mode = {"n", "x", "o"},
--         false
--     }, {
--         "S",
--         mode = {"n", "x", "o"},
--         false
--     }, -- search 功能改至 f 键
--     {
--         "f",
--         mode = {"n", "x", "o"},
--         function()
--             require("flash").jump()
--         end,
--         desc = "Flash"
--     }, {
--         "F",
--         mode = {"n", "x", "o"},
--         function()
--             require("flash").treesitter()
--         end,
--         desc = "Flash Treesitter"
--     }, {
--         "r",
--         mode = "o",
--         function()
--             require("flash").remote()
--         end,
--         desc = "Remote Flash"
--     }, {
--         "R",
--         mode = {"o", "x"},
--         function()
--             require("flash").treesitter_search()
--         end,
--         desc = "Treesitter Search"
--     }, {
--         "<c-s>",
--         mode = {"c"},
--         function()
--             require("flash").toggle()
--         end,
--         desc = "Toggle Flash Search"
--     }}
-- }
