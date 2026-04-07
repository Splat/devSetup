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
Plug 'neoclide/coc.nvim', {'branch': 'release'}    " LSP
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

" -------------------------------
" Golang settings
" -------------------------------
let g:go_fmt_command = "goimports"    " Use goimports for formatting and managing imports on save
let g:go_def_mode = 'gopls'           " Use gopls for 'go to definition'
let g:go_info_mode = 'gopls'          " Use gopls for type info
let g:go_gopls_enabled = 1            " Enable gopls integration

" Auto format on save
autocmd BufWritePre *.go :silent! :GoImports


" -------------------------------
" auto-open file written by lf
" -------------------------------
augroup lf_open
  autocmd!
  autocmd FocusGained * call s:lf_check()
augroup END

function! s:lf_check()
  let l:path = '/tmp/lf-open'
  if filereadable(l:path) && getftime(l:path) > getftime(expand('%'))
    let l:file = trim(readfile(l:path)[0])
    if l:file != '' && filereadable(l:file)
      execute 'edit ' . fnameescape(l:file)
      call delete(l:path)
    endif
  endif
endfunction
