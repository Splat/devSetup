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

### Quick Command Reference (Golang)
- **GoRun**: Executes your current file(s) with go run.
- **GoBuild**: Compiles your package with go build.
- **GoTest**: Runs tests for the current package.
- **GoCoverageToggle**: Toggles the display of test coverage results.
- **GoDef**: Jumps to a symbol or function definition (often mapped to gd in modern setups).
- **GoDoc**: Displays documentation for the identifier under the cursor in a split pane.
- **GoImport**: Manages package imports.
- **GoRename**: Renames the identifier under the cursor across all files in the package.

### Debugging
### Ensure ENV Configured
ensure the the `GOPATH` and `PATH` are properly configuerd in `~/.bash_profile` and `~/.zshrc`. Delve won't install properly or at all without this. 
```
export GOPATH="$HOME/go"
export PATH="$GOPATH/bin:$PATH"
```

Install the Delve debugger and just avoid using GDB unless necessary or on someone else's machine/server. 
`go install github.com/go-delve/delve/cmd/dlv@latest`
