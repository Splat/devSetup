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
" Optional: Add other useful plugins
" Plug 'dense-analysis/ale'         " For linting and formatting
" Plug 'preservim/nerdtree'         " For a file explorer
call plug#end()

" -------------------------------
" Golang settings
" -------------------------------
let g:go_fmt_command = "goimports"        " Use goimports for formatting and managing imports on save
let g:go_def_mode = 'gopls'              " Use gopls for 'go to definition'
let g:go_info_mode = 'gopls'             " Use gopls for type info
let g:go_gopls_enabled = 1               " Enable gopls integration

" Auto format on save
autocmd BufWritePre *.go :silent! :GoImports
```

### Install Plugins and Go Binaries 
Install the plugins: Open Vim and run the command `:PlugInstall`.
Install Go tools: Once the plugins are installed, run `:GoInstallBinaries` or `:GoUpdateBinaries` inside Vim to download and compile all necessary Go tools, including gopls and goimports. 
 
### Verify the Setup
Open a Go file (e.g., `vim hello.go`) and test some of the features: 
Go to definition: Place your cursor over a function or type and use the default mapping gd (or run `:GoDef`).
Show documentation: Hover over a symbol and press `K` (or run `:GoDoc`).
Run tests: Use `:GoTest` to run tests for the current package.
Build/Run: Use `:GoBuild` or `:GoRun` to compile and execute your code. 

With these steps, your Vim ha the beasic of features for Go development, including auto-completion, formatting, and debugging support. 
