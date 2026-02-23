# devSetup
This repo is intended to store easy to find scripts to quickly bootstrap my development environment and methodology.

## Vim Setup
### Setup the plugin manager:
```
curl -fLo ~/.vim/autoload/plug.vim --create-dirs \
    https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
```

### Configure `.vimrc`
Either store in `~/.vimrc` or `~/config/nvim/init.vim`. Been switching to Neovim but still prefer the old days. 

```
" -------------------------------
" Plugin section
" -------------------------------
call plug#begin('~/.vim/plugged')
Plug 'fatih/vim-go', { 'do': ':GoUpdateBinaries' }
" Optional: Add other useful plugins like a file explorer (NERDTree) or a completion engine (coc.nvim)
Plug 'preservim/nerdtree'
call plug#end()

" -------------------------------
" Golang settings
" -------------------------------
let g:go_fmt_command = "goimports" " Use goimports for formatting and managing imports
let g:go_gopls_enabled = 1          " Enable gopls, the Go language server
autocmd BufWritePre *.go :silent! :GoImports " Automatically run goimports on save


```
