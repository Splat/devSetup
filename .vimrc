" ------------------------------
"  Configure Basic Vim Settings
"  -----------------------------
set number relativenumber
set cursorline
set expandtab
set scrolloff=8
set signcolumn=yes
set shiftwidth=4
set smartindent
set tabstop=4
" Set all the line break options
set wrap
set linebreak
set breakindent
set showbreak=>>
" start searching as I type
set incsearch

" -------------------------------
" Plugin section
" -------------------------------
call plug#begin('~/.vim/plugged')
Plug 'fatih/vim-go', { 'do': ':GoUpdateBinaries' }
Plug 'neoclide/coc.nvim', {'branch': 'release'}    " LSP + completion
Plug 'github/copilot.vim'                          " AI inline suggestions (sign in with :Copilot setup)
" Optional: Add other useful plugins. Uncomment for usage
" Plug 'dense-analysis/ale'         " For linting and formatting
" Plug 'preservim/nerdtree'         " For a file explorer
call plug#end()

" coc keymaps
nmap <silent> gd <Plug>(coc-definition)
nmap <silent> gr <Plug>(coc-references)
nmap <silent> K :call CocActionAsync('doHover')<CR>
nmap <silent> <leader>rn <Plug>(coc-rename)
nmap <silent> [g <Plug>(coc-diagnostic-prev)
nmap <silent> ]g <Plug>(coc-diagnostic-next)

" Tab-driven completion: coc popup first, then accept a Copilot suggestion, else a literal Tab
let g:copilot_no_tab_map = v:true
function! s:TabComplete() abort
  if coc#pum#visible()
    return coc#pum#next(1)
  endif
  let l:suggestion = copilot#GetDisplayedSuggestion()
  if !empty(get(l:suggestion, 'text', ''))
    return copilot#Accept("\<Tab>")
  endif
  return "\<Tab>"
endfunction
inoremap <silent><expr> <Tab> <SID>TabComplete()
inoremap <silent><expr> <S-Tab> coc#pum#prev(1)
inoremap <silent><expr> <CR> coc#pum#visible() ? coc#pum#confirm() : "\<CR>"

" -------------------------------
" Golang settings
" -------------------------------
let g:go_fmt_command = "goimports"    " Use goimports for formatting and managing imports on save
let g:go_def_mode = 'gopls'           " Use gopls for 'go to definition'
let g:go_info_mode = 'gopls'          " Use gopls for type info
let g:go_gopls_enabled = 1            " Enable gopls integration
let g:go_code_completion_enabled = 0  " Let coc.nvim own completion; avoid conflicts with vim-go

" Auto format on save
autocmd BufWritePre *.go :silent! :GoImports

