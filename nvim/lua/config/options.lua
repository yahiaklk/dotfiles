local opt = vim.opt

-- Line numbers
opt.number = true
opt.relativenumber = true

-- Indentation (4 spaces; YAML/K8s overrides per filetype below)
opt.expandtab = true
opt.tabstop = 4
opt.shiftwidth = 4
opt.smartindent = true

-- Search
opt.incsearch = true
opt.hlsearch = true
opt.ignorecase = true
opt.smartcase = true

-- Splits (standard vim muscle memory)
opt.splitright = true
opt.splitbelow = true

-- Appearance
opt.termguicolors = true
opt.scrolloff = 8
opt.signcolumn = "yes"
opt.cursorline = true

-- System clipboard
opt.clipboard = "unnamedplus"

-- Persistent undo
opt.undofile = true

-- Responsiveness
opt.updatetime = 250
opt.timeoutlen = 300

-- No swap/backup (undofile is enough)
opt.swapfile = false
opt.backup = false

opt.wrap = false
opt.mouse = "a"

-- YAML and K8s manifests: force 2-space indent (matches CKA exam)
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "yaml", "yml" },
  callback = function()
    vim.opt_local.tabstop = 2
    vim.opt_local.shiftwidth = 2
    vim.opt_local.expandtab = true
  end,
})
