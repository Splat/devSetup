# devSetup
This repo stores scripts and configs to quickly bootstrap my development environment.

## Quick Start

Clone the repo and run the install script — it handles Homebrew, tmux, lf, Node, Go tools, vim-plug, and all config symlinks:

```bash
git clone https://github.com/Splat/devSetup ~/code/devSetup
cd ~/code/devSetup
./install.sh
```

After it completes, follow the printed manual steps (vim plugins + tmux plugins).

### Updating an existing install

Pull the latest repo changes and re-run the script. It is safe to re-run: config symlinks and `dev-session` are refreshed, and already-installed tools are skipped.

```bash
cd ~/code/devSetup
git pull
./install.sh            # refresh configs and dev-session only
./install.sh --upgrade  # also upgrade installed tools
```

`--upgrade` additionally:
- runs `brew upgrade` for tmux, lf, and node (run `brew update` first for the newest versions)
- runs `git pull` on TPM
- reinstalls `gopls` and `dlv` at `@latest`
- re-downloads vim-plug

Plugins are updated separately: `:PlugUpdate` in vim and `Ctrl-a U` in tmux.

### Config symlinks

`install.sh` symlinks configs from the repo rather than copying them, so pulling updates takes effect immediately:

| File | Symlinked to |
|---|---|
| `tmux.conf` | `~/.tmux.conf` |
| `.vimrc` | `~/.vimrc` |
| `lfrc` | `~/.config/lf/lfrc` |
| `coc-settings.json` | `~/.vim/coc-settings.json` |

`dev-session.sh` is copied to `~/bin/dev-session` (executable).

Session management:

```bash
dev-session                 # create/attach "dev" in $PWD
dev-session myproj          # create/attach "dev-myproj"
dev-session --list          # list tmux sessions
dev-session --kill myproj   # kill "dev-myproj" (no name = "dev")
dev-session --kill-all      # kill "dev" and all "dev-*" sessions
```

---

## Vim Setup
### Setup the plugin manager:
```
curl -fLo ~/.vim/autoload/plug.vim --create-dirs \
    https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
```

### Install gopls
`go install golang.org/x/tools/gopls@latest`

### Configure `.vimrc`
Either store in `~/.vimrc` or `~/config/nvim/init.vim`. Been switching to Neovim but still prefer the old days. 

```
" -------------------------------
"  Configure Basic Vim Settings
"  ------------------------------
set number relativenumber

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

### Install coc-go (LSP + Autocomplete)
`coc-go` routes Go files to gopls inside coc.nvim, enabling autocomplete, diagnostics, and hover docs. After `:PlugInstall`, run inside Vim:
```
:CocInstall coc-go
```

`coc-settings.json` is symlinked to `~/.vim/coc-settings.json` by `install.sh`.

**Completion keybindings** (already in `.vimrc`):
- `Tab` / `Shift-Tab` — cycle through suggestions
- `Enter` — confirm selection
 
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

### Ensure ENV Configured
ensure the the `GOPATH` and `PATH` are properly configuerd in `~/.bash_profile` and `~/.zshrc`. Delve won't install properly or at all without this. 
```
export GOPATH="$HOME/go"
export PATH="$GOPATH/bin:$PATH"
```

### GoDoc
Projects worked on all conform to GoDoc and as such should be installed. 
`go install golang.org/x/tools/cmd/godoc@latest`
To run from within project jsut `godoc -http :8080`


### Debugging
Install the Delve debugger and just avoid using GDB unless necessary or on someone else's machine/server. 
`go install github.com/go-delve/delve/cmd/dlv@latest`
