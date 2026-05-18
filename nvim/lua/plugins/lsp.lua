return {
  -- LSP package installer (handles pyright, terraform-ls, etc.)
  {
    "williamboman/mason.nvim",
    opts = {
      ui = {
        icons = {
          package_installed   = "✓",
          package_pending     = "➜",
          package_uninstalled = "✗",
        },
      },
    },
  },

  -- Auto-install LSPs registered in ensure_installed
  {
    "williamboman/mason-lspconfig.nvim",
    dependencies = { "williamboman/mason.nvim" },
    opts = {
      ensure_installed = { "pyright", "terraformls", "yamlls", "bashls" },
      automatic_installation = true,
    },
  },

  -- LSP configurations
  {
    "neovim/nvim-lspconfig",
    dependencies = {
      "williamboman/mason-lspconfig.nvim",
      "hrsh7th/cmp-nvim-lsp",
    },
    config = function()
      local lspconfig    = require("lspconfig")
      local capabilities = require("cmp_nvim_lsp").default_capabilities()

      local on_attach = function(_, bufnr)
        local map = function(keys, func, desc)
          vim.keymap.set("n", keys, func, { buffer = bufnr, desc = "LSP: " .. desc })
        end
        -- Standard vim LSP keymaps — same across all languages
        map("gd",         vim.lsp.buf.definition,   "Go to definition")
        map("gD",         vim.lsp.buf.declaration,  "Go to declaration")
        map("gr",         vim.lsp.buf.references,   "References")
        map("gi",         vim.lsp.buf.implementation, "Implementation")
        map("K",          vim.lsp.buf.hover,         "Hover docs")
        map("<leader>rn", vim.lsp.buf.rename,        "Rename symbol")
        map("<leader>ca", vim.lsp.buf.code_action,   "Code action")
        map("<leader>fm", function() vim.lsp.buf.format({ async = true }) end, "Format file")
      end

      lspconfig.pyright.setup({ on_attach = on_attach, capabilities = capabilities })
      lspconfig.terraformls.setup({ on_attach = on_attach, capabilities = capabilities })
      lspconfig.bashls.setup({ on_attach = on_attach, capabilities = capabilities })

      lspconfig.yamlls.setup({
        on_attach    = on_attach,
        capabilities = capabilities,
        settings = {
          yaml = {
            -- Kubernetes schema applied to all .yaml files by default
            schemas = {
              ["https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/v1.29.0/all.json"] = "/*.yaml",
            },
            validate = true,
          },
        },
      })
    end,
  },

  -- Autocomplete engine
  {
    "hrsh7th/nvim-cmp",
    dependencies = {
      "hrsh7th/cmp-nvim-lsp",
      "hrsh7th/cmp-buffer",
      "hrsh7th/cmp-path",
      "L3MON4D3/LuaSnip",
      "saadparwaiz1/cmp_luasnip",
    },
    config = function()
      local cmp     = require("cmp")
      local luasnip = require("luasnip")

      cmp.setup({
        snippet = {
          expand = function(args) luasnip.lsp_expand(args.body) end,
        },
        mapping = cmp.mapping.preset.insert({
          ["<C-b>"]     = cmp.mapping.scroll_docs(-4),
          ["<C-f>"]     = cmp.mapping.scroll_docs(4),
          ["<C-Space>"] = cmp.mapping.complete(),
          ["<C-e>"]     = cmp.mapping.abort(),
          -- Enter confirms; Tab cycles completions
          ["<CR>"]      = cmp.mapping.confirm({ select = true }),
          ["<Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_next_item()
            elseif luasnip.expand_or_jumpable() then
              luasnip.expand_or_jump()
            else
              fallback()
            end
          end, { "i", "s" }),
          ["<S-Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_prev_item()
            elseif luasnip.jumpable(-1) then
              luasnip.jump(-1)
            else
              fallback()
            end
          end, { "i", "s" }),
        }),
        sources = cmp.config.sources({
          { name = "nvim_lsp" },
          { name = "luasnip" },
          { name = "buffer" },
          { name = "path" },
        }),
      })
    end,
  },
}
