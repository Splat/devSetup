" ------------------------------
"  Configure Basic Vim Settings
"  -----------------------------
set number relativenumber
set cursorline
set expandtab
set scrolloff=8
set signcolumn=yes
set shiftwidth=4
set signcolumn=yes
set smartindent
set tabstop=4

" -------------------------------
" Plugin section
" -------------------------------
call plug#begin('~/.vim/plugged')
Plug 'fatih/vim-go', { 'do': ':GoUpdateBinaries' }
" Optional: Add other useful plugins
" Plug 'dense-analysis/ale'         " For linting and formatting
" Plug 'preservim/nerdtree'         " For a file explorer
call plug#end()

" -------------------------------
" Golang settings
" -------------------------------
let g:go_fmt_command = "goimports"    " Use goimports for formatting and managing imports on save
let g:go_def_mode = 'gopls'           " Use gopls for 'go to definition'
let g:go_info_mode = 'gopls'          " Use gopls for type info
let g:go_gopls_enabled = 1            " Enable gopls integration

" Auto format on save
autocmd BufWritePre *.go :silent! :GoImports
