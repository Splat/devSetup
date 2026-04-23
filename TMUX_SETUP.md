# tmux Dev Environment

Persistent tmux layout for Go development with vim, Claude Code, and a debug window.
Session survives terminal closes and is auto-restored after machine restarts (via tmux-continuum).

## Layout

```
Window 1 — editor
┌───────────────────────────┬──────────────┐
│                           │              │
│   vim .                   │  file tree   │
│   (75%)                   │  lf/nnn/tree │
│                           │  (25%)       │
└───────────────────────────┴──────────────┘

Window 2 — claude
┌──────────────────────────────────────────┐
│   claude                                 │
└──────────────────────────────────────────┘

Window 3 — shell
┌──────────────────────────────────────────┐
│   go build / go run / go generate        │
├─────────────────────────┬────────────────┤
│   go test -v ./...      │   git / misc   │
└─────────────────────────┴────────────────┘

Window 4 — debug
┌──────────────────────────────────────────┐
│   dlv debug / dlv test                   │
├─────────────────────────┬────────────────┤
│   program output        │   logs / watch │
└─────────────────────────┴────────────────┘
```

## First-time machine setup

### 1. Install tmux (≥ 3.2)

```bash
# macOS
brew install tmux

# Ubuntu / Debian
sudo apt install tmux
```

### 2. Install TPM (tmux plugin manager)

```bash
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
```

### 3. Install a file explorer (pick one)

```bash
brew install lf      # recommended — fast, vim keybindings
# or
brew install nnn
```

Then wire `lf` to open files in the vim pane on the left:

```bash
mkdir -p ~/.config/lf
cp lfrc ~/.config/lf/lfrc
```

Pressing Enter on a file in `lf` will now run `:e <file>` in the left pane instead of opening it in place.

### 4. Install Delve (Go debugger)

```bash
go install github.com/go-delve/delve/cmd/dlv@latest
```

### 5. Copy config files

```bash
cp .tmux.conf ~/.tmux.conf
cp dev-session.sh ~/bin/dev-session   # or anywhere on $PATH
chmod +x ~/bin/dev-session
```

### 6. Start tmux and install plugins

```bash
tmux
# Inside tmux:
#   prefix + I   (Ctrl-a then Shift-i)
# Wait for TPM to install tmux-resurrect and tmux-continuum, then reload:
#   prefix + r
```

## Daily use

```bash
# Start or re-attach to your session (pass optional project root)
dev-session ~/code/myproject

# From inside an existing tmux session
dev-session   # attaches/switches without nesting
```

The session is named `dev`. If it already exists the script just attaches — safe to run repeatedly.

## Session persistence

`tmux-continuum` saves session state every 5 minutes and restores it automatically when the tmux server starts. After a reboot:

```bash
tmux        # sessions restore automatically
# or just:
dev-session
```

To manually save/restore:

```
prefix + Ctrl-s   → save now
prefix + Ctrl-r   → restore manually
```

## Key bindings (prefix = Ctrl-a)

| Keys | Action |
|------|--------|
| `prefix + \|` | Split vertical |
| `prefix + -` | Split horizontal |
| `prefix + h/j/k/l` | Move between panes |
| `prefix + H/J/K/L` | Resize panes |
| `Ctrl-h/j/k/l` | Move panes (vim-aware, no prefix needed) |
| `prefix + Enter` | Enter copy mode |
| `v` (copy mode) | Begin selection |
| `y` (copy mode) | Yank to system clipboard |
| `prefix + I` | Install TPM plugins |
| `prefix + Ctrl-s` | Save session |
| `prefix + Ctrl-r` | Restore session |

## vim integration

Add [vim-tmux-navigator](https://github.com/christoomey/vim-tmux-navigator) to get seamless `Ctrl-h/j/k/l` movement across vim splits and tmux panes without prefix:

```vim
" vim-plug
Plug 'christoomey/vim-tmux-navigator'
```

The `.tmux.conf` already contains the matching smart-detection block.
