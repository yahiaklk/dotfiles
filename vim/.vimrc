" Minimal vim config — CKA exam compatible
" Use this on any remote server where nvim is not available

set number
set relativenumber

" 2 spaces everywhere (K8s YAML default)
set expandtab
set tabstop=2
set shiftwidth=2
set autoindent
set smartindent

" Search
set incsearch
set hlsearch
set ignorecase
set smartcase

" Editor behavior
set backspace=indent,eol,start
set ruler
set showcmd
set scrolloff=5
set wildmenu

syntax on
colorscheme desert

" YAML: explicit 2-space (Kubernetes manifests)
autocmd FileType yaml setlocal tabstop=2 shiftwidth=2 expandtab

" Clear search highlight with Esc in normal mode
nnoremap <silent> <Esc> :nohlsearch<CR>

" Quick save
nnoremap <leader>w :w<CR>
