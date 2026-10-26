# devSetup

A one-command bootstrap for a Go-focused terminal development environment, built around tmux. It installs and configures the tooling, then gives each project a ready-made, persistent tmux session.

**What it provides**
- **Environment bootstrap and updates:** `install.sh` installs Homebrew, git, Go, tmux, lf, Node, the AI assistants (Claude Code, GitHub Copilot CLI, Codex), Go tooling (`gopls`, `dlv`), vim-plug and TPM, and links the configs in this repo into place. It is safe to re-run, and `--upgrade` brings installed tools up to date.
- **Windowed tmux sessions:** `dev-session` creates a consistent five-window layout per project: editor with file explorer, Claude Code, GitHub Copilot CLI, a shell with Go test and git panes, and a debugger (delve).
- **Session state management:** sessions persist, so you can detach and come back with everything as you left it. Re-running `dev-session` attaches to an existing session instead of creating a duplicate. Sessions can be listed, switched between, and killed individually or all at once.

**Why use it**
- A new machine or project goes from nothing to a working setup in minutes, with the same layout every time.
- Configs live in version control and are symlinked, so changes apply immediately and stay in sync across machines.
- Several projects can run side by side as named sessions, each rooted in its own directory.

## Quick Start

Clone the repo and run the install script — it handles Homebrew, git, Go, tmux, lf, Node, Claude Code, Copilot CLI, Codex, Go tools, vim-plug, and all config symlinks:

```bash
git clone https://github.com/Splat/devSetup ~/code/devSetup
cd ~/code/devSetup
./install.sh
```

After it completes, reload your shell (`source ~/.zshrc`) and sign in to `claude`, `copilot` (`/login`) and `codex` on first use. Vim and tmux plugins are installed automatically.

### Updating an existing install

Pull the latest repo changes and re-run the script. It is safe to re-run: config symlinks and `dev-session` are refreshed, and already-installed tools are skipped.

```bash
cd ~/code/devSetup
git pull
./install.sh            # refresh configs and dev-session only
./install.sh --upgrade  # also upgrade installed tools
```

`--upgrade` additionally:
- runs `brew upgrade` for git, Go, tmux, lf, node, Copilot CLI and Codex when Homebrew manages them (run `brew update` first for the newest versions)
- runs `claude update` for Claude Code when it was installed outside Homebrew
- skips tools installed some other way (for example Go from go.dev) and tells you to update them manually
- runs `git pull` on TPM
- reinstalls `gopls` and `dlv` at `@latest`
- re-downloads vim-plug

- updates vim plugins (`:PlugUpdate`, which also refreshes vim-go's binaries) and tmux plugins (TPM `update_plugins`)

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

`install.sh` fully automates this — no manual steps needed:

- installs vim-plug and symlinks `.vimrc` (plugins, Go settings, and coc keymaps live there) and `coc-settings.json`
- runs `:PlugInstall` (`:PlugUpdate` with `--upgrade`), which also fetches vim-go's Go binaries
- installs `coc-go` (LSP + autocomplete via gopls)
- installs `gopls`, `dlv`, and `godoc`, and puts `$GOPATH/bin` on your `PATH`

Neovim users can point `~/.config/nvim/init.vim` at the same `.vimrc`.

**Completion keybindings** (already in `.vimrc`):
- `Tab` / `Shift-Tab` — cycle through suggestions
- `Enter` — confirm selection
 
### Verify the Setup
Open a Go file (e.g., `vim hello.go`) and test some of the features: 
Go to definition: Place your cursor over a function or type and use the default mapping gd (or run `:GoDef`).
Show documentation: Hover over a symbol and press `K` (or run `:GoDoc`).
Run tests: Use `:GoTest` to run tests for the current package.
Build/Run: Use `:GoBuild` or `:GoRun` to compile and execute your code. 

With this setup, Vim has the basics for Go development: auto-completion, formatting, and debugging support.

### Quick Command Reference (Golang)
- **GoRun**: Executes your current file(s) with go run.
- **GoBuild**: Compiles your package with go build.
- **GoTest**: Runs tests for the current package.
- **GoCoverageToggle**: Toggles the display of test coverage results.
- **GoDef**: Jumps to a symbol or function definition (often mapped to gd in modern setups).
- **GoDoc**: Displays documentation for the identifier under the cursor in a split pane.
- **GoImport**: Manages package imports.
- **GoRename**: Renames the identifier under the cursor across all files in the package.

### GoDoc and Debugging
`godoc` and the Delve debugger (`dlv`) are installed by `install.sh`. Run docs from a project with `godoc -http :8080`. Prefer Delve over GDB.
